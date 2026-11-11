import Foundation
import Testing
@testable import SomaSense

/// Checks the Swift port against fixtures made by running the prototype's own JavaScript
/// (ios/tools/make_fixtures.js). Regenerate them whenever Main.dc.html's body model changes.
struct ParityTests {
    struct Tap: Decodable {
        var yaw: Double
        var sx: Double
        var sy: Double
        var p: [Double]
        var label: String
        var area: String
    }

    static func taps() throws -> [Tap] {
        let bundle = Bundle(for: BundleMarker.self)
        let url = try #require(bundle.url(forResource: "taps", withExtension: "json"))
        return try JSONDecoder().decode([Tap].self, from: Data(contentsOf: url))
    }

    @Test func tapsLandAndAreNamedAsInTheAndroidApp() throws {
        let mesh = try #require(BodyMesh.loadBundled())
        let taps = try Self.taps()
        #expect(taps.count > 5000)
        var mismatches: [String] = []
        for t in taps {
            guard let hit = mesh.cast(sx: t.sx, sy: t.sy, yaw: t.yaw) else {
                mismatches.append("no hit at \(t.sx),\(t.sy) yaw \(t.yaw)")
                continue
            }
            let place = BodyClassifier.classify(p: hit.p, n: hit.n, tag: hit.tag)
            let far = zip(hit.p, t.p).contains { abs($0 - $1) > 1e-3 }
            if place.label != t.label || place.area != t.area || far {
                mismatches.append("\(t.sx),\(t.sy) yaw \(t.yaw): \(place.label) vs \(t.label)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) taps differ, first: \(mismatches.prefix(5))")
    }

    struct ShapedTap: Decodable {
        var g: Int
        var b: Int
        var yaw: Double
        var sx: Double
        var sy: Double
        var p: [Double]
        var label: String
        var area: String
    }

    @Test func reshapedBodiesMatchTheAndroidApp() throws {
        let mesh = try #require(BodyMesh.loadBundled())
        let offsets = try #require(ShapeOffsets.loadBundled())
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "taps-shaped", withExtension: "json"))
        let taps = try JSONDecoder().decode([ShapedTap].self, from: Data(contentsOf: url))
        #expect(taps.count > 1000)
        var mismatches: [String] = []
        var current: BodyShape?
        for t in taps {
            let shape = BodyShape(g: t.g, b: t.b)
            if shape != current { mesh.apply(shape, offsets: offsets); current = shape }
            guard let hit = mesh.cast(sx: t.sx, sy: t.sy, yaw: t.yaw) else {
                mismatches.append("no hit at \(t.sx),\(t.sy) yaw \(t.yaw) shape \(t.g),\(t.b)")
                continue
            }
            let place = BodyClassifier.classify(p: hit.p, n: hit.n, tag: hit.tag)
            let far = zip(hit.p, t.p).contains { abs($0 - $1) > 1e-3 }
            if place.label != t.label || place.area != t.area || far {
                mismatches.append("\(t.sx),\(t.sy) yaw \(t.yaw) shape \(t.g),\(t.b): \(place.label) vs \(t.label)\(far ? " (moved)" : "")")
            }
            // A point stored on the default body comes back to the same place on this shape.
            let stored = mesh.toBase(hit.p)
            let back = mesh.fromBase(stored.p, v: stored.v)
            if zip(back, hit.p).contains(where: { abs($0 - $1) > 1e-6 }) { mismatches.append("round trip moved \(t.sx),\(t.sy)") }
        }
        mesh.apply(BodyShape(), offsets: offsets)
        #expect(mesh.positions == mesh.base)
        #expect(mismatches.isEmpty, "\(mismatches.count) taps differ, first: \(mismatches.prefix(5))")
    }

    @Test func reportFiguresMatchThePrototypesRules() {
        func report(_ date: String, _ time: String, _ cats: [String], _ sev: Int, meds: [String] = []) -> Report {
            Report(id: date + time, date: date, time: time, cats: cats, severity: sev, points: [], desc: "", sevNote: "", meds: meds, acts: [], senses: [], concern: "")
        }
        let reports = [
            report("2026-10-27", "07:40", ["Tingling"], 5),
            report("2026-10-27", "12:15", ["Pain", "Stiffness"], 4, meds: ["Ibuprofen"]),
            report("2026-10-26", "18:30", ["Pain"], 7, meds: ["Ibuprofen"]),
            report("2026-09-01", "09:00", ["Pain"], 2)
        ]
        let s = ReportSummary(reports: reports, symptomFree: ["2026-10-20", "2026-10-27"], range: 30, today: "2026-10-27")
        #expect(s.from == "2026-09-28")
        #expect(s.inRange.count == 3)
        #expect(s.days == 2)
        #expect(s.freeDays == 1)
        #expect(s.groups.map(\.cat) == ["Pain", "Tingling", "Stiffness"])
        #expect(ReportSummary.mean(s.inRange) == "5.3")
        let d = TypeDetail(list: s.groups[0].list, range: 30, from: s.from, today: "2026-10-27")
        #expect(d.buckets.count == 5)
        #expect(d.buckets.last?.n == 2)
        #expect(d.buckets.first?.start == "2026-09-28")
        #expect(d.parts.map(\.count) == [0, 1, 1, 0])
        #expect(d.context.first?.label == "Ibuprofen")
    }

    @Test func wordingMatches() {
        #expect(Day.long("2026-10-27") == "Tue, Oct 27")
        #expect(Day.monthTitle("2026-10") == "October 2026")
        #expect(Words.time("07:40") == "7:40 AM")
        #expect(Words.time("00:05") == "12:05 AM")
        #expect(Words.partOfDay("21:00") == "Night")
        #expect(Words.severity(7) == "severe")
        #expect(Day.weekday("2026-11-01") == 0)
    }
}

final class BundleMarker {}
