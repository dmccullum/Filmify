import GranularCore

/// A printed canister a saved recipe can be packaged in. Built-in recipes keep
/// their own tins; these are for recipes people make themselves.
struct CanisterDesign: Identifiable, Hashable {
    enum Layout: Hashable {
        /// A narrow coloured panel beside a wider face, like the built-in tins.
        case split(panel: UInt32, panelText: UInt32, face: UInt32, name: UInt32, detail: UInt32)
        /// A plain face between a heavy top band and a lighter bottom band.
        case bands(face: UInt32, band: UInt32, accent: UInt32, name: UInt32, detail: UInt32)
        /// A diagonal sash across the shoulder of the tin.
        case sash(face: UInt32, stripe: UInt32, edge: UInt32, name: UInt32, detail: UInt32)
        /// A stack of thin horizontal stripes across the shoulder, 1970s style.
        case stripes(face: UInt32, stripes: [UInt32], name: UInt32, detail: UInt32)
        /// A ruled paper label glued onto a bare tin, typed rather than printed.
        case paper(tin: UInt32, paper: UInt32, ink: UInt32, rule: UInt32)
        /// Bulk-loaded film with the name written on a strip of tape.
        case tape
    }

    let id: String
    let name: String
    let layout: Layout
    let steelCaps: Bool

    static let tape = CanisterDesign(id: "tape", name: "Bulk Load", layout: .tape, steelCaps: true)

    static let library: [CanisterDesign] = [
        CanisterDesign(
            id: "ember", name: "Ember",
            layout: .split(panel: 0xB3261E, panelText: 0xF2EDE4, face: 0xEEE8DA, name: 0xB3261E, detail: 0x141414),
            steelCaps: false
        ),
        CanisterDesign(
            id: "lagoon", name: "Lagoon",
            layout: .split(panel: 0x0E7C86, panelText: 0x141414, face: 0x141414, name: 0x6FD3CC, detail: 0xF2EDE4),
            steelCaps: false
        ),
        CanisterDesign(
            id: "plum", name: "Plum",
            layout: .split(panel: 0x5B2A6E, panelText: 0xF1E4EF, face: 0xF1E4EF, name: 0x5B2A6E, detail: 0x3A2A40),
            steelCaps: true
        ),
        CanisterDesign(
            id: "olive", name: "Olive",
            layout: .split(panel: 0x6B7A2A, panelText: 0xEFE9D2, face: 0xEFE9D2, name: 0x4F5A1E, detail: 0x2E3412),
            steelCaps: true
        ),
        CanisterDesign(
            id: "sunset", name: "Sunset",
            layout: .bands(face: 0xF4E9D8, band: 0xE8732C, accent: 0xC0392B, name: 0x141414, detail: 0x7A3A1E),
            steelCaps: false
        ),
        CanisterDesign(
            id: "nightshift", name: "Night Shift",
            layout: .bands(face: 0x16213E, band: 0xE94F37, accent: 0xF2C14E, name: 0xF4F1EA, detail: 0xF2C14E),
            steelCaps: false
        ),
        CanisterDesign(
            id: "mint", name: "Mint",
            layout: .bands(face: 0xDDEFE3, band: 0x2E8B6E, accent: 0x141414, name: 0x1E5C49, detail: 0x2E8B6E),
            steelCaps: true
        ),
        CanisterDesign(
            id: "chroma", name: "Chroma",
            layout: .sash(face: 0xF5F4F0, stripe: 0xD6246E, edge: 0x141414, name: 0x141414, detail: 0xD6246E),
            steelCaps: false
        ),
        CanisterDesign(
            id: "citrus", name: "Citrus",
            layout: .sash(face: 0x1C1C1C, stripe: 0xF4C20D, edge: 0xF5F4F0, name: 0xF5F4F0, detail: 0xF4C20D),
            steelCaps: false
        ),
        CanisterDesign(
            id: "glacier", name: "Glacier",
            layout: .sash(face: 0xE9F1F7, stripe: 0x3B82C4, edge: 0x1B3F66, name: 0x1B3F66, detail: 0x3B82C4),
            steelCaps: true
        ),
        CanisterDesign(
            id: "kraft", name: "Kraft",
            layout: .paper(tin: 0xB9BEC2, paper: 0xC8A36A, ink: 0x3B2A17, rule: 0x8A6A3E),
            steelCaps: true
        ),
        CanisterDesign(
            id: "ledger", name: "Ledger",
            layout: .paper(tin: 0x111113, paper: 0xF3EEE1, ink: 0x1D2A4A, rule: 0xC0392B),
            steelCaps: false
        ),
        // Nods to the classics, without anyone's trade dress.
        CanisterDesign(
            id: "seventies", name: "Seventies",
            layout: .stripes(face: 0xF3E3C3, stripes: [0xE8A33D, 0xD9642B, 0xA83C24, 0x5B3A29], name: 0x5B3A29, detail: 0xA83C24),
            steelCaps: false
        ),
        CanisterDesign(
            id: "spectrum", name: "Spectrum",
            layout: .stripes(face: 0xF4F2EC, stripes: [0x3E8EDE, 0x5BB65A, 0xF2C230, 0xEE7D2C, 0xE0453A], name: 0x141414, detail: 0x6B6B6B),
            steelCaps: true
        ),
        CanisterDesign(
            id: "chrome", name: "Chrome",
            layout: .stripes(face: 0x0F2A5C, stripes: [0x5AB0E8, 0xF4F4F0, 0xE94F37], name: 0xF4F4F0, detail: 0x5AB0E8),
            steelCaps: false
        ),
        CanisterDesign(
            id: "sunbleached", name: "Sun-Bleached",
            layout: .split(panel: 0xE3CD84, panelText: 0x3A3631, face: 0x3A3631, name: 0xE3CD84, detail: 0xCFC6B4),
            steelCaps: false
        ),
        CanisterDesign(
            id: "prolab", name: "Pro Lab",
            layout: .bands(face: 0xF7F6F2, band: 0x2A2A2A, accent: 0xC8102E, name: 0x141414, detail: 0xC8102E),
            steelCaps: true
        ),
        CanisterDesign(
            id: "monochrome", name: "Monochrome",
            layout: .split(panel: 0xF4F4F0, panelText: 0x141414, face: 0x141414, name: 0xF4F4F0, detail: 0x9A9A9A),
            steelCaps: true
        ),
        CanisterDesign(
            id: "cinemacan", name: "Cinema Can",
            layout: .sash(face: 0x3A3D40, stripe: 0xC8102E, edge: 0xE8E8E8, name: 0xF4F4F0, detail: 0xE8E8E8),
            steelCaps: true
        ),
        tape
    ]

    /// The designs a recipe can be given without asking: everything but tape.
    static let automatic = library.filter { $0.layout != .tape }

    static func named(_ id: String) -> CanisterDesign? {
        library.first { $0.id == id }
    }

    /// The recipe's chosen canister, or one picked for it from its identifier so
    /// it comes out of the same tin on every launch.
    static func resolved(for recipe: FilmRecipe) -> CanisterDesign {
        if let id = recipe.canister, let design = named(id) {
            return design
        }
        // FNV-1a: Swift's own hashing is reseeded every launch.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in recipe.id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return automatic[Int(hash % UInt64(automatic.count))]
    }
}
