import Foundation
import simd

/// Painting areas on the body, ported from the prototype's startStroke() through areaTris().
/// Press and hold, then drag: brush touches are laid along the finger's path, the paint spreads only
/// across connected skin that faces the same way, and a finished area is filled in and smoothed
/// on a grid seen from the side it was drawn on, then laid back onto the skin it covers.
@MainActor
final class BodyPaint {
    static let brush = 6.0
    static let maxTouches = 400
    static let maxPaint = 2048
    static let holdSeconds = 0.35
    /// A scribbled area joins gaps up to about two and a half brush widths across, and its edge is rounded over most of a brush.
    static let fillClose = 2.0
    static let fillSmooth = 0.8

    /// One brush touch, in figure units on screen and on the body as drawn.
    struct Sample {
        var sx: Double, sy: Double
        var p: [Double], n: [Double]
        var v: Int
        var label: String, area: String
    }

    /// The stroke being drawn, as brush touches (position and radius) and the triangles they may color.
    struct Live {
        var version: Int
        var touches: [SIMD4<Float>]
        var tris: [UInt16]
    }

    /// A finished area's soft mask, seen from the side it was drawn on: cell (i, j) covers
    /// x0 + i·h and y0 + j·h in figure units. `sat` counts cells over 0.3, summed over the grid.
    struct AreaMask {
        var x0: Double, y0: Double, h: Double
        var w: Int, ht: Int
        var bytes: [UInt8]
        var sat: [Int32]
    }

    /// A finished area ready to draw: its mask and the skin it may color.
    struct Decal {
        var key: String
        var yaw: Double
        var mask: AreaMask
        var tris: [UInt16]
    }

    private struct Stroke {
        var yaw: Double
        var r: Double
        var samples: [Sample] = []
        var mask: [UInt8]
        var at: (sx: Double, sy: Double)?
        var tris: [UInt16] = []
    }

    let mesh: BodyMesh
    private var stroke: Stroke?
    private var strokeVersion = 0
    private var decalCache: [String: Decal] = [:]

    // Which vertices touch which, and which triangles meet at each vertex, built once from the mesh.
    private let vStart: [Int32], vTo: [Int32]
    private let tStart: [Int32], tTo: [Int32]
    private var mark: [Int32], dist: [Double], inQueue: [Int32], queue: [Int32]
    private var stamp: Int32 = 0

    init(mesh: BodyMesh) {
        self.mesh = mesh
        let T = mesh.triangles, n = mesh.vertexCount
        var deg = [Int32](repeating: 0, count: n + 1)
        var i = 0
        while i < T.count {
            deg[Int(T[i])] += 2; deg[Int(T[i + 1])] += 2; deg[Int(T[i + 2])] += 2
            i += 3
        }
        var start = [Int32](repeating: 0, count: n + 1)
        for v in 0..<n { start[v + 1] = start[v] + deg[v] }
        var fill = Array(start[0..<n])
        var to = [Int32](repeating: 0, count: Int(start[n]))
        func link(_ a: Int, _ b: Int) { to[Int(fill[a])] = Int32(b); fill[a] += 1 }
        i = 0
        while i < T.count {
            let a = Int(T[i]), b = Int(T[i + 1]), c = Int(T[i + 2])
            link(a, b); link(a, c); link(b, a); link(b, c); link(c, a); link(c, b)
            i += 3
        }
        vStart = start
        vTo = to

        var ts = [Int32](repeating: 0, count: n + 1)
        for v in T { ts[Int(v) + 1] += 1 }
        for v in 0..<n { ts[v + 1] += ts[v] }
        var tf = Array(ts[0..<n])
        var tt = [Int32](repeating: 0, count: T.count)
        for (k, v) in T.enumerated() { tt[Int(tf[Int(v)])] = Int32(k / 3); tf[Int(v)] += 1 }
        tStart = ts
        tTo = tt

        mark = [Int32](repeating: 0, count: n)
        dist = [Double](repeating: 0, count: n)
        inQueue = [Int32](repeating: 0, count: n)
        queue = [Int32](repeating: 0, count: n)
    }

    // MARK: The stroke being drawn

    var isPainting: Bool { stroke != nil }

    func begin(yaw: Double, r: Double) {
        stroke = Stroke(yaw: yaw, r: r, mask: [UInt8](repeating: 0, count: mesh.vertexCount))
    }

    /// Brush touches are laid every half brush along the finger's path, so a quick swipe leaves no gaps.
    /// Where the path leaves the body, nothing is laid. Returns whether anything was added.
    @discardableResult
    func strokeTo(sx: Double, sy: Double) -> Bool {
        guard var st = stroke else { return false }
        let gap = st.r * 0.5
        let from = st.at ?? (sx, sy)
        let d = hypot(sx - from.sx, sy - from.sy)
        if st.at != nil && d < gap { return false }
        let steps = st.at != nil ? min(60, Int(floor(d / gap))) : 0
        var added = false
        for k in (steps > 0 ? 1 : 0)...steps {
            if st.samples.count >= BodyPaint.maxTouches { break }
            let f = steps > 0 ? Double(k) / Double(steps) : 1
            let x = from.sx + (sx - from.sx) * f, y = from.sy + (sy - from.sy) * f
            guard let hit = mesh.cast(sx: x, sy: y, yaw: st.yaw) else { continue }
            let c = BodyClassifier.classify(p: hit.p, n: hit.n, tag: hit.tag)
            let q = Sample(sx: x, sy: y, p: hit.p, n: hit.n, v: mesh.nearestVertex(hit.p), label: c.label, area: c.area)
            reach(&st.mask, q, st.r)
            st.samples.append(q)
            added = true
        }
        st.at = (sx, sy)
        if added {
            let T = mesh.triangles, mask = st.mask
            var tris: [UInt16] = []
            var i = 0
            while i < T.count {
                if mask[Int(T[i])] != 0 || mask[Int(T[i + 1])] != 0 || mask[Int(T[i + 2])] != 0 { tris.append(contentsOf: [T[i], T[i + 1], T[i + 2]]) }
                i += 3
            }
            st.tris = tris
            strokeVersion += 1
        }
        stroke = st
        return added
    }

    var live: Live? {
        guard let st = stroke, !st.samples.isEmpty else { return nil }
        let touches = st.samples.prefix(BodyPaint.maxPaint).map { SIMD4(Float($0.p[0]), Float($0.p[1]), Float($0.p[2]), Float(st.r)) }
        return Live(version: strokeVersion, touches: touches, tris: st.tris)
    }

    /// A short stroke is just a point; a longer one becomes an area anchored at its middle.
    /// The result is stored on the default body, as every marked point is.
    func end(keep: Bool) -> BodyPoint? {
        guard let st = stroke else { return nil }
        stroke = nil
        strokeVersion += 1
        guard keep, !st.samples.isEmpty else { return nil }
        let xs = st.samples.map(\.sx), ys = st.samples.map(\.sy)
        let span = hypot(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        let mid = st.samples[st.samples.count / 2]
        let id = "p" + String(UUID().uuidString.prefix(7)).lowercased()
        var pt = BodyPoint(id: id, p: toBase(mid.p, v: mid.v), n: mid.n, label: mid.label, area: mid.area, v: mid.v)
        if st.samples.count >= 3 && span >= st.r * 2 {
            let labels = BodyPaint.byCount(st.samples.map(\.label))
            pt.label = "Area: " + labels.prefix(3).joined(separator: ", ") + (labels.count > 3 ? " and nearby" : "")
            pt.area = BodyPaint.byCount(st.samples.map(\.area))[0]
            pt.r = st.r
            pt.yaw = st.yaw
            pt.path = st.samples.map { PathTouch(p: toBase($0.p, v: $0.v), n: $0.n) }
        }
        return pt
    }

    /// Distinct values, most frequent first; ties keep the order they first appeared in.
    static func byCount(_ list: [String]) -> [String] {
        var order: [String] = [], count: [String: Int] = [:]
        for s in list {
            if count[s] == nil { order.append(s) }
            count[s, default: 0] += 1
        }
        return order.enumerated().sorted { a, b in
            let x = count[a.element]!, y = count[b.element]!
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    }

    private func toBase(_ p: [Double], v: Int) -> [Double] {
        let P = mesh.positions, B = mesh.base
        return (0..<3).map { B[v + $0] + p[$0] - P[v + $0] }
    }

    /// Marks the skin one brush touch may color, measured along the skin. It spreads only across connected
    /// skin that faces the same way, so it never jumps a gap between fingers or wraps onto the far side.
    private func reach(_ mask: inout [UInt8], _ q: Sample, _ r: Double) {
        let P = mesh.positions, N = mesh.normals, size = mesh.vertexCount
        let limit = r * 1.25
        stamp += 1
        let s = stamp, first = q.v / 3
        mark[first] = s
        dist[first] = hypot3(P[q.v] - q.p[0], P[q.v + 1] - q.p[1], P[q.v + 2] - q.p[2])
        var head = 0, tail = 0
        queue[tail % size] = Int32(first); tail += 1
        inQueue[first] = s
        while head < tail {
            let v = Int(queue[head % size]); head += 1
            let i = v * 3, g = dist[v]
            inQueue[v] = 0
            mask[v] = 1
            for j in Int(vStart[v])..<Int(vStart[v + 1]) {
                let u = Int(vTo[j]), o = u * 3
                let along = g + hypot3(P[o] - P[i], P[o + 1] - P[i + 1], P[o + 2] - P[i + 2])
                if along > limit || (mark[u] == s && along >= dist[u]) { continue }
                if Double(N[o]) * q.n[0] + Double(N[o + 1]) * q.n[1] + Double(N[o + 2]) * q.n[2] < 0.15 { continue }
                mark[u] = s
                dist[u] = along
                if inQueue[u] != s && tail - head < size { inQueue[u] = s; queue[tail % size] = Int32(u); tail += 1 }
            }
        }
    }

    // MARK: Finished areas

    /// The side an older area was drawn from, judged by which way its skin faces.
    static func pathYaw(_ path: [PathTouch]) -> Double {
        var x = 0.0, z = 0.0
        for q in path { x += q.n[0]; z += q.n[2] }
        return BodyCamera.normYaw((atan2(-x, z) * 180 / .pi / 5).rounded() * 5)
    }

    /// Masks for the areas among these points, rebuilt when the body shape changes.
    func decals(for points: [BodyPoint]) -> [Decal] {
        var out: [Decal] = [], keep: Set<String> = []
        for pt in points {
            guard let path = pt.path, !path.isEmpty else { continue }
            let r = pt.r ?? BodyPaint.brush
            let key = "\(pt.id)|\(path.count)|\(r)|\(mesh.shapeVersion)"
            keep.insert(key)
            if let d = decalCache[key] { out.append(d); continue }
            // Each touch is carried along with its nearest vertex onto the body as currently shaped.
            let P = mesh.positions, B = mesh.base
            var shown: [[Double]] = [], starts: [Int] = []
            for q in path {
                let v = mesh.nearestVertex(q.p, onBase: true)
                shown.append((0..<3).map { P[v + $0] + q.p[$0] - B[v + $0] })
                starts.append(v)
            }
            let yaw = pt.yaw ?? BodyPaint.pathYaw(path)
            guard let mask = areaMask(shown, r: r, yaw: yaw) else { continue }
            let d = Decal(key: key, yaw: yaw, mask: mask, tris: areaTris(starts, mask: mask, yaw: yaw))
            decalCache[key] = d
            out.append(d)
        }
        decalCache = decalCache.filter { keep.contains($0.key) }
        return out.filter { !$0.tris.isEmpty }
    }

    /// Fills a scribbled area and smooths its edge, on a grid in the view it was drawn from.
    /// Gaps between passes close up, enclosed holes fill, and the outline is blurred and cut at
    /// halfway, so straight edges keep their place while bumps and corners round off.
    func areaMask(_ path: [[Double]], r: Double, yaw: Double) -> AreaMask? {
        if path.isEmpty { return nil }
        let pts = path.map { p -> (Double, Double) in let s = BodyMesh.toScreen(p, yaw: yaw); return (s.sx, s.sy) }
        let close = r * BodyPaint.fillClose, blur = r * BodyPaint.fillSmooth, reach = r + close
        let pad = reach + 3 * blur + r
        let xs = pts.map(\.0), ys = pts.map(\.1)
        let x0 = xs.min()! - pad, y0 = ys.min()! - pad
        let spanX = xs.max()! + pad - x0, spanY = ys.max()! + pad - y0
        let h = max(r / 4, max(spanX, spanY) / 256)
        let w = Int(ceil(spanX / h)), ht = Int(ceil(spanY / h)), size = w * ht

        // Distance from each cell to the nearest brush touch, within reach of one.
        var near = [Double](repeating: .infinity, count: size)
        for (px, py) in pts {
            let i0 = max(0, Int(floor((px - reach - x0) / h))), i1 = min(w - 1, Int(ceil((px + reach - x0) / h)))
            let j0 = max(0, Int(floor((py - reach - y0) / h))), j1 = min(ht - 1, Int(ceil((py + reach - y0) / h)))
            if i0 > i1 || j0 > j1 { continue }
            for j in j0...j1 {
                let dy = y0 + (Double(j) + 0.5) * h - py
                for i in i0...i1 {
                    let d = hypot(x0 + (Double(i) + 0.5) * h - px, dy), at = j * w + i
                    if d < near[at] { near[at] = d }
                }
            }
        }
        // Grow the paint by `close`, then shrink it back by the same amount, keeping everything painted.
        let grown = near.map { $0 > reach ? UInt8(1) : 0 }
        let fromEdge = BodyPaint.gridDistance(w, ht, grown)
        var fill = [UInt8](repeating: 0, count: size)
        for i in 0..<size { fill[i] = near[i] <= r || (fromEdge[i] - 0.5) * h >= close ? 1 : 0 }
        // Anything unpainted that can't reach the border is enclosed, so it fills in.
        var out = [UInt8](repeating: 0, count: size), queue = [Int](repeating: 0, count: size)
        var head = 0, tail = 0
        func visit(_ at: Int) { if fill[at] == 0 && out[at] == 0 { out[at] = 1; queue[tail] = at; tail += 1 } }
        for i in 0..<w { visit(i); visit((ht - 1) * w + i) }
        for j in 0..<ht { visit(j * w); visit(j * w + w - 1) }
        while head < tail {
            let at = queue[head], i = at % w
            head += 1
            if i > 0 { visit(at - 1) }
            if i < w - 1 { visit(at + 1) }
            if at >= w { visit(at - w) }
            if at < size - w { visit(at + w) }
        }
        // Blur the filled shape; the shader draws its edge where the blur crosses one half.
        let sig = blur / h, rad = Int(ceil(sig * 3))
        let ker = (-rad...rad).map { k in exp(-Double(k * k) / (2 * sig * sig)) }
        let sum = ker.reduce(0, +)
        var across = [Double](repeating: 0, count: size), soft = [Double](repeating: 0, count: size)
        for j in 0..<ht {
            for i in 0..<w {
                var v = 0.0
                for k in -rad...rad {
                    let x = i + k
                    if x >= 0 && x < w && out[j * w + x] == 0 { v += ker[k + rad] }
                }
                across[j * w + i] = v / sum
            }
        }
        for j in 0..<ht {
            for i in 0..<w {
                var v = 0.0
                for k in -rad...rad {
                    let y = j + k
                    if y >= 0 && y < ht { v += across[y * w + i] * ker[k + rad] }
                }
                soft[j * w + i] = v / sum
            }
        }
        var bytes = [UInt8](repeating: 0, count: size), sat = [Int32](repeating: 0, count: (w + 1) * (ht + 1))
        for j in 0..<ht {
            for i in 0..<w {
                let v = soft[j * w + i]
                bytes[j * w + i] = UInt8(max(0, min(255, (v * 255).rounded())))
                sat[(j + 1) * (w + 1) + i + 1] = (v > 0.3 ? 1 : 0) + sat[j * (w + 1) + i + 1] + sat[(j + 1) * (w + 1) + i] - sat[j * (w + 1) + i]
            }
        }
        return AreaMask(x0: x0, y0: y0, h: h, w: w, ht: ht, bytes: bytes, sat: sat)
    }

    /// Distance in cells from every cell to the nearest source cell (Felzenszwalb and Huttenlocher).
    /// Every row and column must hold a source; the masks' empty borders make sure of that.
    static func gridDistance(_ w: Int, _ h: Int, _ src: [UInt8]) -> [Double] {
        let inf = 1e20, len = max(w, h)
        var g = src.map { $0 != 0 ? 0 : inf }
        var f = [Double](repeating: 0, count: len), d = [Double](repeating: 0, count: len)
        var v = [Int](repeating: 0, count: len), z = [Double](repeating: 0, count: len + 1)
        func line(_ n: Int, _ at: (Int) -> Int) {
            for q in 0..<n { f[q] = g[at(q)] }
            var k = 0
            v[0] = 0; z[0] = -inf; z[1] = inf
            if n > 1 {
                for q in 1..<n {
                    func s() -> Double { ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k]) }
                    var t = s()
                    while t <= z[k] { k -= 1; t = s() }
                    k += 1; v[k] = q; z[k] = t; z[k + 1] = inf
                }
            }
            k = 0
            for q in 0..<n {
                while z[k + 1] < Double(q) { k += 1 }
                d[q] = Double((q - v[k]) * (q - v[k])) + f[v[k]]
            }
            for q in 0..<n { g[at(q)] = d[q] }
        }
        for x in 0..<w { line(h) { $0 * w + x } }
        for y in 0..<h { line(w) { y * w + $0 } }
        return g.map { $0.squareRoot() }
    }

    /// The skin an area's mask may color: connected triangles, starting under the touches, that face
    /// the side it was drawn from and overlap the mask. It never crosses to skin hidden behind.
    func areaTris(_ starts: [Int], mask: AreaMask, yaw: Double) -> [UInt16] {
        let T = mesh.triangles, P = mesh.positions, N = mesh.normals
        let d = BodyMesh.viewDir(yaw)
        let t = yaw * .pi / 180, c = cos(t), s = sin(t)
        var seen = [Bool](repeating: false, count: T.count / 3)
        var queue: [Int] = [], out: [UInt16] = []
        let W = mask.w + 1
        func ok(_ tri: Int) -> Bool {
            var face = 0.0, minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
            for k in 0..<3 {
                let o = Int(T[tri * 3 + k]) * 3
                face += Double(N[o]) * d[0] + Double(N[o + 1]) * d[1] + Double(N[o + 2]) * d[2]
                let x = P[o], y = P[o + 1], z = P[o + 2]
                let sx = x * c + z * s, cz = -x * s + z * c, v = y - BodyMesh.cy
                let sy = v * BodyMesh.cosP + cz * BodyMesh.sinP + BodyMesh.cy
                minX = min(minX, sx); maxX = max(maxX, sx); minY = min(minY, sy); maxY = max(maxY, sy)
            }
            if face < -0.15 { return false }
            let i0 = Int(floor((minX - mask.x0) / mask.h - 0.5)), i1 = Int(ceil((maxX - mask.x0) / mask.h - 0.5))
            let j0 = Int(floor((minY - mask.y0) / mask.h - 0.5)), j1 = Int(ceil((maxY - mask.y0) / mask.h - 0.5))
            if i1 < 0 || j1 < 0 || i0 >= mask.w || j0 >= mask.ht { return false }
            func cell(_ v: Int, _ hi: Int) -> Int { max(0, min(hi, v)) }
            let a = cell(i0, mask.w - 1), b = cell(i1, mask.w - 1) + 1, cc = cell(j0, mask.ht - 1), e = cell(j1, mask.ht - 1) + 1
            return mask.sat[e * W + b] - mask.sat[cc * W + b] - mask.sat[e * W + a] + mask.sat[cc * W + a] > 0
        }
        func offer(_ tri: Int) { if !seen[tri] { seen[tri] = true; if ok(tri) { queue.append(tri) } } }
        func around(_ v: Int) { for j in Int(tStart[v])..<Int(tStart[v + 1]) { offer(Int(tTo[j])) } }
        for v3 in starts { around(v3 / 3) }
        while let tri = queue.popLast() {
            out.append(contentsOf: [T[tri * 3], T[tri * 3 + 1], T[tri * 3 + 2]])
            for k in 0..<3 { around(Int(T[tri * 3 + k])) }
        }
        return out
    }
}

private func hypot3(_ x: Double, _ y: Double, _ z: Double) -> Double { (x * x + y * y + z * z).squareRoot() }
