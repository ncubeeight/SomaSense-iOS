import SwiftUI

/// One report's details, with edit and delete.
struct DetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: Report
    @State private var armed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.cats.joined(separator: ", ")).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                        Text(Day.long(report.date) + " at " + Words.time(report.time)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Button { model.startEdit(report) } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                        .accessibilityLabel("Edit report")
                    Button { model.detailId = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close report details")
                }
                ForEach(Array(Words.rows(report).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.key).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.muted)
                        Text(row.value)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    if armed { model.deleteReport(report.id) } else { armed = true }
                } label: {
                    Text(armed ? "Tap again to delete for good" : "Delete report")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(armed ? .white : Ink.rust)
                        .background(armed ? Ink.rust : .white, in: Capsule())
                        .overlay(Capsule().stroke(Ink.rust, lineWidth: 1))
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .foregroundStyle(Ink.text)
        .tint(Ink.text)
        .presentationDetents([.medium, .large])
    }
}
