import SwiftUI

/// 中尺寸（systemMedium）：未来 7 天紧凑一览，每列 = 星期 + 日期数字 + 班次色点。
/// 无班次/休息日显示浅灰点；字号自适应保证不截断。
struct MediumWidgetView: View {

    let date: Date
    let schedules: [DaySchedule]

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("未来 7 天")
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
                HStack(spacing: 3) {
                    ForEach(Array(dayItems.enumerated()), id: \.offset) { index, item in
                        dayCell(item, isToday: index == 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Private

    /// 自参考日起未来 7 个自然日（含首日）；快照中缺失的天以空槽位呈现（浅灰点）
    private var dayItems: [(day: Date, slots: [ShiftSlot])] {
        let today = calendar.startOfDay(for: date)
        let map = Dictionary(uniqueKeysWithValues: schedules.map {
            (calendar.startOfDay(for: $0.day).timeIntervalSince1970, $0.slots)
        })
        return (0..<SharedConstants.widgetMediumDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return (day, map[day.timeIntervalSince1970] ?? [])
        }
    }

    private func dayCell(_ item: (day: Date, slots: [ShiftSlot]), isToday: Bool) -> some View {
        VStack(spacing: 3) {
            Text(weekdaySymbol(for: item.day))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(calendar.component(.day, from: item.day))")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(isToday ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            slotDots(item.slots)
                .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }

    /// 有班次 → 彩色小圆点（至多 3 个）；无班次/休息 → 浅灰点
    @ViewBuilder
    private func slotDots(_ slots: [ShiftSlot]) -> some View {
        let colors = slots.filter { !$0.isRest }
            .prefix(3)
            .map { Color(paletteHex: $0.colorHex) }
        if colors.isEmpty {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 6, height: 6)
                }
            }
        }
    }

    /// 星期单字（日/一/二/…/六），Calendar.weekday 1=周日 … 7=周六
    private func weekdaySymbol(for day: Date) -> String {
        let index = calendar.component(.weekday, from: day)
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return symbols[(index - 1) % 7]
    }
}
