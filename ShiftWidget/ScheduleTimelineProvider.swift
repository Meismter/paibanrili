import Foundation
import WidgetKit

/// 时间线提供器（R12，裁决 #6）：
/// 刷新点 = 当前时刻 + 当日剩余各班次开始时刻 + 每日 0 点；
/// 条目策略 .atEnd（最后一条展示完即请求新时间线）。
/// 数据源：WidgetDataLoader 经 App Group 只读 JSON 快照。
struct ScheduleTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        sampleEntry()
    }

    /// 首次添加小组件时的过渡快照
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(loadEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()

        var refreshDates: [Date] = [now]

        // 1) 当日剩余班次开始时刻（裁决 #6：班次切换点刷新）
        if let today = WidgetDataLoader.loadUpcoming(days: 1, from: now).first {
            for slot in today.slots {
                if slot.isRest { continue }
                let startDate = calendar.date(bySettingHour: slot.startMinutes / 60,
                                              minute: slot.startMinutes % 60,
                                              second: 0,
                                              of: now)
                if let startDate, startDate > now {
                    refreshDates.append(startDate)
                }
            }
        }

        // 2) 明日 0 点（跨日刷新）
        if let nextMidnight = calendar.nextDate(after: now,
                                                matching: DateComponents(hour: 0, minute: 0),
                                                matchingPolicy: .nextTime) {
            refreshDates.append(nextMidnight)
        }

        // 去重排序并生成条目；每个条目的 schedules 以其自身时刻为基准加载
        let entries = refreshDates
            .sorted()
            .map { loadEntry(at: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    // MARK: - Private

    private func loadEntry(at date: Date) -> WidgetEntry {
        // 长跨度（30 天）下仍按 31 天加载；刷新点保持"当日班次切换点 + 明日 0 点"，
        // 配合 .atEnd 策略，每条时间线耗尽后按新基准日重新取数，30 天数据随之滚动。
        WidgetEntry(date: date,
                    schedules: WidgetDataLoader.loadUpcoming(days: SharedConstants.widgetUpcomingDays,
                                                             from: date))
    }

    /// 无数据时的示例占位（首次渲染/预览用）
    private func sampleEntry() -> WidgetEntry {
        let demoSlot = ShiftSlot(entryID: UUID(),
                                 memberName: SharedConstants.selfMemberName,
                                 shiftName: "早班",
                                 colorHex: "#FDD835",
                                 startMinutes: 8 * 60,
                                 endMinutes: 16 * 60)
        return WidgetEntry(date: .now,
                           schedules: [DaySchedule(day: Date(), slots: [demoSlot])])
    }
}
