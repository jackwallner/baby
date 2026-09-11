import Foundation

struct CaffeineSample: Sendable, Equatable, Identifiable {
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
        return isOurs ? "Caffeine" : sourceName
    }
}

struct CaffeineDaySummary: Sendable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let milligrams: Double
    let estimatedAtBedtime: Double
}

struct CaffeineSourceSelection: Sendable, Equatable {
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

struct CaffeineSourceStatus: Sendable, Equatable, Identifiable {
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
struct CaffeineContribution: Sendable, Equatable, Identifiable {
    var id: String { sample.id }
    let sample: CaffeineSample
    let remainingMilligrams: Double
}

struct CaffeineForecast: Sendable, Equatable {
    let at: Date
    let estimatedMilligrams: Double
    let fasterEstimate: Double
    let slowerEstimate: Double
}

enum CaffeineClearance {
    static let referenceHalfLifeRange = 4.0...6.0

    static func remaining(dose: Double, elapsedHours: Double, halfLifeHours: Double) -> Double {
        guard dose > 0, halfLifeHours > 0 else { return 0 }
        return dose * pow(0.5, max(elapsedHours, 0) / halfLifeHours)
    }

    static func included(
        samples: [CaffeineSample],
        selection: CaffeineSourceSelection
    ) -> [CaffeineSample] {
        samples.filter { selection.includes(bundleID: $0.sourceBundleID, isOurs: $0.isOurs) }
    }

    static func consumedToday(
        samples: [CaffeineSample],
        selection: CaffeineSourceSelection,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double {
        let start = calendar.startOfDay(for: now)
        return included(samples: samples, selection: selection)
            .filter { $0.endDate >= start && $0.endDate <= now }
            .reduce(0) { $0 + max($1.milligrams, 0) }
    }

    static func remaining(
        samples: [CaffeineSample],
        at date: Date,
        selection: CaffeineSourceSelection,
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
        samples: [CaffeineSample],
        at date: Date,
        selection: CaffeineSourceSelection,
        halfLifeHours: Double,
        minimumMilligrams: Double = 0.5
    ) -> [CaffeineContribution] {
        included(samples: samples, selection: selection)
            .filter { $0.endDate <= date }
            .map { sample in
                CaffeineContribution(
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
        samples: [CaffeineSample],
        at date: Date,
        selection: CaffeineSourceSelection,
        halfLifeHours: Double
    ) -> CaffeineForecast {
        CaffeineForecast(
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
        samples: [CaffeineSample],
        forecastDate: Date,
        selection: CaffeineSourceSelection,
        halfLifeHours: Double
    ) -> CaffeineForecast {
        let proposed = CaffeineSample(
            id: "preview",
            sourceBundleID: caffeineOwnSourceBundleID,
            sourceName: "Caffeine",
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
        existingSamples: [CaffeineSample],
        bedtime: Date,
        threshold: Double,
        selection: CaffeineSourceSelection,
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
        samples: [CaffeineSample],
        selection: CaffeineSourceSelection
    ) -> [CaffeineSourceStatus] {
        var grouped: [String: [CaffeineSample]] = [:]
        for sample in samples {
            let key = sample.isOurs ? caffeineOwnSourceBundleID : sample.sourceBundleID
            grouped[key, default: []].append(sample)
        }
        return grouped.compactMap { bundleID, group in
            guard let newest = group.max(by: { $0.endDate < $1.endDate }) else { return nil }
            let isOurs = group.contains { $0.isOurs }
            return CaffeineSourceStatus(
                bundleID: bundleID,
                name: isOurs ? "Caffeine" : newest.sourceName,
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
