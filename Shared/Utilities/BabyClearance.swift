import Foundation

struct BabySample: Sendable, Equatable, Identifiable {
    let id: String
    let sourceBundleID: String
    let sourceName: String
    let milligrams: Double
    let endDate: Date
    let isOurs: Bool
    let isLocalOnly: Bool
    /// The drink this entry was logged as, when one was named. Read back from
    /// the Apple Health sample so the label survives a reinstall.
    let drinkName: String?

    init(
        id: String,
        sourceBundleID: String,
        sourceName: String,
        milligrams: Double,
        endDate: Date,
        isOurs: Bool,
        isLocalOnly: Bool = false,
        drinkName: String? = nil
    ) {
        self.id = id
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.milligrams = milligrams
        self.endDate = endDate
        self.isOurs = isOurs
        self.isLocalOnly = isLocalOnly
        self.drinkName = drinkName
    }

    /// What to show in a list row: the drink if it was named, otherwise the
    /// source it arrived from.
    var displayName: String {
        if let drinkName, !drinkName.isEmpty { return drinkName }
        return isOurs ? "Baby" : sourceName
    }
}

struct BabyDaySummary: Sendable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let milligrams: Double
    let estimatedAtBedtime: Double
}

struct BabySourceSelection: Sendable, Equatable {
    var excludedBundleIDs: Set<String> = []

    func includes(bundleID: String, isOurs: Bool) -> Bool {
        isOurs || !excludedBundleIDs.contains(bundleID)
    }

    mutating func setIncluded(_ included: Bool, bundleID: String) {
        if included {
            excludedBundleIDs.remove(bundleID)
        } else {
            excludedBundleIDs.insert(bundleID)
        }
    }
}

struct BabySourceStatus: Sendable, Equatable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let milligrams: Double
    let latestEntry: Date
    let sampleCount: Int
    let isOurs: Bool
    let isIncluded: Bool
    let localOnlyMilligrams: Double
}

/// One logged dose and what the model says is left of it at a given moment.
/// The Now screen uses these to say where the running estimate came from, which
/// otherwise reads as a number the app invented, especially on a first launch
/// where every sample arrived from Apple Health rather than from a tap here.
struct BabyContribution: Sendable, Equatable, Identifiable {
    var id: String { sample.id }
    let sample: BabySample
    let remainingMilligrams: Double
}

struct BabyForecast: Sendable, Equatable {
    let at: Date
    let estimatedMilligrams: Double
    let fasterEstimate: Double
    let slowerEstimate: Double
}

enum BabyClearance {
    static let referenceHalfLifeRange = 4.0...6.0

    static func remaining(dose: Double, elapsedHours: Double, halfLifeHours: Double) -> Double {
        guard dose > 0, halfLifeHours > 0 else { return 0 }
        return dose * pow(0.5, max(elapsedHours, 0) / halfLifeHours)
    }

    static func included(
        samples: [BabySample],
        selection: BabySourceSelection
    ) -> [BabySample] {
        samples.filter { selection.includes(bundleID: $0.sourceBundleID, isOurs: $0.isOurs) }
    }

    static func consumedToday(
        samples: [BabySample],
        selection: BabySourceSelection,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double {
        let start = calendar.startOfDay(for: now)
        return included(samples: samples, selection: selection)
            .filter { $0.endDate >= start && $0.endDate <= now }
            .reduce(0) { $0 + max($1.milligrams, 0) }
    }

    static func remaining(
        samples: [BabySample],
        at date: Date,
        selection: BabySourceSelection,
        halfLifeHours: Double
    ) -> Double {
        included(samples: samples, selection: selection)
            .filter { $0.endDate <= date }
            .reduce(0) { total, sample in
                let elapsed = date.timeIntervalSince(sample.endDate) / 3600
                return total + remaining(
                    dose: max(sample.milligrams, 0),
                    elapsedHours: elapsed,
                    halfLifeHours: halfLifeHours
                )
            }
    }

    /// Per-dose breakdown of `remaining(samples:at:...)`, largest share first.
    /// Doses below `minimumMilligrams` are dropped so a 48-hour lookback does
    /// not list a dozen rows that each round to zero.
    static func contributions(
        samples: [BabySample],
        at date: Date,
        selection: BabySourceSelection,
        halfLifeHours: Double,
        minimumMilligrams: Double = 0.5
    ) -> [BabyContribution] {
        included(samples: samples, selection: selection)
            .filter { $0.endDate <= date }
            .map { sample in
                BabyContribution(
                    sample: sample,
                    remainingMilligrams: remaining(
                        dose: max(sample.milligrams, 0),
                        elapsedHours: date.timeIntervalSince(sample.endDate) / 3600,
                        halfLifeHours: halfLifeHours
                    )
                )
            }
            .filter { $0.remainingMilligrams >= minimumMilligrams }
            .sorted {
                if $0.remainingMilligrams != $1.remainingMilligrams {
                    return $0.remainingMilligrams > $1.remainingMilligrams
                }
                return $0.sample.endDate > $1.sample.endDate
            }
    }

    static func forecast(
        samples: [BabySample],
        at date: Date,
        selection: BabySourceSelection,
        halfLifeHours: Double
    ) -> BabyForecast {
        BabyForecast(
            at: date,
            estimatedMilligrams: remaining(
                samples: samples,
                at: date,
                selection: selection,
                halfLifeHours: halfLifeHours
            ),
            fasterEstimate: remaining(
                samples: samples,
                at: date,
                selection: selection,
                halfLifeHours: referenceHalfLifeRange.lowerBound
            ),
            slowerEstimate: remaining(
                samples: samples,
                at: date,
                selection: selection,
                halfLifeHours: referenceHalfLifeRange.upperBound
            )
        )
    }

    static func forecastAdding(
        dose: Double,
        at doseDate: Date,
        samples: [BabySample],
        forecastDate: Date,
        selection: BabySourceSelection,
        halfLifeHours: Double
    ) -> BabyForecast {
        let proposed = BabySample(
            id: "preview",
            sourceBundleID: babyOwnSourceBundleID,
            sourceName: "Baby",
            milligrams: dose,
            endDate: doseDate,
            isOurs: true
        )
        return forecast(
            samples: samples + [proposed],
            at: forecastDate,
            selection: selection,
            halfLifeHours: halfLifeHours
        )
    }

    static func timeToReach(
        currentMilligrams: Double,
        threshold: Double,
        halfLifeHours: Double
    ) -> TimeInterval? {
        guard currentMilligrams > 0, threshold > 0, halfLifeHours > 0 else { return nil }
        guard currentMilligrams > threshold else { return 0 }
        return halfLifeHours * log2(currentMilligrams / threshold) * 3600
    }

    static func latestTimeForDose(
        dose: Double,
        existingSamples: [BabySample],
        bedtime: Date,
        threshold: Double,
        selection: BabySourceSelection,
        halfLifeHours: Double
    ) -> Date? {
        guard dose > 0, threshold > 0, halfLifeHours > 0 else { return nil }
        let existingAtBedtime = remaining(
            samples: existingSamples,
            at: bedtime,
            selection: selection,
            halfLifeHours: halfLifeHours
        )
        let allowance = threshold - existingAtBedtime
        guard allowance > 0 else { return nil }
        guard allowance < dose else { return bedtime }
        let hours = halfLifeHours * log2(dose / allowance)
        return bedtime.addingTimeInterval(-hours * 3600)
    }

    static func sources(
        samples: [BabySample],
        selection: BabySourceSelection
    ) -> [BabySourceStatus] {
        var grouped: [String: [BabySample]] = [:]
        for sample in samples {
            let key = sample.isOurs ? babyOwnSourceBundleID : sample.sourceBundleID
            grouped[key, default: []].append(sample)
        }
        return grouped.compactMap { bundleID, group in
            guard let newest = group.max(by: { $0.endDate < $1.endDate }) else { return nil }
            let isOurs = group.contains { $0.isOurs }
            return BabySourceStatus(
                bundleID: bundleID,
                name: isOurs ? "Baby" : newest.sourceName,
                milligrams: group.reduce(0) { $0 + max($1.milligrams, 0) },
                latestEntry: newest.endDate,
                sampleCount: group.count,
                isOurs: isOurs,
                isIncluded: selection.includes(bundleID: bundleID, isOurs: isOurs),
                localOnlyMilligrams: group.reduce(0) { $0 + ($1.isLocalOnly ? max($1.milligrams, 0) : 0) }
            )
        }
        .sorted {
            if $0.isOurs != $1.isOurs { return $0.isOurs }
            if $0.milligrams != $1.milligrams { return $0.milligrams > $1.milligrams }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
