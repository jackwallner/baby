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
            case .dishSoap: "Dish soap"
            case .detergent: "Laundry detergent"
            case .oxygenBleach: "Oxygen bleach (OxiClean)"
            case .hydrogenPeroxide: "Hydrogen peroxide 3%"
            case .whiteVinegar: "White vinegar"
            case .bakingSoda: "Baking soda"
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
            case .dishSoap: "The blue kind by the sink."
            case .detergent: "Most have enzymes, which is what breaks milk and poop down."
            case .oxygenBleach: "Colour-safe powder. Not chlorine bleach."
            case .hydrogenPeroxide: "The brown bottle from the medicine cabinet."
            case .whiteVinegar: "For the sour-milk smell."
            case .bakingSoda: "For smell, not for the stain."
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
            case .blowout: "Blowout"
            case .poop: "Poop"
            case .spitUp: "Spit-up"
            case .breastMilk: "Breast milk"
            case .formula: "Formula"
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
            case .blowout: "Get it off the skin first, then peel the clothes downward if you can, not over the head."
            case .poop: "Lift the solids off with the edge of a wipe. Don't rub."
            case .spitUp: "Blot, don't rub. Rubbing pushes it into the weave."
            case .breastMilk: "Rinse it now if you can. Dried milk is a different job."
            case .formula: "Rinse it now if you can. Dried formula is a different job."
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
    static let careLabelRule = "Check the care label first, and never put two products on the fabric in the same step. Rinse in between."

    static let neverRule = "No chlorine bleach on baby clothes here, and never mix hydrogen peroxide or vinegar with anything else."

    // MARK: - Steps

    private static let rinse = Step(
        supply: nil,
        title: "Cold water, from the back",
        detail: "Hold the fabric wrong side up and run cold water through the back of the stain so it goes out the way it came in. Never hot: heat cooks milk and poop into the fibres.",
        caution: nil
    )

    private static let dishSoap = Step(
        supply: .dishSoap,
        title: "A drop of dish soap",
        detail: "Work one drop in with a fingertip, wait five minutes, rinse cold. It is built to lift the fat in milk, which is half of what a baby stain is.",
        caution: nil
    )

    private static let detergent = Step(
        supply: .detergent,
        title: "Rub in a little detergent",
        detail: "Enzymes in ordinary laundry detergent break down protein. Rub a little straight into the damp stain and leave it fifteen minutes before washing.",
        caution: nil
    )

    private static let oxygenSoak = Step(
        supply: .oxygenBleach,
        title: "Soak in oxygen bleach",
        detail: "Dissolve the powder in warm water to the dose on the tub, submerge the garment, and leave it one to eight hours. This is the one that gets old stains out.",
        caution: "Colour-safe, but check the label for wool and silk."
    )

    private static let sun = Step(
        supply: nil,
        title: "Lay it in the sun, still damp",
        detail: "Sunlight fades the yellow of breastfed poop and milk better than anything in the cupboard, and it is free. A few hours, damp, stain side up.",
        caution: nil
    )

    private static let peroxide = Step(
        supply: .hydrogenPeroxide,
        title: "Dab hydrogen peroxide",
        detail: "Dab it on, wait ten minutes, rinse cold. Rinse off any earlier product before this one.",
        caution: "Whites and colourfast fabrics only. Test a hidden seam first."
    )

    private static let vinegarSmell = Step(
        supply: .whiteVinegar,
        title: "Soak for the sour smell",
        detail: "One part white vinegar to four parts cool water, thirty minutes, then rinse. This is for the smell that survives the wash, not for the mark.",
        caution: "On its own, in clean water. Never alongside peroxide or bleach."
    )

    private static let bakingSodaSmell = Step(
        supply: .bakingSoda,
        title: "Baking soda paste for the smell",
        detail: "A spoon of baking soda with a little water, spread on, thirty minutes, brush off. Again: smell, not stain.",
        caution: nil
    )

    private static let washAndCheck = Step(
        supply: nil,
        title: "Wash, then look before it dries",
        detail: "Wash as warm as the care label allows, then check the garment while it is still wet. A dryer sets whatever is left, and after that it is permanent.",
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
