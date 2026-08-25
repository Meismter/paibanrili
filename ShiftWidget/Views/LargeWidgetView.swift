import SwiftUI

/// 大尺寸（systemLarge）：未来 30 天紧凑日历网格。
/// 每行 7 列对齐星期（首行按今天所在星期留空位），单元格 = 日期数字 + 班次彩色小色块；
/// 无班次/休息显示浅灰点；字号 minimumScaleFactor 自适应保证不截断。
struct LargeWidgetView: View {

    let date: Date
    let schedules: [DaySchedule]

    private let calendar = Calendar.current
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("未来 30 天")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if schedules.isEmpty {
                Spacer()
                Text("暂无排班\n打开 App 添加吧")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                weekdayHeader
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        if let cell {
                            cellView(cell)
                        } else {
                            Color.clear
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Private

    /// 日历式对齐的单元格序列：今天所在星期之前的空位 + 未来 30 天
    private var cells: [DayCell?] {
        let today = calendar.startOfDay(for: date)
        // 周一开始布局：weekday 1=周日→6 … 6=周五→4，7=周六→5；周一=0
        let leading = (calendar.component(.weekday, from: today) + 5) % 7
        let map = Dictionary(uniqueKeysWithValues: schedules.map {
            (calendar.startOfDay(for: $0.day).timeIntervalSince1970, $0.slots)
        })
        var result: [DayCell?] = Array(repeating: nil, count: leading)
        for offset in 0..<SharedConstants.widgetLargeDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            result.append(DayCell(day: day, slots: map[day.timeIntervalSince1970] ?? []))
        }
        return result
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cellView(_ cell: DayCell) -> some View {
        VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: cell.day))")
                .font(.caption2.monospacedDigit())
                .fontWeight(isToday(cell.day) ? .bold : .regular)
                .foregroundStyle(isToday(cell.day) ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            slotBlock(cell.slots)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
    }

    /// 班次彩色小色块；无班次/休息 → 浅灰圆点
    @ViewBuilder
    private func slotBlock(_ slots: [ShiftSlot]) -> some View {
        if let slot = slots.first(where: { !$0.isRest }) ?? slots.first {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(paletteHex: slot.colorHex))
                .frame(height: 5)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 3)
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 5, height: 5)
        }
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }

    /// 单日网格单元
    private struct DayCell {
        let day: Date
        let slots: [ShiftSlot]
    }
}
