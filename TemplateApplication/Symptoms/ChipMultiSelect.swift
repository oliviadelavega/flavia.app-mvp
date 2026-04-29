//
// Flavia study app
//
// Wrap-laid-out multi-select chip group. Each tap toggles the chip's
// token in the bound selection array (preserving stable insertion order
// rather than the order in `options`, so the array round-trips through
// Firestore predictably).
//

import SwiftUI


struct ChipMultiSelect: View {
    let options: [String]
    @Binding var selection: [String]
    var label: (String) -> String = { $0.replacingOccurrences(of: "_", with: " ") }


    var body: some View {
        ChipFlowLayout(spacing: 8, runSpacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection.contains(option)
                Button {
                    toggle(option)
                } label: {
                    Text(label(option))
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }


    private func toggle(_ option: String) {
        if let index = selection.firstIndex(of: option) {
            selection.remove(at: index)
        } else {
            selection.append(option)
        }
    }
}


private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8


    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arrangement = arrange(subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: arrangement.size.width, height: arrangement.size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, frame) in arrangement.frames.enumerated() {
            let origin = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subviews[index].place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }


    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > maxWidth, cursorX > 0 {
                cursorX = 0
                cursorY += rowHeight + runSpacing
                rowHeight = 0
            }
            frames.append(CGRect(x: cursorX, y: cursorY, width: size.width, height: size.height))
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, cursorX - spacing)
        }

        return (frames, CGSize(width: totalWidth, height: cursorY + rowHeight))
    }
}


#Preview {
    @Previewable @State var selection: [String] = ["hands", "face"]

    Form {
        Section("Body parts affected") {
            ChipMultiSelect(
                options: SymptomVocabulary.bodyParts,
                selection: $selection
            )
        }
    }
}
