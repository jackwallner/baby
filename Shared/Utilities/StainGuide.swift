import Foundation

/// The stain helper: what to do about a blowout, spit-up, breast milk or
/// formula, using only what the parent says they have at home.
///
/// This is laundry advice, not health advice, so none of the 1.4.1 wording
/// rules apply to it. Two safety rules do, and they are enforced by the shape
/// of the data rather than by remembering: every step names at most one
/// product, and the list always opens with "check the care label".
enum StainGuide {
    enum Supply: String, CaseIterable, Codable, Sendable, Identifiable {
        case dishSoap
        case detergent
        case oxygenBleach
        case hydrogenPeroxide
        case whiteVinegar
        case bakingSoda

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dishSoap: String(localized: "Dish soap")
            case .detergent: String(localized: "Laundry detergent")
            case .oxygenBleach: String(localized: "Oxygen bleach (OxiClean)")
            case .hydrogenPeroxide: String(localized: "Hydrogen peroxide 3%")
            case .whiteVinegar: String(localized: "White vinegar")
            case .bakingSoda: String(localized: "Baking soda")
            }
        }

        var symbolName: String {
            switch self {
            case .dishSoap: "drop.circle.fill"
            case .detergent: "washer.fill"
            case .oxygenBleach: "sparkles"
            case .hydrogenPeroxide: "flask.fill"
            case .whiteVinegar: "waterbottle.fill"
            case .bakingSoda: "cube.fill"
            }
        }

        /// Shown under the item at setup, so the choice is not a guess.
        var hint: String {
            switch self {
            case .dishSoap: String(localized: "The blue kind by the sink.")
            case .detergent: String(localized: "Most have enzymes, which is what breaks milk and poop down.")
            case .oxygenBleach: String(localized: "Colour-safe powder. Not chlorine bleach.")
            case .hydrogenPeroxide: String(localized: "The brown bottle from the medicine cabinet.")
            case .whiteVinegar: String(localized: "For the sour-milk smell.")
            case .bakingSoda: String(localized: "For smell, not for the stain.")
            }
        }
    }

    enum Stain: String, CaseIterable, Identifiable, Sendable {
        case blowout
        case poop
        case spitUp
        case breastMilk
        case formula

        var id: String { rawValue }

        var label: String {
            switch self {
            case .blowout: String(localized: "Blowout")
            case .poop: String(localized: "Poop")
            case .spitUp: String(localized: "Spit-up")
            case .breastMilk: String(localized: "Breast milk")
            case .formula: String(localized: "Formula")
            }
        }

        /// The segmented control is five wide on a 390pt screen, so it gets
        /// the short words and the rest of the app gets the real ones.
        var shortLabel: String {
            switch self {
            case .blowout: String(localized: "Blowout")
            case .poop: String(localized: "Poop")
            case .spitUp: String(localized: "Spit-up")
            case .breastMilk: String(localized: "Milk")
            case .formula: String(localized: "Formula")
            }
        }

        var symbolName: String {
            switch self {
            case .blowout: "exclamationmark.triangle.fill"
            case .poop: "drop.triangle.fill"
            case .spitUp: "arrow.up.circle.fill"
            case .breastMilk: "drop.fill"
            case .formula: "waterbottle.fill"
            }
        }

        /// The one thing to do in the first ten seconds, before any product.
        var firstMove: String {
            switch self {
            case .blowout: String(localized: "Get it off the skin first, then peel the clothes downward if you can, not over the head.")
            case .poop: String(localized: "Lift the solids off with the edge of a wipe. Don't rub.")
            case .spitUp: String(localized: "Blot, don't rub. Rubbing pushes it into the weave.")
            case .breastMilk: String(localized: "Rinse it now if you can. Dried milk is a different job.")
            case .formula: String(localized: "Rinse it now if you can. Dried formula is a different job.")
            }
        }
    }

    struct Step: Identifiable, Sendable {
        var id: String { title }
        /// At most one product per step. Two products in one instruction is
        /// how people end up mixing things in a sink.
        var supply: Supply?
        var title: String
        var detail: String
        /// Shown in the step when it only applies to some fabrics.
        var caution: String?
    }

    /// Said once, at the top, never repeated per step.
    static let careLabelRule = String(localized: "Check the care label first, and never put two products on the fabric in the same step. Rinse in between.")

    static let neverRule = String(localized: "No chlorine bleach on baby clothes here, and never mix hydrogen peroxide or vinegar with anything else.")

    // MARK: - Steps

    private static let rinse = Step(
        supply: nil,
        title: String(localized: "Cold water, from the back"),
        detail: String(localized: "Hold the fabric wrong side up and run cold water through the back of the stain so it goes out the way it came in. Never hot: heat cooks milk and poop into the fibres."),
        caution: nil
    )

    private static let dishSoap = Step(
        supply: .dishSoap,
        title: String(localized: "A drop of dish soap"),
        detail: String(localized: "Work one drop in with a fingertip, wait five minutes, rinse cold. It is built to lift the fat in milk, which is half of what a baby stain is."),
        caution: nil
    )

    private static let detergent = Step(
        supply: .detergent,
        title: String(localized: "Rub in a little detergent"),
        detail: String(localized: "Enzymes in ordinary laundry detergent break down protein. Rub a little straight into the damp stain and leave it fifteen minutes before washing."),
        caution: nil
    )

    private static let oxygenSoak = Step(
        supply: .oxygenBleach,
        title: String(localized: "Soak in oxygen bleach"),
        detail: String(localized: "Dissolve the powder in warm water to the dose on the tub, submerge the garment, and leave it one to eight hours. This is the one that gets old stains out."),
        caution: String(localized: "Colour-safe, but check the label for wool and silk.")
    )

    private static let sun = Step(
        supply: nil,
        title: String(localized: "Lay it in the sun, still damp"),
        detail: String(localized: "Sunlight fades the yellow of breastfed poop and milk better than anything in the cupboard, and it is free. A few hours, damp, stain side up."),
        caution: nil
    )

    private static let peroxide = Step(
        supply: .hydrogenPeroxide,
        title: String(localized: "Dab hydrogen peroxide"),
        detail: String(localized: "Dab it on, wait ten minutes, rinse cold. Rinse off any earlier product before this one."),
        caution: String(localized: "Whites and colourfast fabrics only. Test a hidden seam first.")
    )

    private static let vinegarSmell = Step(
        supply: .whiteVinegar,
        title: String(localized: "Soak for the sour smell"),
        detail: String(localized: "One part white vinegar to four parts cool water, thirty minutes, then rinse. This is for the smell that survives the wash, not for the mark."),
        caution: String(localized: "On its own, in clean water. Never alongside peroxide or bleach.")
    )

    private static let bakingSodaSmell = Step(
        supply: .bakingSoda,
        title: String(localized: "Baking soda paste for the smell"),
        detail: String(localized: "A spoon of baking soda with a little water, spread on, thirty minutes, brush off. Again: smell, not stain."),
        caution: nil
    )

    private static let washAndCheck = Step(
        supply: nil,
        title: String(localized: "Wash, then look before it dries"),
        detail: String(localized: "Wash as warm as the care label allows, then check the garment while it is still wet. A dryer sets whatever is left, and after that it is permanent."),
        caution: nil
    )

    /// The steps for this stain, in the order to try them, with anything the
    /// parent does not own left out.
    static func steps(for stain: Stain, owning supplies: Set<Supply>) -> [Step] {
        let ordered: [Step]
        switch stain {
        case .blowout, .poop:
            ordered = [rinse, dishSoap, detergent, oxygenSoak, sun, peroxide, washAndCheck]
        case .spitUp:
            ordered = [rinse, dishSoap, detergent, bakingSodaSmell, oxygenSoak, washAndCheck]
        case .breastMilk:
            ordered = [rinse, detergent, dishSoap, oxygenSoak, sun, washAndCheck]
        case .formula:
            ordered = [rinse, dishSoap, detergent, oxygenSoak, vinegarSmell, washAndCheck]
        }
        return ordered.filter { step in
            guard let supply = step.supply else { return true }
            return supplies.contains(supply)
        }
    }

    /// What the parent is missing that would have helped, so the empty-handed
    /// case says something useful instead of nothing.
    static func missing(for stain: Stain, owning supplies: Set<Supply>) -> [Supply] {
        let all: [Step]
        switch stain {
        case .blowout, .poop: all = [dishSoap, detergent, oxygenSoak, peroxide]
        case .spitUp: all = [dishSoap, detergent, bakingSodaSmell, oxygenSoak]
        case .breastMilk: all = [detergent, dishSoap, oxygenSoak]
        case .formula: all = [dishSoap, detergent, oxygenSoak, vinegarSmell]
        }
        return all.compactMap(\.supply).filter { !supplies.contains($0) }
    }

    // MARK: - What is at home

    private static let storageKey = "stainSupplies"

    static func storedSupplies() -> Set<Supply> {
        guard let raw = AppGroup.defaults.stringArray(forKey: storageKey) else { return [] }
        return Set(raw.compactMap(Supply.init(rawValue:)))
    }

    static func store(_ supplies: Set<Supply>) {
        AppGroup.defaults.set(supplies.map(\.rawValue).sorted(), forKey: storageKey)
    }

    static var hasChosenSupplies: Bool {
        AppGroup.defaults.object(forKey: storageKey) != nil
    }
}
