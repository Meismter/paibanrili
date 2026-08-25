import SwiftUI

/// 轮转序列编辑器（R10）：从已有班次中增删排序，形成循环序列（如 早→中→夜→休）。
struct RotationEditorView: View {

    /// 全部可选班次
    let shifts: [ShiftDefinition]
    /// 当前轮转序列（可变绑定）
    @Binding var pattern: [UUID]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("轮转序列（循环填充）")
                .font(.subheadline.bold())

            if pattern.isEmpty {
                Text("尚未添加班次，点击下方按钮按顺序加入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pattern.enumerated()), id: \.offset) { index, shiftID in
                            token(index: index, shiftID: shiftID)
                        }
                    }
                }
                Text(patternText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Menu {
                ForEach(shifts) { shift in
                    Button {
                        pattern.append(shift.id)
                    } label: {
                        Label(shift.name + " " + shift.timeRangeText,
                              systemImage: "plus.circle")
                    }
                }
            } label: {
                Label("添加班次到序列", systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 子元素

    private func token(index: Int, shiftID: UUID) -> some View {
        let shift = shifts.first { $0.id == shiftID }
        return HStack(spacing: 4) {
            if let shift {
                Circle().fill(Color(paletteHex: shift.colorHex)).frame(width: 8, height: 8)
                Text(shift.name).font(.caption)
            } else {
                Text("?").font(.caption)
            }
            Button {
                pattern.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    private var patternText: String {
        pattern.compactMap { id in shifts.first { $0.id == id }?.name }
            .joined(separator: " → ") + " → (循环)"
    }
}
