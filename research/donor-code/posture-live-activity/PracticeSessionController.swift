// Practice sessions are iOS-only - they read AirPods head motion.
#if os(iOS)

import ActivityKit
import AudioToolbox
import Foundation
import SwiftData
import UIKit
import UserNotifications

/// Drives one bounded posture session (daily practice now; walks in a later
/// phase): owns the motion stream for its duration, scores every sample,
/// accrues elapsed time from observed samples only, and writes the results.
///
/// Deliberately NOT an extension of `AirpodsBackgroundMonitor` - the all-day
/// monitor is a process-scoped singleton with all-day semantics (retention
/// pruning, long haptic debounce). A session wants tighter feedback constants
/// and a lifecycle tied to a view. The two share `PostureScoring` and
/// `MinuteBucket` so their numbers always agree.
@MainActor
@Observable
final class PracticeSessionController {
    enum PauseReason: Equatable {
        case airpodsOut
        case user
    }

    enum Phase: Equatable {
        case idle
        /// Guided chin-tuck warm-up reps before the timed hold (practice only).
        case reps
        /// Armed, waiting for the first scored AirPods sample.
        case waiting
        case running
        case paused(PauseReason)
        case finished
    }

    struct Config: Sendable {
        let kind: PostureSessionKind
        let targetSeconds: Int
        let targetPercent: Int
        let level: Int
        /// Chin-tuck warm-up reps before the hold. 0 skips the warm-up
        /// (walks always pass 0).
        var repsTarget: Int = 0
        /// False for custom-length sessions that shouldn't advance the level
        /// ladder - they still credit the streak.
        var countsForLevel: Bool = true
        /// Walk goal is a distance rather than a duration. `targetSeconds`
        /// still acts as a safety cap so a stalled GPS can't run forever.
        var goalIsDistance: Bool = false
        /// Target distance in meters when `goalIsDistance` (walks only).
        var targetDistanceMeters: Double = 0
        /// Layer GPS on top of the pedometer for accurate walk distance.
        var useGPS: Bool = false
        /// Which posture ladder this practice session belongs to. nil for walks
        /// and legacy paths; scoring then falls back to the nearest baseline.
        var postureMode: PostureMode? = nil
        /// Pro unlocks the full ladder. Free sessions cap at
        /// `PracticeProgression.freeLevelCap`, and the summary must report the
        /// *capped* level so it can't promise a level the user can't play.
        var isPro: Bool = true
    }

    struct Result: Sendable {
        let kind: PostureSessionKind
        let alignedPercent: Int
        let completed: Bool
        let passed: Bool
        let goodSeconds: Int
        let borderlineSeconds: Int
        let badSeconds: Int
        /// Aligned fraction per segment (10s for practice, 60s for walks),
        /// for the summary strip.
        let timeline: [Double]
        let level: Int
        let newLevel: Int
        let leveledUp: Bool
        let streakDays: Int
        let levelProgressDone: Int
        let levelProgressNeeded: Int
        let levelPipAnimateIndex: Int?
        /// The ladder has more levels but this user is held at the free cap, so
        /// the summary points at Posture+ instead of a next level.
        var levelCapped: Bool = false
        /// Titles of badges this session newly earned, for the summary line.
        let newAchievementTitles: [String]
        /// Walk metrics (0 on practice sessions).
        var distanceMeters: Double = 0
        var steps: Int = 0
        var goalIsDistance: Bool = false
    }

    // MARK: - Observable state

    private(set) var phase: Phase = .idle
    private(set) var elapsedSeconds: Double = 0
    private(set) var currentQuality: PostureQuality = .good
    private(set) var result: Result?
    private(set) var config: Config?
    private(set) var lastError: String?

    /// Chin-tuck warm-up progress (only meaningful while `phase == .reps`).
    private(set) var repsCompleted = 0
    var repsTarget: Int { config?.repsTarget ?? 0 }
    private var repDetector = ChinTuckRepDetector()

    var remainingSeconds: Int {
        guard let config else { return 0 }
        return max(0, config.targetSeconds - Int(elapsedSeconds))
    }

    /// Weighted aligned fraction so far (good = 1, borderline = 0.5).
    var alignedFractionSoFar: Double {
        let total = goodSeconds + borderlineSeconds + badSeconds
        guard total > 0 else { return 0 }
        return (goodSeconds + borderlineSeconds * 0.5) / total
    }

    // MARK: - Internals

    private let motion = HeadphoneMotionService()
    private let context: ModelContext
    private let calibrationService: CalibrationService

    private var smoothedPitch: Double?
    private let smoothingAlpha = 0.15

    private var goodSeconds: Double = 0
    private var borderlineSeconds: Double = 0
    private var badSeconds: Double = 0
    private var minuteBucket = MinuteBucket()

    // Segment timeline for the summary strip (10s practice, 60s walk -
    // a 30-min walk at 10s segments would be an unreadable 180 bars).
    private var timeline: [Double] = []
    private var segmentSeconds: Double = 0
    private var segmentAligned: Double = 0
    private var segmentLength: Double = 10

    // In-session slouch nudge: tighter than the all-day monitor - the whole
    // point of practice is immediate feedback. Walks nudge slower and rarer.
    private var firstBadAt: Date?
    private var inBadBout = false
    private var lastHapticAt: Date = .distantPast
    private var slouchNudgeSeconds: TimeInterval = 15
    private var hapticDebounceSeconds: TimeInterval = 20

    // Walk mode: rolling window of raw samples; the verdict recomputes at
    // most once a second off the window median (gait bob cancels out).
    private var walkSamples: [(t: TimeInterval, pitch: Double)] = []
    private var lastWalkVerdictAt: TimeInterval = 0

    /// Walking's honest neutral (natural forward lean, head bob) differs from
    /// standing calibration, so the first 30s of the walk auto-captures the
    /// user's own walking head-pose as the baseline for the rest.
    private var walkWarmupPitches: [Double] = []
    private var autoWalkBaseline: Double?

    /// Live walk metrics (steps, distance, cadence) + the "actually walking"
    /// gate. Created lazily for walk sessions.
    private var walkMetrics: WalkMetricsService?

    /// Published for the walk UI: are we currently registering steps? When
    /// false the walk keeps its clock running (so the in-app countdown and
    /// the Live Activity/watch countdown never drift apart) but the time
    /// scores as rest - sitting still can't fake a good walk.
    private(set) var isWalkingNow = true

    // Live walk readouts for the UI (0 outside a walk).
    var walkSteps: Int { walkMetrics?.steps ?? 0 }
    var walkDistanceMeters: Double { walkMetrics?.distanceMeters ?? 0 }
    var walkUsingGPS: Bool { walkMetrics?.usingGPS ?? false }
    var walkLocationDenied: Bool { walkMetrics?.locationDenied ?? false }

    /// Distance still to walk toward a distance goal (meters), else 0.
    var walkDistanceRemaining: Double {
        guard let config, config.goalIsDistance else { return 0 }
        return max(0, config.targetDistanceMeters - walkDistanceMeters)
    }

    /// Progress toward the walk's goal (0…1): distance for distance goals,
    /// elapsed time otherwise.
    var walkProgressFraction: Double {
        guard let config else { return 0 }
        if config.goalIsDistance, config.targetDistanceMeters > 0 {
            return min(1, walkDistanceMeters / config.targetDistanceMeters)
        }
        guard config.targetSeconds > 0 else { return 0 }
        return min(1, elapsedSeconds / Double(config.targetSeconds))
    }

    /// Sessions under this long aren't worth a row - an instant cancel is
    /// noise, not an attempt.
    private static let minRecordSeconds: Double = 30

    private static let keepAliveToken = "session"

    // Live Activity: countdown + current alignment in the Dynamic Island
    // while the user switches apps. The countdown renders off `endDate`, so
    // only quality flips and pauses need pushes. We keep the id, not the
    // `Activity` object - it isn't Sendable, and each push looks it up
    // fresh inside its own task region.
    private var liveActivityID: String?
    private var lastActivityQuality: PostureQuality = .good
    private var lastActivityUpdateAt: Date = .distantPast

    var isAirpodsConnected: Bool { motion.isConnected }

    /// Tracked via lifecycle notifications - `UIApplication.shared` is
    /// unavailable in the extension targets that also compile Shared/.
    private var isAppInBackground = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(context: ModelContext) {
        self.context = context
        self.calibrationService = CalibrationService(context: context)
        motion.onSample = { [weak self] pitch, _, _ in
            self?.ingest(pitch: pitch, at: .now)
        }
        motion.onConnect = { [weak self] connected in
            self?.handleConnect(connected)
        }
        let center = NotificationCenter.default
        let toBackground = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor in self?.isAppInBackground = true }
        }
        let toForeground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor in self?.isAppInBackground = false }
        }
        lifecycleObservers = [toBackground, toForeground]
    }

    // MARK: - Config

    /// Count of passed practice sessions - the input to the level ramp.
    static func passedPracticeCount(context: ModelContext) -> Int {
        let practiceRaw = PostureSessionKind.practice.rawValue
        let descriptor = FetchDescriptor<PostureSession>(
            predicate: #Predicate { $0.kindRaw == practiceRaw && $0.passed }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Passed practice sessions for one posture ladder. Pre-split rows carry no
    /// mode (`postureModeRaw == ""`) and are grandfathered into *every* ladder
    /// so existing users keep their level when the standing/sitting split ships.
    static func passedPracticeCount(context: ModelContext, mode: PostureMode) -> Int {
        let practiceRaw = PostureSessionKind.practice.rawValue
        let modeRaw = mode.rawValue
        let descriptor = FetchDescriptor<PostureSession>(
            predicate: #Predicate {
                $0.kindRaw == practiceRaw && $0.passed
                    && ($0.postureModeRaw == modeRaw || $0.postureModeRaw == "")
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Today's practice config from the level ramp for one posture (free users
    /// cap at `PracticeProgression.freeLevelCap`). Each mode ramps on its own
    /// passed-session count.
    static func nextConfig(context: ModelContext, isPro: Bool, mode: PostureMode) -> Config {
        let passed = passedPracticeCount(context: context, mode: mode)
        let level = PracticeProgression.effectiveLevel(
            level: PracticeProgression.level(passedSessions: passed),
            isPro: isPro
        )
        // Every practice session opens with the chin-tuck warm-up, including
        // the first. The pre-start copy promises it, and it's the neck reset
        // that makes the hold worthwhile. If detection never lands (odd AirPods
        // pitch response), the reps screen surfaces a "Skip the warm-up" button
        // after ~10s so no one is stranded before any time is logged.
        let reps = PostureScoring.ChinTuck.defaultRepsTarget
        return Config(
            kind: .practice,
            targetSeconds: PracticeProgression.sessionSeconds(forLevel: level),
            targetPercent: PracticeProgression.targetPercent(forLevel: level),
            level: level,
            repsTarget: reps,
            postureMode: mode,
            isPro: isPro
        )
    }

    // MARK: - Lifecycle

    func start(config: Config) {
        guard phase == .idle || phase == .finished else { return }
        guard calibrationService.current()?.airpodsPitch != nil else {
            lastError = "Calibrate with AirPods before a session."
            return
        }
        self.config = config
        result = nil
        lastError = nil
        elapsedSeconds = 0
        goodSeconds = 0
        borderlineSeconds = 0
        badSeconds = 0
        timeline = []
        segmentSeconds = 0
        segmentAligned = 0
        smoothedPitch = nil
        firstBadAt = nil
        inBadBout = false
        minuteBucket = MinuteBucket()
        walkSamples = []
        lastWalkVerdictAt = 0
        walkWarmupPitches = []
        autoWalkBaseline = nil
        isWalkingNow = true
        currentQuality = .good
        repsCompleted = 0
        repDetector = ChinTuckRepDetector()
        if config.kind == .walk {
            segmentLength = 60
            slouchNudgeSeconds = PostureScoring.Walk.nudgeSustainSeconds
            hapticDebounceSeconds = PostureScoring.Walk.nudgeDebounceSeconds
            let metrics = WalkMetricsService()
            metrics.start(useGPS: config.useGPS)
            walkMetrics = metrics
        } else {
            segmentLength = 10
            slouchNudgeSeconds = 15
            hapticDebounceSeconds = 20
        }
        phase = (config.kind == .practice && config.repsTarget > 0) ? .reps : .waiting

        // Take exclusive ownership of the head-motion stream - iOS starves a
        // second CMHeadphoneMotionManager while the monitor's is live.
        AirpodsBackgroundMonitor.shared.suspendForForegroundRead()
        // Keep motion flowing through a screen lock for the bounded duration.
        AudioKeepAlive.shared.acquire(Self.keepAliveToken)
        motion.start()
        AnalyticsService.sessionStarted(source: .airpods, targetSeconds: config.targetSeconds)
    }

    func pauseByUser() {
        guard phase == .running || phase == .waiting else { return }
        persistFlush(minuteBucket.flush())
        motion.stop()
        phase = .paused(.user)
        updateLiveActivity(paused: true, force: true)
        AnalyticsService.sessionPaused()
    }

    func resume() {
        guard case .paused(.user) = phase else { return }
        phase = .waiting
        motion.start()
        AnalyticsService.sessionResumed()
    }

    /// End before the target. Writes an honest partial row (no streak or
    /// level credit) when the attempt was long enough to mean something.
    func endEarly() {
        guard phase != .idle, phase != .finished else { return }
        AnalyticsService.sessionCancelled()
        finish(completed: false)
    }

    /// Abandon without recording anything (view dismissed instantly).
    func cancel() {
        guard phase != .idle else { return }
        if elapsedSeconds >= Self.minRecordSeconds {
            endEarly()
            return
        }
        teardown()
        phase = .idle
        config = nil
    }

    // MARK: - Sample path

    private func handleConnect(_ connected: Bool) {
        guard phase == .running || phase == .waiting else { return }
        if !connected {
            persistFlush(minuteBucket.flush())
            firstBadAt = nil
            inBadBout = false
            smoothedPitch = nil
            phase = .paused(.airpodsOut)
            updateLiveActivity(paused: true, force: true)
        }
        // Reconnect: HeadphoneMotionService's wantsToRun re-arms motion on its
        // own; the next scored sample flips us back to .running in ingest.
    }

    /// Score one sample and advance the session clock by the observed dt.
    /// Internal (not private) so tests can drive synthetic streams.
    func ingest(pitch: Double, at now: Date) {
        switch phase {
        case .reps:
            ingestRep(pitch: pitch, at: now)
            return
        case .waiting, .paused(.airpodsOut):
            phase = .running
        case .running:
            break
        case .idle, .finished, .paused(.user):
            return
        }

        guard let config, let calibration = calibrationService.current(),
              let baseline = calibration.airpodsPitch else { return }

        // Walking gate + auto-baseline, before scoring. The clock never
        // holds: stationary time scores as rest instead, so the countdown
        // stays honest everywhere (app, Dynamic Island, watch) and standing
        // still can't bank aligned time.
        if config.kind == .walk {
            walkMetrics?.tick(now: now)
            let walking = walkMetrics?.isWalking ?? true
            if isWalkingNow != walking { isWalkingNow = walking }
            // With a saved walking baseline (captured once in the first-walk
            // setup) we score from the first second and skip the per-walk
            // auto-capture entirely. Only legacy users with no saved baseline
            // fall back to normalizing against this walk's own first 30s.
            if walking, calibration.airpodsWalkingPitch == nil {
                if elapsedSeconds <= PostureScoring.Walk.warmupSeconds {
                    walkWarmupPitches.append(pitch)
                } else if autoWalkBaseline == nil {
                    autoWalkBaseline = PostureScoring.median(walkWarmupPitches)
                }
            }
        }

        let quality: PostureQuality
        if config.kind == .walk {
            if isWalkingNow {
                quality = walkQuality(pitch: pitch, at: now, calibration: calibration, combined: baseline)
            } else {
                // Not registering steps: the time counts, aligned it is not.
                quality = .bad
            }
        } else {
            smoothedPitch = PostureScoring.smoothed(
                previous: smoothedPitch, sample: pitch, alpha: smoothingAlpha
            )
            let scoredPitch = smoothedPitch ?? pitch
            let reference = PostureScoring.postureReference(
                pitch: scoredPitch,
                standing: calibration.airpodsStandingPitch,
                sitting: calibration.airpodsSittingPitch,
                combined: baseline,
                standingSlouchDelta: calibration.standingSlouchDelta,
                sittingSlouchDelta: calibration.sittingSlouchDelta,
                fallbackSlouchDelta: calibration.slouchPitchDelta,
                mode: config.postureMode
            )
            quality = PostureScoring.quality(
                deviation: scoredPitch - reference.baseline,
                slouchDelta: reference.slouchDelta,
                sensitivity: GoalSettings.shared.sensitivity
            )
        }
        if quality != currentQuality { currentQuality = quality }

        // Elapsed accrues from observed sample gaps (clamped), never a Timer -
        // pods-out or a suspension can't credit phantom time, and pausing
        // falls out for free.
        let (credited, flush) = minuteBucket.accumulate(quality: quality, at: now)
        persistFlush(flush)
        elapsedSeconds += credited
        // A walk's first stretch (pocketing the phone, finding stride) runs
        // the clock but stays out of the score and timeline.
        let inWarmup = config.kind == .walk && elapsedSeconds <= PostureScoring.Walk.warmupSeconds
        if !inWarmup {
            switch quality {
            case .good: goodSeconds += credited
            case .borderline: borderlineSeconds += credited
            case .bad: badSeconds += credited
            }
            accrueTimeline(credited: credited, quality: quality)
        }
        if config.kind == .walk && !isWalkingNow {
            // Waiting at a light isn't a slouch - no buzz, and no carrying a
            // half-built bad bout into the next stretch of walking.
            firstBadAt = nil
            inBadBout = false
        } else {
            updateSlouchNudge(quality: quality, now: now)
        }

        startLiveActivityIfNeeded()
        updateLiveActivity(paused: false, force: false)

        if config.goalIsDistance {
            // Distance goal ends on distance; targetSeconds is a safety cap so
            // a stalled sensor can't run the session forever.
            if walkDistanceMeters >= config.targetDistanceMeters
                || (config.targetSeconds > 0 && Int(elapsedSeconds) >= config.targetSeconds) {
                finish(completed: true)
            }
        } else if Int(elapsedSeconds) >= config.targetSeconds {
            finish(completed: true)
        }
    }

    /// Chin-tuck warm-up: count retract-and-return cycles against the
    /// standing baseline. No session time or scoring accrues here - the
    /// clock starts with the hold.
    private func ingestRep(pitch: Double, at now: Date) {
        guard let calibration = calibrationService.current(),
              let baseline = calibration.airpodsStandingPitch ?? calibration.airpodsPitch else { return }
        let counted = repDetector.ingest(
            t: now.timeIntervalSinceReferenceDate, pitch: pitch, baseline: baseline
        )
        guard counted > 0 else { return }
        repsCompleted += counted
        AudioServicesPlaySystemSound(1519)
        if repsCompleted >= repsTarget {
            // Hand off to the hold; the next scored sample flips to .running.
            AnalyticsService.chinTuckWarmupCompleted(reps: repsCompleted)
            smoothedPitch = nil
            phase = .waiting
        }
    }

    /// Escape hatch for a warm-up that isn't detecting (bad fit, odd pitch
    /// response) - jump straight to the hold.
    func skipReps() {
        guard phase == .reps else { return }
        smoothedPitch = nil
        phase = .waiting
    }

    #if DEBUG
    /// Manual rep advance for simulator work - no motion stream there.
    func debugCountRep() {
        guard phase == .reps else { return }
        repsCompleted += 1
        if repsCompleted >= repsTarget {
            smoothedPitch = nil
            phase = .waiting
        }
    }
    #endif

    /// Walk verdict: median head pitch over the rolling window, judged
    /// against the standing baseline with relaxed thresholds. Recomputes at
    /// most once a second; between verdicts the last one holds.
    private func walkQuality(
        pitch: Double, at now: Date, calibration: Calibration, combined: Double
    ) -> PostureQuality {
        let t = now.timeIntervalSinceReferenceDate
        walkSamples.append((t, pitch))
        let cutoff = t - PostureScoring.Walk.windowSeconds
        if let firstKeep = walkSamples.firstIndex(where: { $0.t >= cutoff }), firstKeep > 0 {
            walkSamples.removeFirst(firstKeep)
        }
        guard t - lastWalkVerdictAt >= 1 else { return currentQuality }
        // The saved walking baseline (deliberately captured once in the
        // first-walk setup, or this walk's own warmup median as the legacy
        // fallback) is anchored to the standing calibration: walking earns a
        // small natural lean, but a capture taken mid-slouch can't drag the
        // whole scale down with it.
        let walkBaseline = PostureScoring.Walk.anchoredBaseline(
            walking: calibration.airpodsWalkingPitch ?? autoWalkBaseline,
            standing: calibration.airpodsStandingPitch ?? combined
        )
        guard let deviation = PostureScoring.walkWindowDeviation(
            samples: walkSamples, baseline: walkBaseline, now: t
        ) else { return currentQuality }
        lastWalkVerdictAt = t
        return PostureScoring.quality(
            deviation: deviation,
            slouchDelta: calibration.standingSlouchDelta ?? calibration.slouchPitchDelta,
            sensitivity: PostureScoring.Walk.sensitivity
        )
    }

    private func accrueTimeline(credited: Double, quality: PostureQuality) {
        segmentSeconds += credited
        switch quality {
        case .good: segmentAligned += credited
        case .borderline: segmentAligned += credited * 0.5
        case .bad: break
        }
        if segmentSeconds >= segmentLength {
            timeline.append(segmentAligned / segmentSeconds)
            segmentSeconds = 0
            segmentAligned = 0
        }
    }

    private func updateSlouchNudge(quality: PostureQuality, now: Date) {
        switch quality {
        case .good:
            firstBadAt = nil
            inBadBout = false
        case .borderline:
            break
        case .bad:
            if let started = firstBadAt {
                if !inBadBout, now.timeIntervalSince(started) >= slouchNudgeSeconds {
                    inBadBout = true
                    guard now.timeIntervalSince(lastHapticAt) >= hapticDebounceSeconds else { return }
                    lastHapticAt = now
                    AudioServicesPlaySystemSound(1520)
                }
            } else {
                firstBadAt = now
            }
        }
    }

    // MARK: - Finish

    private func finish(completed: Bool) {
        guard let config else { return }
        // Snapshot walk metrics before teardown stops the service.
        let walkDistance = config.kind == .walk ? walkDistanceMeters : 0
        let walkStepCount = config.kind == .walk ? walkSteps : 0
        teardown()

        if segmentSeconds >= 2 {
            timeline.append(segmentAligned / segmentSeconds)
        }

        let good = Int(goodSeconds.rounded())
        let borderline = Int(borderlineSeconds.rounded())
        let bad = Int(badSeconds.rounded())
        let alignedPercent = PostureScoring.sessionScore(
            goodSeconds: good, borderlineSeconds: borderline, badSeconds: bad
        )
        // `passed` means level credit, which only practice can earn - and
        // only at the ladder's own duration (custom lengths are streak-only).
        let passed = config.kind == .practice && completed && config.countsForLevel
            && alignedPercent >= config.targetPercent

        // Level math is scoped to this session's posture ladder (each posture
        // ramps independently). Non-practice paths fall back to the total.
        let passedBefore: Int = {
            if config.kind == .practice, let mode = config.postureMode {
                return Self.passedPracticeCount(context: context, mode: mode)
            }
            return Self.passedPracticeCount(context: context)
        }()
        // Report the level the user can actually *play*. Free users ramp only to
        // `freeLevelCap`, so the raw ladder would otherwise announce "Level 3
        // unlocked. Tomorrow's hold grows" while tomorrow's session stays at the
        // capped length forever.
        let levelBefore = PracticeProgression.effectiveLevel(
            level: PracticeProgression.level(passedSessions: passedBefore),
            isPro: config.isPro
        )

        // Snapshot the badge set before this session lands, so the summary
        // can celebrate anything newly earned.
        let sessionsBefore = (try? context.fetch(FetchDescriptor<PostureSession>())) ?? []
        let streakBefore = try? context.fetch(FetchDescriptor<StreakState>()).first
        let earnedBefore = AchievementCatalog.earnedIDs(
            streak: streakBefore, sessions: sessionsBefore, isPro: config.isPro
        )

        let row = PostureSession(
            durationSeconds: Int(elapsedSeconds.rounded()),
            score: alignedPercent,
            goodSeconds: good,
            borderlineSeconds: borderline,
            badSeconds: bad,
            source: .airpods,
            kind: config.kind,
            postureMode: config.postureMode,
            targetSeconds: config.targetSeconds,
            targetPercent: config.targetPercent,
            alignedPercent: alignedPercent,
            completed: completed,
            passed: passed,
            distanceMeters: walkDistance,
            steps: walkStepCount,
            goalIsDistance: config.goalIsDistance,
            targetDistanceMeters: config.targetDistanceMeters
        )
        row.startedAt = Date.now.addingTimeInterval(-elapsedSeconds)
        context.insert(row)
        try? context.save()

        var streakDays = 0
        if completed {
            let state = StreakService(context: context).recordSessionCompleted(at: .now)
            streakDays = state.currentStreak
        }

        // Walks never advance the practice level.
        let passedTotal = passedBefore + (passed ? 1 : 0)
        let rawLevel = PracticeProgression.level(passedSessions: passedTotal)
        let newLevel = PracticeProgression.effectiveLevel(level: rawLevel, isPro: config.isPro)
        let levelCapped = !config.isPro && rawLevel >= PracticeProgression.freeLevelCap

        let sessionsAfter = (try? context.fetch(FetchDescriptor<PostureSession>())) ?? []
        let streakAfter = try? context.fetch(FetchDescriptor<StreakState>()).first
        let newAchievements = AchievementCatalog
            .all(streak: streakAfter, sessions: sessionsAfter, isPro: config.isPro)
            .filter { $0.isEarned && !earnedBefore.contains($0.id) }
            .map(\.title)

        let progressAfter = PracticeProgression.progressInLevel(passedSessions: passedTotal)
        let pipAnimateIndex = passed ? progressAfter.done - 1 : nil

        result = Result(
            kind: config.kind,
            alignedPercent: alignedPercent,
            completed: completed,
            passed: passed,
            goodSeconds: good,
            borderlineSeconds: borderline,
            badSeconds: bad,
            timeline: timeline,
            level: config.level,
            newLevel: newLevel,
            leveledUp: newLevel > levelBefore,
            streakDays: streakDays,
            levelProgressDone: progressAfter.done,
            levelProgressNeeded: progressAfter.needed,
            levelPipAnimateIndex: pipAnimateIndex,
            levelCapped: levelCapped,
            newAchievementTitles: newAchievements,
            distanceMeters: walkDistance,
            steps: walkStepCount,
            goalIsDistance: config.goalIsDistance
        )
        phase = .finished
        AnalyticsService.sessionCompleted(
            score: alignedPercent, duration: Int(elapsedSeconds), source: .airpods
        )

        if completed, isAppInBackground {
            postCompletionNotification(kind: config.kind, alignedPercent: alignedPercent, passed: passed)
        }
    }

    /// Stop motion, hand the stream back, drop the keep-alive, flush minutes.
    private func teardown() {
        motion.stop()
        walkMetrics?.stop()
        persistFlush(minuteBucket.flush())
        AudioKeepAlive.shared.release(Self.keepAliveToken)
        AirpodsBackgroundMonitor.shared.resumeAfterForegroundRead()
        endLiveActivity()
    }

    // MARK: - Live Activity

    private func activityContentState(paused: Bool) -> PracticeActivityAttributes.ContentState {
        .init(
            endDate: Date.now.addingTimeInterval(Double(remainingSeconds)),
            quality: currentQuality.rawValue,
            alignedPercent: Int((alignedFractionSoFar * 100).rounded()),
            paused: paused
        )
    }

    /// End every practice/walk Live Activity, including ones orphaned by a
    /// prior crash or force-quit (ActivityKit activities outlive the process).
    /// Called on launch so a crashed walk's Dynamic Island countdown can't
    /// linger and stack a second one on the next walk ("multiple walks at
    /// once"), and defensively before we start a fresh one.
    static func endAllLiveActivities() async {
        for activity in Activity<PracticeActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Started on the first scored sample (after the warm-up), so the
    /// countdown it shows is the real hold.
    private func startLiveActivityIfNeeded() {
        guard liveActivityID == nil, let config,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let activity = try? Activity.request(
            attributes: PracticeActivityAttributes(kind: config.kind.rawValue),
            content: .init(state: activityContentState(paused: false), staleDate: nil)
        )
        liveActivityID = activity?.id
        lastActivityUpdateAt = .now
        lastActivityQuality = currentQuality
    }

    /// Push a state update. Unthrottled for pause/resume; sample-path calls
    /// pass `force: false` and only land on a quality flip or every ~15s
    /// (the countdown itself needs no pushes).
    private func updateLiveActivity(paused: Bool, force: Bool) {
        guard let id = liveActivityID else { return }
        let now = Date.now
        if !force {
            let qualityChanged = currentQuality != lastActivityQuality
            let stale = now.timeIntervalSince(lastActivityUpdateAt) >= 15
            guard qualityChanged || stale else { return }
        }
        lastActivityUpdateAt = now
        lastActivityQuality = currentQuality
        let state = activityContentState(paused: paused)
        Task.detached {
            guard let activity = Activity<PracticeActivityAttributes>.activities
                .first(where: { $0.id == id }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let id = liveActivityID else { return }
        liveActivityID = nil
        Task.detached {
            guard let activity = Activity<PracticeActivityAttributes>.activities
                .first(where: { $0.id == id }) else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func persistFlush(_ flush: MinuteBucket.Flush?) {
        guard let flush else { return }
        let row = PostureMinuteSample(
            minuteStart: flush.minuteStart,
            goodSeconds: flush.goodSeconds,
            borderlineSeconds: flush.borderlineSeconds,
            badSeconds: flush.badSeconds,
            source: .airpods
        )
        context.insert(row)
        try? context.save()
    }

    /// The session hit its target while the phone was locked or backgrounded -
    /// tell the user it's done so they aren't sitting tall for nothing.
    private func postCompletionNotification(kind: PostureSessionKind, alignedPercent: Int, passed: Bool) {
        let content = UNMutableNotificationContent()
        if kind == .walk {
            content.title = "walk done."
        } else {
            content.title = passed ? "practice done. target met." : "practice done."
        }
        content.body = "\(alignedPercent)% aligned today. Your streak is safe."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "posture.practice.finished",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

#endif
