import MetalKit
import SwiftUI

/// The body shape controls in Settings: a front and side preview, Gender and Build sliders, and a reset.
struct BodyShapeSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To customize body shape model to your body type, you may make modifications here:")
            if model.shapesAvailable, let mesh = model.mesh {
                BodyPreview(mesh: mesh, shapeVersion: model.shapeVersion)
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement()
                    .accessibilityLabel("Preview of the body shape, from the front and the side")
                    .accessibilityAddTraits(.isImage)
                slider("Gender", value: \.g, low: "Feminine", mid: "Androgynous", high: "Masculine")
                slider("Build", value: \.b, low: "Slimmer", mid: "Average", high: "Fuller")
                Button { model.setShape(BodyShape()) } label: {
                    Text("Reset to default")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(model.shape.isDefault ? Ink.off : Ink.teal)
                        .overlay(Capsule().stroke(model.shape.isDefault ? Ink.off : Ink.teal, lineWidth: 1))
                }
                .disabled(model.shape.isDefault)
            } else {
                Text("Body shape options aren’t available on this device.")
            }
        }
    }

    private func slider(_ title: String, value key: WritableKeyPath<BodyShape, Int>, low: String, mid: String, high: String) -> some View {
        let v = model.shape[keyPath: key]
        let words = v == 0 ? "Default" : (v < 0 ? low : high) + ", \(abs(v)) percent"
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold))
            Slider(value: Binding(
                get: { Double(model.shape[keyPath: key]) },
                set: { n in
                    var next = model.shape
                    next[keyPath: key] = Int(n.rounded())
                    model.setShape(next)
                }), in: -100...100, step: 1)
                .tint(Ink.teal)
                .accessibilityLabel(title)
                .accessibilityValue(words)
            HStack {
                Text(low)
                Spacer()
                Text(mid)
                Spacer()
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(Ink.muted)
            .accessibilityHidden(true)
        }
    }
}

/// The body from the front and from the side, filling each half of the view, as the prototype's preview does.
struct BodyPreview: UIViewRepresentable {
    let mesh: BodyMesh
    var shapeVersion: Int

    final class Coordinator { var renderer: BodyRenderer? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView()
        v.device = MTLCreateSystemDefaultDevice()
        v.enableSetNeedsDisplay = true
        v.isPaused = true
        v.isUserInteractionEnabled = false
        context.coordinator.renderer = BodyRenderer(view: v, mesh: mesh)
        v.delegate = context.coordinator.renderer
        return v
    }

    func updateUIView(_ v: MTKView, context: Context) {
        guard let r = context.coordinator.renderer else { return }
        r.shotsFor = { size in
            // fitMap(): the figure fills 96% of the height, centred in each half.
            let k: Float = 0.96
            let w = Float(max(size.width, 1)) / 2, h = Float(max(size.height, 1))
            let fw = h * k * 240 / 440, a = 2 * fw / 240 / w
            let map = SIMD4<Float>(a, -2 * k / 440, -a * 120, k)
            return [
                BodyRenderer.Shot(yaw: 0, map: map, area: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
                BodyRenderer.Shot(yaw: 90, map: map, area: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
            ]
        }
        v.setNeedsDisplay()
    }
}
