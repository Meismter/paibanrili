import Foundation
import WidgetKit

/// Widget 时间线条目：某时刻的排班快照（只读数据）。
struct WidgetEntry: TimelineEntry {
    /// 该条目的展示/刷新时刻
    let date: Date
    /// 自该时刻起未来若干天的班次快照（来自 App Group JSON）
    let schedules: [DaySchedule]
}

extension WidgetEntry {
    static let empty = WidgetEntry(date: .now, schedules: [])
}
