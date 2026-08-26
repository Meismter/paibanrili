import SwiftUI

/// 日期格（R01 / 批次 A）：日期数字 + 彩色班次胶囊（最多展示 2 个 + "+N"）。
/// 批次 A：每格加浅底色圆角框；有班次时框底色随首个班次颜色变化（浅色变体）；
/// 今天以 accent 描边 + 浅色圆点高亮。
/// R15 迭代：有备注的日期，右上角边缘竖排至多 4 个象限小圆点
/// （红=重要且紧急 / 蓝=重要不紧急 / 橙=紧急不重要 / 灰=不重要不紧急），
/// 样式仿上一版小圆圈记号笔，沿右边缘向下排列，不挤占相邻日期。
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
                quadrantDots
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    /// 右上角边缘的象限小圆点：竖排、最多 4 个、仿小圆圈记号笔
    private var quadrantDots: some View {
        VStack(spacing: 2.5) {
            ForEach(noteQuadrants.prefix(4), id: \.rawValue) { quadrant in
                Circle()
                    .fill(Color(paletteHex: quadrant.colorHex))
                    .frame(width: 6.5, height: 6.5)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 0.6, y: 0.5)
                    .accessibilityLabel(quadrant.title)
            }
        }
        .padding(.trailing, 2.5)
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
