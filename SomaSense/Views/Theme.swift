import SwiftUI

/// The prototype's colours.
enum Ink {
    static let text = Color(hex: 0x14282C)
    static let muted = Color(hex: 0x4F6368)
    static let teal = Color(hex: 0x0B6169)
    static let paint = Color(hex: 0x2E8F95)
    static let stage = Color(hex: 0xF3F6F6)
    static let line = Color(hex: 0xC4D0D0)
    static let faint = Color(hex: 0xE4EAEA)
    static let off = Color(hex: 0xA5B4B5)
    static let disabled = Color(hex: 0xD3DCDC)
    static let rust = Color(hex: 0xB8430F)
    static let selectedRow = Color(hex: 0xE6F2F2)
    static let free = Color(hex: 0x8EDB8F)
    static let mild = Color(hex: 0xD6ECEC)
    static let moderate = Color(hex: 0x86C6C4)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A rounded choice bubble, filled when chosen.
struct Chip: View {
    var label: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(on ? .white : Ink.text)
                .background(on ? Ink.teal : .white, in: Capsule())
                .overlay(Capsule().stroke(on ? Ink.teal : Ink.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Wraps its children onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let h = rows.last.map { $0.y + $0.h } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.w).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var w: CGFloat = 0; var h: CGFloat = 0 }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].w + spacing + s.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.h + spacing))
            }
            var r = rows[rows.count - 1]
            r.w += (r.items.isEmpty ? 0 : spacing) + s.width
            r.h = max(r.h, s.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text).font(.headline).foregroundStyle(Ink.text).accessibilityAddTraits(.isHeader)
    }
}
