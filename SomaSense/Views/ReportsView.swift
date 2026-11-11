import SwiftUI

/// How often each symptom type was reported, with a breakdown of the chosen type.
struct ReportsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = ReportSummary(reports: model.reports, symptomFree: model.log.symptomFree, range: model.range, today: model.today)
        let active = s.groups.first { $0.cat == model.drillCat } ?? s.groups.first
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reports").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Frequency by symptom or sensation").foregroundStyle(Ink.muted)
                }
                HStack(spacing: 8) {
                    ForEach([7, 30, 90], id: \.self) { n in
                        Chip(label: "\(n) days", on: model.range == n) { model.range = n }
                    }
                }
                HStack(spacing: 8) {
                    tile("\(s.inRange.count)", "Reports")
                    tile("\(s.days)", "Days with symptoms")
                    tile(ReportSummary.mean(s.inRange), "Avg severity")
                }
                types(s, active: active?.cat)
                if let active { drill(active, s) }
                Text("This log is a record to share with your clinician. It does not diagnose or give medical advice.")
                    .font(.footnote).foregroundStyle(Ink.muted)
            }
            .padding(20)
        }
        .background(Color.white)
        .foregroundStyle(Ink.text)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.bold())
            Text(label).font(.caption).foregroundStyle(Ink.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(Ink.stage, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func types(_ s: ReportSummary, active: String?) -> some View {
        let top = Double(s.groups.first?.list.count ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "How often, by type")
            Text("A report with two types counts once in each. Tap a type for details.").font(.subheadline).foregroundStyle(Ink.muted)
            if s.groups.isEmpty {
                Text("No reports in this period.").foregroundStyle(Ink.muted)
            }
            ForEach(s.groups, id: \.cat) { g in
                let on = g.cat == active
                Button { model.drillCat = g.cat } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(g.cat).font(.body.weight(.semibold))
                            Spacer()
                            Text("\(g.list.count) · avg severity " + ReportSummary.mean(g.list)).font(.subheadline).foregroundStyle(Ink.muted)
                        }
                        bar(Double(g.list.count) / top)
                    }
                    .padding(10)
                    .background(on ? Ink.selectedRow : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.faint)
                Capsule().fill(Ink.teal).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 8)
    }

    private func drill(_ g: ReportSummary.Group, _ s: ReportSummary) -> some View {
        let d = TypeDetail(list: g.list, range: model.range, from: s.from, today: model.today)
        let maxW = Double(d.where_.first?.count ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(g.cat).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Text(Words.plural(g.list.count, "report") + " in the last \(model.range) days").foregroundStyle(Ink.muted)
            Text("Over time").font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(d.buckets.enumerated()), id: \.offset) { _, b in
                    VStack(spacing: 2) {
                        Text(b.n > 0 ? "\(b.n)" : "").font(.caption2)
                        RoundedRectangle(cornerRadius: 3).fill(Ink.teal)
                            .frame(height: b.n > 0 ? max(4, CGFloat(b.n) / CGFloat(d.maxBucket) * 56) : 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
            .accessibilityElement()
            .accessibilityLabel(g.cat + " reports per " + (d.size == 1 ? "day" : "week") + ": " + d.buckets.map { "\($0.n)" }.joined(separator: ", "))
            HStack {
                Text(Day.short(d.buckets.first?.start ?? s.from))
                Spacer()
                Text(Day.short(d.buckets.last?.end ?? model.today))
            }
            .font(.caption).foregroundStyle(Ink.muted)
            Text("Where on the body").font(.subheadline.weight(.semibold))
            ForEach(d.where_, id: \.label) { w in row(w.label, w.count, Double(w.count) / maxW) }
            Text("Time of day").font(.subheadline.weight(.semibold))
            ForEach(d.parts, id: \.label) { p in row(p.label, p.count, Double(p.count) / Double(d.maxPart)) }
            Text("Logged alongside").font(.subheadline.weight(.semibold))
            if d.context.isEmpty {
                Text("No medicines, activities or other sensations logged.").font(.subheadline).foregroundStyle(Ink.muted)
            } else {
                FlowLayout {
                    ForEach(d.context, id: \.label) { c in
                        Text(c.label + " · \(c.count)").font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Ink.stage, in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.faint, lineWidth: 1))
    }

    private func row(_ label: String, _ count: Int, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label); Spacer(); Text("\(count)") }.font(.subheadline)
            bar(fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(count)")
    }
}
