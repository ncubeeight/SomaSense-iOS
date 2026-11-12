import Foundation
import Testing
@testable import SomaSense

/// Painting areas on the body, as ported from the prototype.
@MainActor
struct PaintTests {
    /// A loop around the navel, in figure units, drawn from the front.
    static func paintBelly(_ paint: BodyPaint) {
        paint.begin(yaw: 0, r: BodyPaint.brush)
        for (x, y) in [(-12.0, 175.0), (12, 175), (12, 195), (-12, 195), (-12, 178)] { paint.strokeTo(sx: x, sy: y) }
    }

    @Test func aStrokeBecomesAnAreaOnTheSkinItCovers() throws {
        let mesh = try #require(BodyMesh.loadBundled())
        let paint = BodyPaint(mesh: mesh)
        Self.paintBelly(paint)
        let live = try #require(paint.live)
        #expect(live.touches.count > 10)
        #expect(!live.tris.isEmpty)

        let pt = try #require(paint.end(keep: true))
        #expect(!paint.isPainting && paint.live == nil)
        let path = try #require(pt.path)
        #expect(path.count == live.touches.count)
        #expect(pt.label.hasPrefix("Area: "))
        #expect(pt.label.contains("abdomen") || pt.label.contains("navel"))
        #expect(pt.area == "torso")
        #expect(pt.r == BodyPaint.brush && pt.yaw == 0)

        // The area colors only skin facing the front, and none of the back.
        let decals = paint.decals(for: [pt])
        let d = try #require(decals.first)
        #expect(d.tris.count > 30)
        let N = mesh.normals
        for k in stride(from: 0, to: d.tris.count, by: 3) {
            let z = (0..<3).reduce(0.0) { $0 + Double(N[Int(d.tris[k + $1]) * 3 + 2]) }
            #expect(z > -0.5)
        }
        // The mask is filled in the middle of the loop, not just along the stroke.
        let m = d.mask
        let i = Int((0 - m.x0) / m.h), j = Int((185 - m.y0) / m.h)
        #expect(m.bytes[j * m.w + i] > 200)
        // Cached until the shape changes.
        #expect(paint.decals(for: [pt]).first?.key == d.key)
    }

    @Test func aShortHoldIsAPointAndACancelKeepsNothing() throws {
        let mesh = try #require(BodyMesh.loadBundled())
        let paint = BodyPaint(mesh: mesh)
        paint.begin(yaw: 0, r: BodyPaint.brush)
        paint.strokeTo(sx: 0, sy: 185)
        let pt = try #require(paint.end(keep: true))
        #expect(pt.path == nil && !pt.isArea)
        #expect(!pt.label.hasPrefix("Area"))

        Self.paintBelly(paint)
        #expect(paint.end(keep: false) == nil)
        // Off the body, nothing is laid.
        paint.begin(yaw: 0, r: BodyPaint.brush)
        paint.strokeTo(sx: -110, sy: 20)
        #expect(paint.end(keep: true) == nil)
    }

    @Test func helpersMatchThePrototype() {
        let d = BodyPaint.gridDistance(3, 3, [0, 0, 0, 0, 1, 0, 0, 0, 0])
        #expect(d[4] == 0 && d[1] == 1 && abs(d[0] - 2.0.squareRoot()) < 1e-9)
        #expect(BodyPaint.byCount(["a", "b", "b", "c", "a", "b"]) == ["b", "a", "c"])
        #expect(BodyPaint.byCount(["x", "y"]) == ["x", "y"])
        #expect(BodyPaint.pathYaw([PathTouch(p: [0, 0, 0], n: [0, 0, 1])]) == 0)
        #expect(BodyPaint.pathYaw([PathTouch(p: [0, 0, 0], n: [-1, 0, 0])]) == 90)
        #expect(BodyPaint.pathYaw([PathTouch(p: [0, 0, 0], n: [0, 0, -1])]) == 180)
    }
}
