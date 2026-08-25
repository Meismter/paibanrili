import SwiftUI

/// 日期格（R01 / 批次 A）：日期数字 + 彩色班次胶囊（最多展示 2 个 + "+N"）。
/// 批次 A：每格加浅底色圆角框；有班次时框底色随首个班次颜色变化（浅色变体）；
/// 今天以 accent 描边 + 浅色圆点高亮。
struct DayCellView: View {

    let day: Date
    let entries: [ScheduleEntry]
    /// shiftID → 班次定义索引（避免逐格查询）
    let shiftIndex: [UUID: ShiftDefinition]
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.footnote.monospacedDigit())
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : .primary)
                .frame(width: 22, height: 22)

            ForEach(visibleSlots) { slot in
                capsule(for: slot)
            }
            if entries.count > maxVisible {
                Text("+\(entries.count - maxVisible)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(frameBackground)
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    private var maxVisible: Int { 2 }

    private var visibleSlots: [ScheduleEntry] {
        Array(entries.prefix(maxVisible))
    }

    /// 框底色：有班次 → 首个班次的浅色变体；否则浅灰
    private var frameBackground: Color {
        guard let shift = firstShift else {
            return Color.gray.opacity(0.12)
        }
        return Color(paletteHex: shift.colorHex).opacity(0.30)
    }

    private var firstShift: ShiftDefinition? {
        entries.first?.shiftID.flatMap { shiftIndex[$0] }
    }

    @ViewBuilder
    private func capsule(for entry: ScheduleEntry) -> some View {
        if let shift = entry.shiftID.flatMap({ shiftIndex[$0] }) {
            // 简化：小色点 + 班次名纯文本，无长条底色
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(paletteHex: shift.colorHex))
                    .frame(width: 6, height: 6)
                Text(shift.name)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
        } else {
            // 班次已被删除的悬挂记录：灰色占位提示
            Text("—")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}
