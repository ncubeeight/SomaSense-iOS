import Foundation
import simd

/// The body mesh and its camera, ported from bodyModel() in the prototype.
/// Units match the prototype: the figure is 240 wide and 440 tall, y runs down from the top of the head,
/// x is the person's left, and z faces forward. The camera is orthographic and looks 8° down.
final class BodyMesh {
    static let pitch = 8.0 * .pi / 180
    static let cy = 220.0
    static let cosP = cos(pitch), sinP = sin(pitch)

    /// Positions, three per vertex (x, y, z), in double precision as in the prototype.
    /// They follow the chosen body shape; `base` keeps the default body.
    private(set) var positions: [Double]
    let base: [Double]
    let triangles: [UInt16]
    /// Per-vertex body-part tag and its name.
    let groups: [Int]
    let tags: [String]
    /// Smooth normals (baked for the default body, adjusted for the chosen shape) and ambient occlusion, for drawing.
    private(set) var normals: [Float]
    let baseNormals: [Float]
    let occlusion: [Float]
    /// Goes up each time the shape changes, so drawings know to refresh.
    private(set) var shapeVersion = 0
    private var rawBase: [Double] = []
    private var rawSign = 1.0

    var vertexCount: Int { positions.count / 3 }

    private var proj: [Double] = []
    private var projYaw: Double?

    private struct Raw: Decodable {
        var p: [Double]
        var t: [Int]
        var g: [Int]
        var tags: [String]
        var n: [Double]
        var a: [Double]
    }

    init(data: Data) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        positions = raw.p.map { $0 / 10 }
        base = positions
        triangles = raw.t.map { UInt16($0) }
        groups = raw.g
        tags = raw.tags
        normals = raw.n.map { Float($0 / 100) }
        baseNormals = normals
        occlusion = raw.a.map { Float($0 / 100) }
    }

    static func loadBundled() -> BodyMesh? {
        guard let url = Bundle.main.url(forResource: "body-mesh", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? BodyMesh(data: data)
    }

    // MARK: Body shape

    /// Moves every vertex from the default body by the weighted MakeHuman offsets, as setOffsets() does.
    func apply(_ shape: BodyShape, offsets: ShapeOffsets) {
        let list: [([Int], Double)] = [
            (offsets.f, Double(max(0, -shape.g)) / 100), (offsets.m, Double(max(0, shape.g)) / 100),
            // MakeHuman's heaviest setting is still moderate, so the end of the Build slider goes somewhat past it.
            (offsets.s, Double(max(0, -shape.b)) / 100), (offsets.h, Double(max(0, shape.b)) / 100 * 1.5)
        ]
        var next = base
        for (d, w) in list where w != 0 && d.count == next.count {
            for i in 0..<next.count { next[i] += Double(d[i]) / 10 * w }
        }
        positions = next
        projYaw = nil
        morphNormals()
        shapeVersion += 1
    }

    /// Area-weighted vertex normals of a set of positions.
    private func rawNormals(_ P: [Double]) -> [Double] {
        var n = [Double](repeating: 0, count: P.count)
        var i = 0
        while i < triangles.count {
            let a = Int(triangles[i]) * 3, b = Int(triangles[i + 1]) * 3, c = Int(triangles[i + 2]) * 3
            let ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2]
            let vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2]
            let x = uy * vz - uz * vy, y = uz * vx - ux * vz, z = ux * vy - uy * vx
            for q in [a, b, c] { n[q] += x; n[q + 1] += y; n[q + 2] += z }
            i += 3
        }
        i = 0
        while i < n.count {
            var l = (n[i] * n[i] + n[i + 1] * n[i + 1] + n[i + 2] * n[i + 2]).squareRoot()
            if l == 0 { l = 1 }
            n[i] /= l; n[i + 1] /= l; n[i + 2] /= l
            i += 3
        }
        return n
    }

    /// Keeps the baked smoothing: only the change in surface direction since the default body is added.
    private func morphNormals() {
        if rawBase.isEmpty {
            rawBase = rawNormals(base)
            var dot = 0.0
            for i in 0..<rawBase.count { dot += rawBase[i] * Double(baseNormals[i]) }
            rawSign = dot < 0 ? -1 : 1
        }
        let raw = rawNormals(positions)
        var out = [Float](repeating: 0, count: raw.count)
        var i = 0
        while i < raw.count {
            let x = Double(baseNormals[i]) + rawSign * (raw[i] - rawBase[i])
            let y = Double(baseNormals[i + 1]) + rawSign * (raw[i + 1] - rawBase[i + 1])
            let z = Double(baseNormals[i + 2]) + rawSign * (raw[i + 2] - rawBase[i + 2])
            var l = (x * x + y * y + z * z).squareRoot()
            if l == 0 { l = 1 }
            out[i] = Float(x / l); out[i + 1] = Float(y / l); out[i + 2] = Float(z / l)
            i += 3
        }
        normals = out
    }

    /// The index (times three) of the vertex nearest a point, among the given positions.
    private func nearest(_ p: [Double], in P: [Double]) -> Int {
        var best = Double.infinity, at = 0, i = 0
        while i < P.count {
            let dx = P[i] - p[0], dy = P[i + 1] - p[1], dz = P[i + 2] - p[2]
            let d = dx * dx + dy * dy + dz * dz
            if d < best { best = d; at = i }
            i += 3
        }
        return at
    }

    /// The index (times three) of the vertex nearest a point on the body as shaped, or on the default body.
    func nearestVertex(_ p: [Double], onBase: Bool = false) -> Int { nearest(p, in: onBase ? base : positions) }

    /// Points are stored on the default body. These move a point between it and the chosen shape,
    /// carried along with its nearest vertex, as the prototype does.
    /// Returns the point on the default body and the vertex it moves with.
    func toBase(_ p: [Double]) -> (p: [Double], v: Int) {
        let v = nearest(p, in: positions)
        if positions == base { return (p, v) }
        return ((0..<3).map { base[v + $0] + p[$0] - positions[v + $0] }, v)
    }

    func fromBase(_ p: [Double], v: Int? = nil) -> [Double] {
        if positions == base { return p }
        let v = v ?? nearest(p, in: base)
        return (0..<3).map { positions[v + $0] + p[$0] - base[v + $0] }
    }

    struct Screen { var sx: Double; var sy: Double; var depth: Double }

    static func toScreen(_ p: [Double], yaw: Double) -> Screen {
        let t = yaw * .pi / 180, c = cos(t), s = sin(t)
        let cx = p[0] * c + p[2] * s, cz = -p[0] * s + p[2] * c, v = p[1] - cy
        return Screen(sx: cx, sy: v * cosP + cz * sinP + cy, depth: cz * cosP - v * sinP)
    }

    /// The direction from the body toward the camera.
    static func viewDir(_ yaw: Double) -> [Double] {
        let t = yaw * .pi / 180
        return [-sin(t) * cosP, -sinP, cos(t) * cosP]
    }

    private func project(_ yaw: Double) {
        if projYaw == yaw { return }
        let t = yaw * .pi / 180, c = cos(t), s = sin(t)
        if proj.count != positions.count { proj = Array(repeating: 0, count: positions.count) }
        var i = 0
        while i < positions.count {
            let x = positions[i], y = positions[i + 1], z = positions[i + 2]
            let cx = x * c + z * s, cz = -x * s + z * c, v = y - BodyMesh.cy
            // Rounded through Float as the prototype's Float32Array does, so taps on a dividing line land the same way.
            proj[i] = Double(Float(cx))
            proj[i + 1] = Double(Float(v * BodyMesh.cosP + cz * BodyMesh.sinP + BodyMesh.cy))
            proj[i + 2] = Double(Float(cz * BodyMesh.cosP - v * BodyMesh.sinP))
            i += 3
        }
        projYaw = yaw
    }

    struct Hit {
        var p: [Double]
        var n: [Double]
        var depth: Double
        var tag: String
    }

    /// The surface nearest the viewer under a screen point, in figure units.
    func cast(sx: Double, sy: Double, yaw: Double) -> Hit? {
        project(yaw)
        var best = -Double.infinity, bt = -1, bu = 0.0, bv = 0.0
        var i = 0
        while i < triangles.count {
            let a = Int(triangles[i]) * 3, b = Int(triangles[i + 1]) * 3, c = Int(triangles[i + 2]) * 3
            let ax = proj[a], ay = proj[a + 1], bx = proj[b], by = proj[b + 1], cx = proj[c], cy = proj[c + 1]
            defer { i += 3 }
            if (sx < ax && sx < bx && sx < cx) || (sx > ax && sx > bx && sx > cx) || (sy < ay && sy < by && sy < cy) || (sy > ay && sy > by && sy > cy) { continue }
            let den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9 { continue }
            let u = ((by - cy) * (sx - cx) + (cx - bx) * (sy - cy)) / den
            let v = ((cy - ay) * (sx - cx) + (ax - cx) * (sy - cy)) / den
            if u < 0 || v < 0 || u + v > 1 { continue }
            let w = 1 - u - v
            let depth = u * proj[a + 2] + v * proj[b + 2] + w * proj[c + 2]
            if depth > best { best = depth; bt = i; bu = u; bv = v }
        }
        if bt < 0 { return nil }
        let ia = Int(triangles[bt]), ib = Int(triangles[bt + 1]), ic = Int(triangles[bt + 2]), bw = 1 - bu - bv
        func at(_ i: Int, _ k: Int) -> Double { positions[i * 3 + k] }
        let p = (0..<3).map { k in bu * at(ia, k) + bv * at(ib, k) + bw * at(ic, k) }
        let e1 = (0..<3).map { at(ib, $0) - at(ia, $0) }, e2 = (0..<3).map { at(ic, $0) - at(ia, $0) }
        var n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
        let l = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).squareRoot()
        n = n.map { $0 / (l == 0 ? 1 : l) }
        let d = BodyMesh.viewDir(yaw)
        if n[0] * d[0] + n[1] * d[1] + n[2] * d[2] < 0 { n = n.map { -$0 } }
        let vertex = bu >= bv && bu >= bw ? ia : bv >= bw ? ib : ic
        return Hit(p: p, n: n, depth: best, tag: tags[groups[vertex]])
    }

    /// Whether a marked point can be seen from this side, or is turned away or hidden behind another part.
    func isVisible(_ pt: BodyPoint, yaw: Double) -> Bool {
        let d = BodyMesh.viewDir(yaw)
        if pt.n[0] * d[0] + pt.n[1] * d[1] + pt.n[2] * d[2] < 0.02 { return false }
        let q = BodyMesh.toScreen(pt.p, yaw: yaw)
        guard let r = cast(sx: q.sx, sy: q.sy, yaw: yaw) else { return true }
        return r.depth <= q.depth + 2
    }
}
