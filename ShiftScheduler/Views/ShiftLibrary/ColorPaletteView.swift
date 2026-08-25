import SwiftUI

/// 预设色板选择网格（R03）：12 色圆形色块，选中带描边。
struct ColorPaletteView: View {

    /// 当前选中的 hex
    @Binding var selectedHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Theme.palette) { paletteColor in
                Button {
                    selectedHex = paletteColor.hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(paletteHex: paletteColor.hex))
                            .frame(width: 34, height: 34)
                        if paletteColor.hex == Theme.normalizedHex(selectedHex) {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.7),
                                              lineWidth: 2)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(paletteColor.name)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 色板预览（供 ShiftEditView 内嵌使用说明）
#Preview("色板") {
    struct Demo: View {
        @State private var hex = "#FDD835"
        var body: some View {
            VStack {
                ColorPaletteView(selectedHex: $hex)
                Text(hex).font(.caption.monospaced())
            }
            .padding()
        }
    }
    return Demo()
}
