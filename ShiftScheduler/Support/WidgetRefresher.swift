import Foundation
import SwiftData
import WidgetKit

/// Widget 同步刷新器 —— 所有排班写库点的统一收口。
///
/// 共享约定 #9 / 主理人裁决①：
/// 每次成功保存排班数据后，必须重建 App Group 内的 JSON 快照
/// （WidgetDataLoader.writeSnapshot），并调用
/// WidgetCenter.reloadAllTimelines() 即时刷新桌面小组件。
@MainActor
enum WidgetRefresher {

    /// 在写库（含 context.save()）之后调用
    static func refreshAfterWrite(context: ModelContext) {
        let schedules = Self.buildSnapshot(context: context)
        WidgetDataLoader.writeSnapshot(schedules)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 全量重建快照：所有成员在滚动窗口内的条目按归属日分桶
    /// （窗口 = 今日起未来 widgetSnapshotDays 天，保证 ≥31 天覆盖并控制快照体积）
    static func buildSnapshot(context: ModelContext) -> [DaySchedule] {
        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: .now)
        let windowEnd = calendar.date(byAdding: .day,
                                      value: SharedConstants.widgetSnapshotDays,
                                      to: windowStart)
            ?? windowStart.addingTimeInterval(Double(SharedConstants.widgetSnapshotDays) * 86400)

        let entries = (try? context.fetch(
            FetchDescriptor<ScheduleEntry>(sortBy: [SortDescriptor(\.attributedDate)])
        ))?.filter { $0.attributedDate >= windowStart && $0.attributedDate < windowEnd } ?? []
        guard !entries.isEmpty else { return [] }

        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        let memberNames = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) })
        let shifts = (try? context.fetch(FetchDescriptor<ShiftDefinition>())) ?? []
        let shiftIndex = Dictionary(uniqueKeysWithValues: shifts.map { ($0.id, $0) })

        // 按归属日分桶
        var buckets: [TimeInterval: (day: Date, slots: [ShiftSlot])] = [:]
        for entry in entries {
            let shift = entry.shiftID.flatMap { shiftIndex[$0] }
            let slot = ShiftSlot(entryID: entry.id,
                                 memberName: memberNames[entry.memberID] ?? SharedConstants.selfMemberName,
                                 shiftName: shift?.name ?? "排班",
                                 colorHex: shift?.colorHex ?? "#757575",
                                 startMinutes: shift?.startMinutes ?? 0,
                                 endMinutes: shift?.endMinutes ?? 0)
            let key = entry.attributedDate.timeIntervalSince1970
            if var bucket = buckets[key] {
                bucket.slots.append(slot)
                buckets[key] = bucket
            } else {
                buckets[key] = (entry.attributedDate, [slot])
            }
        }

        return buckets.values
            .map { DaySchedule(day: $0.day, slots: $0.slots.sorted { $0.startMinutes < $1.startMinutes }) }
            .sorted { $0.day < $1.day }
    }
}
