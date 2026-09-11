import Foundation

/// A named quick-log button. The milligram figure is what gets logged; the name
/// is carried into the Apple Health sample metadata so the entry is still
/// recognisable months later in the Health app.
struct DrinkPreset: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(name)-\(Int(milligrams))" }
    var name: String
    var milligrams: Double
    var symbolName: String

    init(name: String, milligrams: Double, symbolName: String = "cup.and.saucer.fill") {
        self.name = name
        self.milligrams = milligrams
        self.symbolName = symbolName
    }
}

/// Typical caffeine content for common drinks, used to seed presets and to give
/// the preview sheet a picker instead of a bare stepper.
///
/// These are published averages for a standard serving. Actual content varies
/// with brew, bean, and size, which is why every figure stays editable.
enum DrinkCatalog {
    struct Category: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let drinks: [DrinkPreset]
    }

    static let coffee = Category(name: "Coffee", drinks: [
        DrinkPreset(name: "Drip coffee", milligrams: 95, symbolName: "cup.and.saucer.fill"),
        DrinkPreset(name: "Espresso", milligrams: 64, symbolName: "cup.and.saucer.fill"),
        DrinkPreset(name: "Double espresso", milligrams: 128, symbolName: "cup.and.saucer.fill"),
        DrinkPreset(name: "Latte", milligrams: 128, symbolName: "mug.fill"),
        DrinkPreset(name: "Cold brew", milligrams: 205, symbolName: "takeoutbag.and.cup.and.straw.fill"),
        DrinkPreset(name: "Instant coffee", milligrams: 62, symbolName: "mug.fill"),
        DrinkPreset(name: "Decaf coffee", milligrams: 3, symbolName: "cup.and.saucer"),
    ])

    static let tea = Category(name: "Tea", drinks: [
        DrinkPreset(name: "Black tea", milligrams: 47, symbolName: "cup.and.saucer.fill"),
        DrinkPreset(name: "Green tea", milligrams: 28, symbolName: "leaf.fill"),
        DrinkPreset(name: "Matcha", milligrams: 70, symbolName: "leaf.fill"),
        DrinkPreset(name: "Chai latte", milligrams: 48, symbolName: "mug.fill"),
        DrinkPreset(name: "Yerba mate", milligrams: 85, symbolName: "leaf.fill"),
    ])

    static let energy = Category(name: "Energy", drinks: [
        DrinkPreset(name: "Energy drink", milligrams: 80, symbolName: "bolt.fill"),
        DrinkPreset(name: "Large energy drink", milligrams: 160, symbolName: "bolt.fill"),
        DrinkPreset(name: "Energy shot", milligrams: 200, symbolName: "bolt.circle.fill"),
        DrinkPreset(name: "Pre-workout", milligrams: 200, symbolName: "figure.strengthtraining.traditional"),
    ])

    static let other = Category(name: "Other", drinks: [
        DrinkPreset(name: "Cola", milligrams: 34, symbolName: "waterbottle.fill"),
        DrinkPreset(name: "Diet cola", milligrams: 46, symbolName: "waterbottle.fill"),
        DrinkPreset(name: "Dark chocolate", milligrams: 24, symbolName: "square.fill"),
        DrinkPreset(name: "Caffeine pill", milligrams: 100, symbolName: "pills.fill"),
    ])

    static let categories: [Category] = [coffee, tea, energy, other]

    static var allDrinks: [DrinkPreset] { categories.flatMap(\.drinks) }

    /// Seeds the three quick-log buttons a new install starts with.
    static let defaultPresets: [DrinkPreset] = [
        DrinkPreset(name: "Drip coffee", milligrams: 95, symbolName: "cup.and.saucer.fill"),
        DrinkPreset(name: "Double espresso", milligrams: 128, symbolName: "cup.and.saucer.fill"),
        DrinkPreset(name: "Energy drink", milligrams: 80, symbolName: "bolt.fill"),
    ]

    /// Best-effort name for a bare milligram figure, used when migrating presets
    /// saved before drinks had names and when labelling a manual dose.
    static func closestName(to milligrams: Double) -> DrinkPreset {
        let match = allDrinks.min { lhs, rhs in
            abs(lhs.milligrams - milligrams) < abs(rhs.milligrams - milligrams)
        }
        guard let match, abs(match.milligrams - milligrams) <= 8 else {
            return DrinkPreset(name: "Caffeine", milligrams: milligrams, symbolName: "drop.fill")
        }
        return DrinkPreset(name: match.name, milligrams: milligrams, symbolName: match.symbolName)
    }
}
