import Foundation

// MARK: - Widget 侧只读数据模型
//
// 实现说明（主理人裁决①）：主 App 每次写库后经 WidgetRefresher 将排班快照
// 序列化为 JSON 写入 App Group 容器（widget_snapshot.json），本加载器在扩展
// 进程内只读取该文件，不在 Widget 侧打开 SwiftData 存储。
// （曾并行实现过"镜像 @Model 直读共享库"方案，因与裁决方案冲突且镜像模型
// 需与主 target 字段严格同步，已统一收敛到本 JSON 快照方案。）

/// 单条班次槽位快照
public struct ShiftSlot: Codable, Hashable, Identifiable, Sendable {
    /// 来源 ScheduleEntry.id（用于去重与刷新判断）
    public let entryID: UUID
    /// 成员名（首版多为"我自己"）
    public let memberName: String
    /// 班次名称，如 "早班"
    public let shiftName: String
    /// 班次颜色，"#RRGGBB" 大写带#
    public let colorHex: String
    /// 距午夜分钟数（0...1439）
    public let startMinutes: Int
    /// 距午夜分钟数；<= startMinutes 表示跨午夜；0-0 表示休息
    public let endMinutes: Int

    public init(entryID: UUID,
                memberName: String,
                shiftName: String,
                colorHex: String,
                startMinutes: Int,
                endMinutes: Int) {
        self.entryID = entryID
        self.memberName = memberName
        self.shiftName = shiftName
        self.colorHex = colorHex
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    /// 是否为全天休息（start=end=0 约定为休）
    public var isRest: Bool { startMinutes == 0 && endMinutes == 0 }

    /// 时长分钟数（跨午夜自动折算；休息为 0）
    public var durationMinutes: Int {
        if isRest { return 0 }
        return endMinutes <= startMinutes ? (1440 - startMinutes + endMinutes) : (endMinutes - startMinutes)
    }

    /// Identifiable 协议要求：与 ScheduleEntry.id 对齐用于去重与刷新判断
    public var id: UUID { entryID }
}

/// 某归属日（当日 12:00 本地）的班次列表
public struct DaySchedule: Codable, Hashable, Identifiable, Sendable {
    /// 归属日，存储为该自然日 12:00 本地时间（共享约定 #2）
    public let day: Date
    public let slots: [ShiftSlot]

    public init(day: Date, slots: [ShiftSlot]) {
        self.day = day
        self.slots = slots
    }

    public var id: Date { day }
}

/// Widget 数据加载器 —— 经 App Group 只读加载未来 N 天班次。
public enum WidgetDataLoader {

    /// App Group 容器中的快照文件 URL
    public static func snapshotURL() -> URL? {
        SharedConstants.sharedContainerURL()?
            .appendingPathComponent(SharedConstants.widgetSnapshotFileName)
    }

    /// 只读加载自参考日起未来 N 天的班次安排。
    /// - Parameters:
    ///   - days: 加载天数（默认 31：今日 + 未来 30 天，覆盖 Large 小组件展示上限）
    ///   - reference: 参考时刻，默认当前时间
    ///   - calendar: 用于"自然日"判定的日历，默认 `.current`
    /// - Returns: 按日期升序、每日内按开始分钟升序的日程数组；无数据/读取失败返回空数组
    public static func loadUpcoming(days: Int = SharedConstants.widgetUpcomingDays,
                                    from reference: Date = .now,
                                    calendar: Calendar = .current) -> [DaySchedule] {
        guard days > 0 else { return [] }
        guard let url = snapshotURL() else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let all = try JSONDecoder().decode([DaySchedule].self, from: data)
            let today = calendar.startOfDay(for: reference)
            let upcoming = all
                .filter { calendar.startOfDay(for: $0.day) >= today }
                .sorted { $0.day < $1.day }
                .prefix(days)
                .map { schedule in
                    DaySchedule(day: schedule.day,
                                slots: schedule.slots.sorted { $0.startMinutes < $1.startMinutes })
                }
            return Array(upcoming)
        } catch {
            // 快照缺失或损坏时静默降级为空数据，Widget 展示占位态
            return []
        }
    }

    /// 主 App 专用：将最新排班快照写入 App Group 容器（建议全量覆盖写）。
    /// 调用方：WidgetRefresher.refreshAfterWrite(context:)；
    /// 写入后必须调用 `WidgetCenter.shared.reloadAllTimelines()`（共享约定 #9）。
    @discardableResult
    public static func writeSnapshot(_ schedules: [DaySchedule]) -> Bool {
        guard let url = snapshotURL() else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(schedules)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
