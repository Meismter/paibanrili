import SwiftUI

/// 日期格（R01 / 批次 A）：日期数字 + 彩色班次胶囊（最多展示 2 个 + "+N"）。
/// 批次 A：每格加浅底色圆角框；有班次时框底色随首个班次颜色变化（浅色变体）；
/// 今天以 accent 描边 + 浅色圆点高亮。
/// R15 迭代：有备注的日期右上角按艾森豪威尔象限显示至多 4 个迷你色块标签
/// （红=重要且紧急 / 蓝=重要不紧急 / 橙=紧急不重要 / 灰=不重要不紧急），
/// 尺寸控制在格内，不挤占相邻日期。
struct DayCellView: View {

    let day: Date
    let entries: [ScheduleEntry]
    /// shiftID → 班次定义索引（避免逐格查询）
    let shiftIndex: [UUID: ShiftDefinition]
    let isToday: Bool
    /// 该日有内容的备注象限（空数组 = 无备注）；最多 4 个，按象限顺序排列
    var noteQuadrants: [NoteQuadrant] = []

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
        .overlay(alignment: .topTrailing) {
            if !noteQuadrants.isEmpty {
                quadrantTags
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    /// 象限迷你色块标签：横向排列，最多 4 个，紧凑不溢出
    private var quadrantTags: some View {
        HStack(spacing: 1.5) {
            ForEach(noteQuadrants.prefix(4), id: \.rawValue) { quadrant in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(paletteHex: quadrant.colorHex))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(quadrant.title)
            }
        }
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.background.opacity(0.85))
        )
        .padding(.trailing, 3)
        .padding(.top, 3)
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
