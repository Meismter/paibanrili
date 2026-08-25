import Foundation

/// SharedKit 共享常量 —— 主 App 与 Widget 扩展两个 target 均编译此文件。
/// 跨 target 约定（架构文档 §8）统一收敛于此，禁止在业务代码中硬编码。
public enum SharedConstants {

    // MARK: - App Group

    /// App Group 标识：主 App 与 Widget 通过它共享容器
    public static let appGroupID = "group.shiftscheduler.shared"

    /// 返回 App Group 容器 URL（未配置权限时返回 nil）
    public static func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    // MARK: - 小组件覆盖天数

    /// 时间线/加载器覆盖天数：今日 + 未来 30 天（= widgetLargeDays + 1 天余量）
    public static let widgetUpcomingDays = 31

    /// 快照滚动窗口天数（buildSnapshot 上限，> widgetUpcomingDays 防时钟漂移缺数据）
    public static let widgetSnapshotDays = 32

    /// Medium 小组件展示天数
    public static let widgetMediumDays = 7

    /// Large 小组件展示天数
    public static let widgetLargeDays = 30

    // MARK: - 日历事件标识约定

    /// EKEvent.notes 的去重查询前缀："​[SS:"
    public static let eventNotesPrefix = "[SS:"

    /// 事件标题中的分隔符："班次名 · HH:mm-HH:mm"
    public static let eventTitleSeparator = " · "

    /// Widget 快照文件名（主 App 写、Widget 读，经 App Group 共享）
    public static let widgetSnapshotFileName = "widget_snapshot.json"

    /// 首版默认成员名（裁决 #1：未匹配到成员的条目归入"我自己"）
    public static let selfMemberName = "我自己"

    /// 为指定排班条目生成稳定标识（写入 notes 首行）
    /// - Parameter entryID: ScheduleEntry.id
    /// - Returns: 形如 "[SS:<uuidString>]" 的标识串
    public static func eventTag(for entryID: UUID) -> String {
        "[SS:\(entryID.uuidString)]"
    }

    /// 判断一段 notes 是否携带本应用的排班标识
    public static func isAppTagged(notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.contains(eventNotesPrefix)
    }

    /// 按共享约定构造事件标题："班次名 · HH:mm-HH:mm"
    /// 跨午夜结束时间若为 0（即 24:00），展示为 "24:00"
    public static func eventTitle(shiftName: String, startMinutes: Int, endMinutes: Int) -> String {
        "\(shiftName)\(eventTitleSeparator)\(hhmm(startMinutes))-\(hhmm(endMinutes, endOfDayAs24: true))"
    }

    // MARK: - Private

    /// 分钟数 → "HH:mm"（SharedKit 内部独立实现，避免依赖主 target 的 DateUtils/Extensions）
    private static func hhmm(_ minutes: Int, endOfDayAs24: Bool = false) -> String {
        let clamped = max(0, min(1439, minutes))
        if endOfDayAs24 && clamped == 0 { return "24:00" }
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
