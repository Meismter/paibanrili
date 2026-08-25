import SwiftUI

/// 日期格（R01）：日期数字 + 彩色班次胶囊（最多展示 2 个），今天高亮圈。
struct DayCellView: View {

    let day: Date
    let entries: [ScheduleEntry]
    /// shiftID → 班次定义索引（避免逐格查询）
    let shiftIndex: [UUID: ShiftDefinition]
    let isToday: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.footnote.monospacedDigit())
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 22, height: 22)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    }
                }

            ForEach(visibleSlots) { slot in
                capsule(for: slot)
            }
            if entries.count > maxVisible {
                Text("+\(entries.count - maxVisible)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private var maxVisible: Int { 2 }

    private var visibleSlots: [ScheduleEntry] {
        Array(entries.prefix(maxVisible))
    }

    @ViewBuilder
    private func capsule(for entry: ScheduleEntry) -> some View {
        if let shift = entry.shiftID.flatMap({ shiftIndex[$0] }) {
            HStack(spacing: 2) {
                Circle()
                    .fill(Color(paletteHex: shift.colorHex))
                    .frame(width: 6, height: 6)
                Text(shift.name)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .frame(maxWidth: .infinity)
            .background(
                Color(paletteHex: shift.colorHex).opacity(0.18),
                in: Capsule()
            )
        } else {
            // 班次已被删除的悬挂记录：灰色占位提示
            Text("—")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}
