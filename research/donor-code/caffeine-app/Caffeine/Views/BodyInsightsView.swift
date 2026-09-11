import SwiftUI

/// Caffeine measured against the body data already in Apple Health.
///
/// Every claim on this screen is phrased as an observation about what was
/// recorded, never as an effect the app has established or a health outcome it
/// promises. That is both honest and what Guideline 1.4.1 requires of a
/// wellness app.
struct BodyInsightsView: View {
    @EnvironmentObject private var settings: CaffeineSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var insights = HealthInsightsService.shared
    @State private var upgradeFocus: PlusFeature?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !settings.bodyInsightsEnabled || !insights.isAuthorizationRequested {
                    connectCard
                } else if insights.isLoading && insights.report.records.isEmpty {
                    ProgressView("Reading Apple Health")
                        .tint(Theme.cyan)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    // The cutoff is what this app has that a half-life
                    // calculator does not, so it renders for everyone. It used
                    // to sit behind the lock, which meant the one screen that
                    // distinguishes Caffeine could not be reached without a
                    // purchase. The comparisons behind it are still Caffeine+.
                    cutoffCard
                    if store.isPro {
                        comparisonSection
                        doseResponseSection
                        bodyContextSection
                        missingDataNote
                    } else {
                        lockedShowcase
                    }
                }
                disclaimer
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Your Cutoff")
        .refreshable { await insights.refresh(force: true) }
        .task {
            guard settings.bodyInsightsEnabled else { return }
            await insights.refresh()
        }
        .sheet(item: $upgradeFocus) { focus in
            CaffeinePaywallView(paywallImpressionID: "caffeine_body_\(focus.rawValue)", focus: focus)
        }
    }

    // MARK: - Connect

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.forecastGradient)
            Text("Stop guessing at the 5 hour average")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The half-life model is the same for everyone. Your sleep is not. With read-only access to the sleep and heart data already in Apple Health, Caffeine can line your higher-caffeine days up against your lower ones and report what was actually recorded.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                questionRow("moon.stars.fill", "At what bedtime estimate does my sleep get shorter?")
                questionRow("waveform.path.ecg", "Do my heavier days show in resting heart rate or HRV?")
                questionRow("heart.fill", "What does my heart rate do after a dose?")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))

            Text("Reads \(BodyMetric.allCases.count) categories plus workouts, body mass, age and sex. Nothing is written, nothing leaves your device, and turning this off changes nothing about logging or the bedtime forecast.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Connect Apple Health") {
                Task {
                    let granted = await insights.requestAuthorization()
                    settings.bodyInsightsEnabled = granted
                    if granted { await insights.refresh(force: true) }
                }
            }
            .buttonStyle(PaywallCTAStyle())

            Text("Apple never tells an app which read permissions you granted. If a category stays empty here, it either has no data or was left off in the Health app.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Cutoff

    private var cutoffCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR CUTOFF, FROM YOUR NIGHTS")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)

            switch insights.report.cutoff {
            case let .insufficientData(have, need):
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(have) of \(need) nights")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Keep logging. Once there are \(need) nights with both caffeine and recorded sleep, Caffeine looks for the bedtime estimate above which your own sleep ran shorter.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    ProgressView(value: Double(have), total: Double(need))
                        .tint(Theme.cyan)
                    cutoffExample
                }
            case let .noMeasurableDifference(nights):
                VStack(alignment: .leading, spacing: 8) {
                    Text("No clear difference")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Across \(nights) nights, your recorded sleep was about the same whether the bedtime estimate was high or low. That is a real answer, and a common one.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            case let .found(cutoff):
                VStack(alignment: .leading, spacing: 8) {
                    Text(CaffeineFormat.milligrams(cutoff.milligrams))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("On nights when your estimate at bedtime was at or above this, your recorded sleep averaged \(CaffeineInsights.durationText(cutoff.sleepDelta)) shorter than on nights below it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(cutoff.nightsAbove) nights above · \(cutoff.nightsBelow) nights below")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if abs(cutoff.milligrams - settings.bedtimeThreshold) >= 5 {
                        Button("Use \(CaffeineFormat.milligrams(cutoff.milligrams)) as my bedtime preference") {
                            settings.bedtimeThreshold = min(max(cutoff.milligrams, 5), 100)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cyan)
                    }
                }
            }

            Text("An association in your own records, not a safe limit and not a recommendation. Plenty of things other than caffeine change how you sleep.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cyan.opacity(0.22), lineWidth: 1)
        )
    }

    /// A worked example of the finding, shown only while the real one is still
    /// accumulating.
    ///
    /// Twenty-one nights is a long time to look at a progress bar and not know
    /// what it is counting towards, and a reviewer or a first-day user would
    /// otherwise never see the one output that separates this app from a
    /// half-life calculator. Every number here is fixed and labelled as an
    /// example, so it can never be mistaken for a reading of this person.
    private var cutoffExample: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXAMPLE OF THE FINDING · NOT YOUR DATA")
                .font(.caption2.bold())
                .foregroundStyle(Theme.warning)
            Text("92 mg")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text("On nights when the estimate at bedtime was at or above this, recorded sleep averaged 41 minutes shorter than on nights below it.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("14 nights above · 9 nights below")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.warning.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example of the finding, not your data. 92 milligrams. On nights when the estimate at bedtime was at or above this, recorded sleep averaged 41 minutes shorter than on nights below it.")
    }

    // MARK: - Comparisons

    @ViewBuilder
    private var comparisonSection: some View {
        let overnight = insights.report.comparisons.filter(\.metric.isOvernight)
        let daytime = insights.report.comparisons.filter { !$0.metric.isOvernight }

        if overnight.isEmpty && daytime.isEmpty {
            emptyComparisonCard
        } else {
            if !overnight.isEmpty {
                comparisonCard(
                    title: "THE NIGHT AFTER",
                    caption: "Nights split at \(CaffeineFormat.milligrams(overnight[0].splitMilligrams)) estimated at bedtime.",
                    comparisons: overnight
                )
            }
            if !daytime.isEmpty {
                comparisonCard(
                    title: "THE DAY ITSELF",
                    caption: "Days split at \(CaffeineFormat.milligrams(daytime[0].splitMilligrams)) consumed.",
                    comparisons: daytime
                )
            }
        }
    }

    private func comparisonCard(title: String, caption: String, comparisons: [MetricComparison]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(comparisons) { comparison in
                ComparisonRow(comparison: comparison)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var emptyComparisonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not enough overlapping days yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("A comparison needs at least \(CaffeineInsights.minimumRecords) days that have both a caffeine total and the measurement, with \(CaffeineInsights.minimumPerGroup) days on each side of your median. Small samples produce confident-looking noise, so Caffeine waits.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Dose response and body context

    @ViewBuilder
    private var doseResponseSection: some View {
        if insights.report.heartRateResponse != nil || insights.report.workouts != nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("AROUND EACH DRINK")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)

                if let response = insights.report.heartRateResponse {
                    insightRow(
                        icon: "heart.fill",
                        title: "Heart rate after a dose",
                        value: String(format: "%+.1f bpm", response.delta),
                        detail: "Averaged over \(response.doseCount) doses: \(Int(response.baselineBPM.rounded())) bpm in the hour before, \(Int(response.afterBPM.rounded())) bpm in the 20 to 90 minutes after."
                    )
                }

                if let workouts = insights.report.workouts {
                    insightRow(
                        icon: "figure.run",
                        title: "On board at your workouts",
                        value: CaffeineFormat.milligrams(workouts.averageOnBoard),
                        detail: "Across \(workouts.workoutCount) workouts, typically starting around \(CaffeineInsights.clockText(minutesAfterMidnight: workouts.typicalStartMinutes))."
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    @ViewBuilder
    private var bodyContextSection: some View {
        let report = insights.report
        if report.doseIntensity != nil || report.halfLifeSuggestion != nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR BODY, YOUR MODEL")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)

                if let intensity = report.doseIntensity, intensity.milligrams > 0 {
                    insightRow(
                        icon: "scalemass.fill",
                        title: "Today, per kilogram",
                        value: String(format: "%.1f mg/kg", intensity.milligramsPerKilogram),
                        detail: "\(CaffeineFormat.milligrams(intensity.milligrams)) against \(Int(intensity.bodyMassKilograms.rounded())) kg from Apple Health."
                    )
                }

                if let suggestion = report.halfLifeSuggestion {
                    insightRow(
                        icon: "figure.stand",
                        title: "Suggested half-life",
                        value: String(format: "%.1f hours", suggestion.hours),
                        detail: suggestion.reason + " A starting point from published averages for your age band, not a measurement of your own clearance."
                    )
                    if abs(suggestion.hours - settings.halfLifeHours) >= 0.25 {
                        Button("Use \(String(format: "%.1f", suggestion.hours)) hours") {
                            settings.halfLifeHours = suggestion.hours
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cyan)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    private func insightRow(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(value)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Locked showcase

    /// What a free user sees under the cutoff once body data is connected.
    ///
    /// The verdict itself is free: it is the answer no other caffeine app can
    /// give, so hiding it hid the reason to want the app at all. What is still
    /// Caffeine+ is everything that sits underneath the verdict, and it is
    /// pitched with the person's own findings rendered and blurred rather than
    /// with a list of feature names.
    private var lockedShowcase: some View {
        VStack(spacing: 18) {
            if hasFindingsToTease {
                blurredFindings
            } else {
                whatItAnswersCard
            }
            upgradeCard
        }
    }

    private var hasFindingsToTease: Bool {
        !insights.report.comparisons.isEmpty
    }

    /// The user's own findings, rendered and then blurred. Nothing here is
    /// invented: the numbers under the blur are the ones Caffeine+ reveals.
    private var blurredFindings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("Ready now", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.violet)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(findingsHeadline)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(insights.report.comparisons.prefix(3)) { comparison in
                        ComparisonRow(comparison: comparison)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .blur(radius: 7)
                .accessibilityHidden(true)

                Image(systemName: "lock.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(16)
                    .background(.ultraThinMaterial, in: Circle())
            }
            // Fixed, because the teaser's height would otherwise be set by
            // however many comparisons this person happens to have, and the CTA
            // under it has to land on the first screen either way.
            .frame(height: 180)
            .clipped()

            Text("These are your own numbers, blurred until Caffeine+.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.violet.opacity(0.3), lineWidth: 1)
        )
    }

    private var findingsHeadline: String {
        let count = insights.report.comparisons.count
        return "\(count) \(count == 1 ? "comparison is" : "comparisons are") worked out and waiting"
    }

    /// Shown before there is anything real to blur. States the questions this
    /// person's own data will answer, without pretending to have answered one.
    private var whatItAnswersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Caffeine+", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(Theme.violet)
            Text("Questions your own record answers")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 12) {
                questionRow("moon.stars.fill", "At what bedtime estimate does my sleep actually get shorter?")
                questionRow("waveform.path.ecg", "Do my higher-caffeine days show up in resting heart rate or HRV?")
                questionRow("heart.fill", "What does my heart rate do in the 90 minutes after a dose?")
                questionRow("figure.run", "How much is modeled on board when I start a workout?")
            }
            Text("Caffeine answers each from your own days, or says there is not enough overlap yet. It will not manufacture a finding out of a small sample.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func questionRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var upgradeCard: some View {
        VStack(spacing: 10) {
            Button(store.shortConversionCTALabel) { upgradeFocus = .bodyComparisons }
                .buttonStyle(PaywallCTAStyle())
            Text("Also unlocks 90 days of history, custom quick-log drinks, and the bedtime reminder.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Footers

    @ViewBuilder
    private var missingDataNote: some View {
        let empty = insights.report.emptyMetrics
        if !empty.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No data for \(empty.map(\.title).joined(separator: ", "))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Either nothing has been recorded for those, or they were left off when you granted access. Health › Sharing › Apps controls what Caffeine can read.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                if let url = HealthKitService.privacySettingsURL {
                    Link("Open Settings", destination: url)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.cyan)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var disclaimer: some View {
        Text("Caffeine describes what Apple Health already recorded alongside your intake. It does not diagnose, treat, or prevent anything, and it is not a substitute for advice from a clinician.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
    }
}

private struct ComparisonRow: View {
    let comparison: MetricComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: comparison.metric.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 22)
                Text(comparison.metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(headline)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(comparison.isMeaningful ? Theme.textPrimary : Theme.textSecondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var headline: String {
        guard comparison.isMeaningful else { return "about the same" }
        let direction = comparison.delta > 0 ? "+" : "−"
        return "\(direction)\(comparison.metric.differenceText(comparison.delta))"
    }

    private var detail: String {
        let lower = comparison.metric.formatted(comparison.lowerMean)
        let higher = comparison.metric.formatted(comparison.higherMean)
        let counts = "\(comparison.lowerCount) lower, \(comparison.higherCount) higher"
        guard comparison.isMeaningful else {
            return "\(lower) on lower days, \(higher) on higher days. Within normal variation (\(counts))."
        }
        return "\(lower) on lower-caffeine days, \(higher) on higher ones (\(counts))."
    }
}
