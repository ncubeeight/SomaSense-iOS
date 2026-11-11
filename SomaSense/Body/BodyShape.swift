import Foundation

/// The chosen body shape: Gender from feminine (-100) to masculine (100), and Build from slimmer (-100) to fuller (100).
struct BodyShape: Codable, Equatable {
    var g = 0
    var b = 0
    var isDefault: Bool { g == 0 && b == 0 }
}

/// MakeHuman's shape offsets for the bundled mesh: feminine, masculine, slimmer and heavier, in tenths of a unit per coordinate.
struct ShapeOffsets: Decodable {
    var f: [Int]
    var m: [Int]
    var s: [Int]
    var h: [Int]

    static func loadBundled() -> ShapeOffsets? {
        guard let url = Bundle.main.url(forResource: "body-shapes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ShapeOffsets.self, from: data)
    }
}
