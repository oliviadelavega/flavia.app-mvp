//
// Flavia study app
//
// 0–5 segmented scale with named anchors at the low and high ends.
//

import SwiftUI


struct ScalePicker: View {
    let title: LocalizedStringResource
    let anchors: (low: LocalizedStringResource, high: LocalizedStringResource)
    @Binding var selection: Int?

    private let range = 0...5


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(range, id: \.self) { value in
                    Button {
                        selection = (selection == value) ? nil : value
                    } label: {
                        Text("\(value)")
                            .font(.body.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(selection == value ? Color.accentColor : Color.secondary)
                }
            }

            HStack {
                Text(anchors.low)
                Spacer()
                Text(anchors.high)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}


#Preview {
    @Previewable @State var value: Int? = 2

    Form {
        ScalePicker(
            title: "Itch level",
            anchors: ("none", "unbearable"),
            selection: $value
        )
    }
}
