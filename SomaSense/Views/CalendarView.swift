import SwiftUI

/// The month calendar, coloured by each day's highest severity, with the chosen day's reports below.
struct CalendarView: View {
    @Environment(AppModel.self) private var model

    private struct Shown { var report: Report; var points: [BodyPoint] }

    private var visible: [Shown] {
        model.reports.map { r in Shown(report: r, points: r.points.filter { model.area == "all" || $0.area == model.area }) }
            .filter { !$0.points.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("Where and when symptoms were reported").foregroundStyle(Ink.muted)
                    }
                    Spacer(minLength: 0)
                    ShareButton(label: "Share", hint: "Shares this month’s log") { model.openShare() }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AppModel.areas, id: \.0) { a in
                            Chip(label: a.1, on: model.area == a.0) { model.area = a.0 }
                        }
                    }
                }
                monthHeader
                grid
                legend
                dayPanel
            }
            .padding(20)
        }
        .background(Color.white)
        .foregroundStyle(Ink.text)
    }

    private var monthHeader: some View {
        HStack {
            Button { model.calMonth = Day.addingMonths(model.calMonth, -1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous month")
            Spacer()
            Text(Day.monthTitle(model.calMonth)).font(.title3.bold())
            Spacer()
            Button { model.calMonth = Day.addingMonths(model.calMonth, 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Next month")
        }
    }

    private var grid: some View {
        let month = model.calMonth, lead = Day.weekday(month + "-01"), n = Day.daysIn(month)
        let shown = visible
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { w in
                Text(w).font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
            }
            ForEach(0..<lead, id: \.self) { i in Color.clear.frame(height: 48).id("blank\(i)") }
            ForEach(1...n, id: \.self) { d in
                let key = month + "-" + String(format: "%02d", d)
                dayCell(key, d, shown.filter { $0.report.date == key })
            }
        }
    }

    private func dayCell(_ key: String, _ d: Int, _ list: [Shown]) -> some View {
        let maxSev = list.map(\.report.severity).max() ?? 0
        let free = model.log.symptomFree.contains(key)
        let sel = key == model.calDay, today = key == model.today
        let bg: Color = free ? Ink.free : list.isEmpty ? .white : maxSev <= 3 ? Ink.mild : maxSev <= 6 ? Ink.moderate : Ink.teal
        let fg: Color = !list.isEmpty && maxSev > 6 ? .white : Ink.text
        let border: (Color, CGFloat) = sel ? (Ink.rust, 3) : today ? (Ink.text, 2) : (Ink.faint, 1)
        let aria = Day.short(key) + ", " + (free ? "no symptoms" : Words.plural(list.count, "report"))
            + (list.isEmpty ? "" : ", highest severity \(maxSev)") + (today ? ", today" : "")
        return Button { model.calDay = key } label: {
            VStack(spacing: 0) {
                Text("\(d)").font(.subheadline.weight(today ? .bold : .regular))
                Text(free ? "✓" : list.isEmpty ? " " : "\(list.count)").font(.caption2.bold())
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(bg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border.0, lineWidth: border.1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(aria)
        .accessibilityAddTraits(sel ? .isSelected : [])
    }

    private var legend: some View {
        FlowLayout(spacing: 12) {
            Text("Highest severity").font(.caption.weight(.semibold))
            swatch(Ink.mild, "Mild")
            swatch(Ink.moderate, "Moderate")
            swatch(Ink.teal, "Severe")
            HStack(spacing: 4) {
                Text("✓").font(.caption2.bold()).frame(width: 14, height: 14).background(Ink.free, in: RoundedRectangle(cornerRadius: 3))
                Text("No symptoms")
            }.font(.caption)
        }
        .foregroundStyle(Ink.muted)
    }

    private func swatch(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 14, height: 14)
            Text(label)
        }.font(.caption)
    }

    private var dayPanel: some View {
        let free = model.log.symptomFree.contains(model.calDay)
        let list = visible.filter { $0.report.date == model.calDay }.sorted { $0.report.time < $1.report.time }
        let sub = free ? "Marked symptom-free. Tap below to undo." : !list.isEmpty ? Words.plural(list.count, "report")
            : "Nothing reported" + (model.area == "all" ? "" : " in this area")
        return VStack(alignment: .leading, spacing: 12) {
            Text(Day.long(model.calDay)).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(Ink.muted)
            if model.canMarkFree {
                Button { model.toggleFree() } label: {
                    Label("No symptoms", systemImage: "checkmark")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(free ? Ink.free : .white, in: Capsule())
                        .overlay(Capsule().stroke(Ink.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(free ? .isSelected : [])
            }
            if !list.isEmpty {
                HStack(spacing: 24) {
                    Spacer()
                    thumb(front: true, list)
                    thumb(front: false, list)
                    Spacer()
                }
                ForEach(list, id: \.report.id) { x in
                    Button { model.detailId = x.report.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Words.time(x.report.time) + " · " + x.report.cats.joined(separator: ", ")).font(.body.weight(.semibold))
                                Spacer()
                                Text("\(x.report.severity)/10").font(.body.weight(.semibold))
                            }
                            Text(x.points.map(\.label).joined(separator: ", ")).font(.subheadline).foregroundStyle(Ink.muted)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.faint, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func thumb(front: Bool, _ list: [Shown]) -> some View {
        let w: CGFloat = 86, h: CGFloat = 158
        let yaw: Double = front ? 0 : 180
        var dots: [BodyMesh.Screen] = []
        for x in list {
            for p in x.points {
                let touches: [(p: [Double], n: [Double], v: Int?)] = p.path.map { $0.map { ($0.p, $0.n, nil) } } ?? [(p.p, p.n, p.v)]
                for t in touches where (t.n[2] >= 0) == front {
                    let shown: [Double] = model.mesh?.fromBase(t.p, v: t.v) ?? t.p
                    dots.append(BodyMesh.toScreen(shown, yaw: yaw))
                }
            }
        }
        let custom = model.thumbnails()
        let fallback: UIImage = UIImage(named: front ? "body-front" : "body-back") ?? UIImage()
        let picture: UIImage = (front ? custom?.front : custom?.back) ?? fallback
        return VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Image(uiImage: picture).resizable().frame(width: w, height: h)
                ForEach(Array(dots.enumerated()), id: \.offset) { _, q in
                    let at = CGPoint(x: (q.sx + 120) / 240 * w, y: q.sy / 440 * h)
                    Circle().fill(Ink.teal).frame(width: 8, height: 8).position(at)
                }
            }
            .frame(width: w, height: h)
            Text(front ? "Front" : "Back").font(.caption).foregroundStyle(Ink.muted)
        }
        .accessibilityHidden(true)
    }
}
