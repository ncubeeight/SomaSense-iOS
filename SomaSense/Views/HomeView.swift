import SwiftUI

/// The body map: tap to mark points, drag to turn, pinch to zoom.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let views: [(String, Double)] = [("Front", 0), ("Right", 90), ("Back", 180), ("Left", -90)]

    var body: some View {
        let cam = model.camera
        VStack(spacing: 0) {
            dayHeader
            viewChips
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    BodyStage(model: model, yaw: model.shownYaw, map: cam.clipMap, shapeVersion: model.shapeVersion)
                    pins
                    sideLabels(geo.size)
                    controls
                }
                .onAppear { cam.stage = geo.size }
                .onChange(of: geo.size) { _, s in cam.stage = s }
            }
            .clipped()
            bottom
        }
        .background(Ink.stage)
    }

    private var dayHeader: some View {
        let isToday = model.homeDay == model.today
        let n = model.reports.filter { $0.date == model.homeDay }.count
        return HStack {
            Button { model.dayPrev() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 2) {
                Text(isToday ? "Today" : Day.long(model.homeDay)).font(.title3.bold())
                Text((isToday ? Day.long(model.homeDay) + " · " : "") + Words.plural(n, "report")).font(.subheadline).foregroundStyle(Ink.muted)
            }
            Spacer()
            Button { model.dayNext() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(isToday)
                .accessibilityLabel("Next day")
        }
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var viewChips: some View {
        HStack(spacing: 4) {
            ForEach(Self.views, id: \.0) { v in
                let on = abs(BodyCamera.normYaw(model.camera.yaw - v.1)) <= 22.5
                Button { model.camera.snap(to: v.1, reduceMotion: reduceMotion) } label: {
                    Text(v.0).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? .white : Ink.text)
                        .background(on ? Ink.teal : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.white, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var pins: some View {
        let cam = model.camera, yaw = model.shownYaw
        return ForEach(Array(model.selected.enumerated()), id: \.element.id) { i, stored in
            let p = model.shown(stored)
            let q = BodyMesh.toScreen(p.p, yaw: yaw)
            let at = cam.toStage(sx: q.sx, sy: q.sy)
            let seen = model.mesh?.isVisible(p, yaw: yaw) ?? true
            let size: CGFloat = !seen ? 22 : cam.zoom >= 2 ? 26 : 32
            Button { model.removePin(p.id) } label: {
                Text("\(i + 1)")
                    .font(.system(size: !seen || cam.zoom >= 2 ? 12 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Ink.teal, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .opacity(seen ? 1 : 0.4)
            .allowsHitTesting(seen)
            .position(at)
            .accessibilityLabel((seen ? "Remove " : "") + (p.isArea ? "area " : "point ") + "\(i + 1), " + p.label + (seen ? "" : ", on the far side"))
        }
    }

    @ViewBuilder private func sideLabels(_ size: CGSize) -> some View {
        let yaw = model.shownYaw
        let nearFront = abs(yaw) < 50, nearBack = abs(yaw) > 130
        if nearFront || nearBack {
            HStack {
                Text(nearFront ? "Right" : "Left")
                Spacer()
                Text(nearFront ? "Left" : "Right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ink.muted)
            .padding(.horizontal, 16)
            .frame(width: size.width)
            .position(x: size.width / 2, y: size.height * 0.45)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        let cam = model.camera
        return VStack {
            Spacer()
            HStack(alignment: .bottom) {
                if cam.zoom > 1 {
                    VStack(spacing: 8) {
                        round("arrow.counterclockwise", "Turn body left") { cam.snap(to: BodyCamera.normYaw(cam.yaw - 30), reduceMotion: reduceMotion) }
                        round("arrow.clockwise", "Turn body right") { cam.snap(to: BodyCamera.normYaw(cam.yaw + 30), reduceMotion: reduceMotion) }
                    }
                }
                Spacer()
                VStack(spacing: 8) {
                    round("plus", "Zoom in") { cam.zoomStep(2) }.disabled(cam.zoom >= BodyCamera.maxZoom)
                    round("minus", "Zoom out") { cam.zoomStep(0.5) }.disabled(cam.zoom <= 1)
                }
            }
            .padding(12)
        }
    }

    private func round(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(Ink.line, lineWidth: 1))
        }
        .foregroundStyle(Ink.text)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var bottom: some View {
        if model.selected.isEmpty {
            let zoomed = model.camera.zoom > 1
            VStack(spacing: 4) {
                Text(zoomed ? "Tap the exact spot. Drag to move around." : "Tap where you feel it. Drag to turn the body.")
                    .font(.body.weight(.semibold)).foregroundStyle(Ink.text)
                Text(zoomed ? "Pinch or use minus to zoom out." : "Zoom in to mark fingers or toes.")
                    .font(.subheadline).foregroundStyle(Ink.muted)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        } else {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What are you feeling here?").font(.headline)
                        Text(model.selectedSummary).font(.subheadline).foregroundStyle(Ink.muted).lineLimit(2)
                    }
                    Spacer()
                    Button("Clear") { model.clearPins() }.foregroundStyle(Ink.teal).frame(minHeight: 44)
                }
                Button { model.startCompose() } label: {
                    Label("Add symptom details", systemImage: "arrow.right")
                        .labelStyle(TrailingIcon())
                        .font(.body.bold())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white)
                        .background(Ink.teal, in: Capsule())
                }
            }
            .foregroundStyle(Ink.text)
            .padding(20)
            .background(.white)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Add details for marked points")
        }
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

/// Hosts the Metal stage and feeds it the camera.
struct BodyStage: UIViewRepresentable {
    let model: AppModel
    var yaw: Double
    var map: SIMD4<Float>
    var shapeVersion: Int

    func makeUIView(context: Context) -> BodyStageView {
        let v = BodyStageView(mesh: model.mesh, camera: model.camera)
        v.onTap = { [weak model] pt in
            guard let model else { return }
            let f = model.camera.toFigure(pt)
            model.tap(sx: f.sx, sy: f.sy)
        }
        return v
    }

    func updateUIView(_ v: BodyStageView, context: Context) {
        v.redraw(yaw: yaw)
    }
}
