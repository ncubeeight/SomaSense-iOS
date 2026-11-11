import CoreGraphics
import Foundation
import Observation

/// Where the body map is looking: turn, zoom and pan, with the figure laid out as in the prototype.
/// The figure is top-aligned and centred, leaving a gap under the feet; zoom scales about its centre.
@MainActor @Observable
final class BodyCamera {
    static let feetGap: CGFloat = 32
    static let maxZoom: CGFloat = 6

    var yaw: Double = 0
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var stage: CGSize = .zero

    @ObservationIgnored private var snapTimer: Task<Void, Never>?

    var baseFigure: CGSize {
        let h = max(1, min(640, stage.height - BodyCamera.feetGap))
        return CGSize(width: h * 240 / 440, height: h)
    }

    /// The figure's rectangle in the stage, after zoom and pan.
    var figureRect: CGRect {
        let b = baseFigure
        let w = b.width * zoom, h = b.height * zoom
        let cx = stage.width / 2 + pan.width, cy = b.height / 2 + pan.height
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Figure units (x -120...120, y 0...440) to stage points, and back.
    func toStage(sx: Double, sy: Double) -> CGPoint {
        let r = figureRect
        return CGPoint(x: r.minX + (sx + 120) / 240 * r.width, y: r.minY + sy / 440 * r.height)
    }

    func toFigure(_ p: CGPoint) -> (sx: Double, sy: Double) {
        let r = figureRect
        return ((p.x - r.minX) / r.width * 240 - 120, (p.y - r.minY) / r.height * 440)
    }

    /// The shader's mapping from figure units to Metal's clip space.
    var clipMap: SIMD4<Float> {
        let r = figureRect, w = max(stage.width, 1), h = max(stage.height, 1)
        return SIMD4(Float(2 * r.width / 240 / w), Float(-2 * r.height / 440 / h), Float(2 * r.minX / w - 1), Float(1 - 2 * r.minY / h))
    }

    static func normYaw(_ y: Double) -> Double {
        let v = ((y + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
        return v == -180 ? 180 : v
    }

    func clampedPan(_ z: CGFloat, _ p: CGSize) -> CGSize {
        if z <= 1 { return .zero }
        let b = baseFigure, mx = b.width * z / 2, my = b.height * z / 2
        return CGSize(width: max(-mx, min(mx, p.width)), height: max(-my, min(my, p.height)))
    }

    /// Scales about a stage point, so what is under the fingers stays there.
    func zoom(to z: CGFloat, about f: CGPoint) {
        let next = max(1, min(BodyCamera.maxZoom, z))
        let r = figureRect
        let k = 1 - next / zoom
        pan = clampedPan(next, CGSize(width: pan.width + (f.x - r.midX) * k, height: pan.height + (f.y - r.midY) * k))
        zoom = next
    }

    func zoomStep(_ factor: CGFloat) {
        snapTimer?.cancel()
        let z = zoom * factor
        zoom(to: z < 1.05 ? 1 : z, about: CGPoint(x: stage.width / 2, y: stage.height / 2))
    }

    func reset() {
        snapTimer?.cancel()
        zoom = 1
        pan = .zero
    }

    /// Turns to an angle in 10° steps, as the prototype does. With reduced motion it jumps there.
    func snap(to target: Double, reduceMotion: Bool) {
        snapTimer?.cancel()
        if reduceMotion { yaw = target; return }
        snapTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                let gap = BodyCamera.normYaw(target - self.yaw)
                if abs(gap) <= 10 {
                    self.yaw = target
                    return
                }
                self.yaw = BodyCamera.normYaw(self.yaw + (gap > 0 ? 10 : -10))
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func stopSnap() { snapTimer?.cancel() }
}
