import Foundation
import SwiftData

/// 班次定义模型（R03）。
/// 时间表示约定（共享约定 #4）：startMinutes/endMinutes 为距午夜的分钟数（Int，0...1439），
/// 不使用 DateComponents 存储时间点；endMinutes <= startMinutes 即跨午夜；
/// start=end=0 特殊约定为"全天休息"（休班），不算跨午夜、时长为 0。
@Model
final class ShiftDefinition {

    /// 唯一标识
    @Attribute(.unique) private(set) var id: UUID

    /// 班次名，如 "早班"
    var name: String

    /// 开始时刻，距午夜分钟数（0...1439），如 8*60=480
    var startMinutes: Int

    /// 结束时刻，距午夜分钟数（0...1439）；<= startMinutes 表示跨午夜；
    /// "24:00" 一律存 0；与 start 同为 0 时表示全天休息
    var endMinutes: Int

    /// 班次颜色，"#RRGGBB" 大写带 #（共享约定 #1）
    var colorHex: String

    /// 智能识别别名关键词，如 ["早", "早班", "白班", "D"]
    var keywords: [String]

    /// 展示排序值（越小越靠前）
    var sortOrder: Int

    /// 创建时间
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         startMinutes: Int,
         endMinutes: Int,
         colorHex: String = "#757575",
         keywords: [String] = [],
         sortOrder: Int = 0,
         createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.startMinutes = startMinutes.clampedToMinutesOfDay
        self.endMinutes = endMinutes.clampedToMinutesOfDay
        self.colorHex = Theme.normalizedHex(colorHex) ?? "#757575"
        self.keywords = keywords
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    // MARK: - 计算属性

    /// 跨午夜判定（唯一入口：DateUtils.crossesMidnight）
    var crossesMidnight: Bool {
        DateUtils.crossesMidnight(startMinutes: startMinutes, endMinutes: endMinutes)
    }

    /// 是否为全天休息班（start=end=0 约定）
    var isRestShift: Bool {
        startMinutes == 0 && endMinutes == 0
    }

    /// 班次时长分钟数；休息班为 0
    var durationMinutes: Int {
        if isRestShift { return 0 }
        if crossesMidnight { return (1440 - startMinutes) + endMinutes }
        return max(0, endMinutes - startMinutes)
    }

    /// 展示用时间段文本："08:00-16:00"；跨午夜且结束存 0 时展示 "16:00-24:00"；休息展示 "休息"
    var timeRangeText: String {
        if isRestShift { return "休息" }
        let endText: String
        if crossesMidnight && endMinutes == 0 {
            endText = "24:00"
        } else {
            endText = endMinutes.timeString
        }
        return "\(startMinutes.timeString)-\(endText)"
    }

    // MARK: - 具体时刻换算

    /// 该班次在归属日的开始时刻
    func startDate(on attributedDay: Date, calendar: Calendar = .current) -> Date {
        DateUtils.date(day: attributedDay, minutesAfterMidnight: startMinutes, calendar: calendar)
    }

    /// 该班次在归属日的结束时刻（跨午夜自动落到次日）
    func endDate(on attributedDay: Date, calendar: Calendar = .current) -> Date {
        startDate(on: attributedDay, calendar: calendar)
            .addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    /// 该班次在归属日的时间区间（类图接口 interval(on:)）
    func interval(on date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = startDate(on: date, calendar: calendar)
        let duration = TimeInterval(max(durationMinutes, 0) * 60)
        return DateInterval(start: start, duration: duration)
    }

    // MARK: - 内置默认班次（共享约定：早 08-16 / 中 16-24 / 夜 00-08 / 休）

    /// 首版内置四个默认班次（仅在空库播种时插入，见 ContainerFactory.seedDefaultDataIfNeeded）
    static func defaultLibrary() -> [ShiftDefinition] {
        [
            ShiftDefinition(name: "早班",
                            startMinutes: 8 * 60,
                            endMinutes: 16 * 60,
                            colorHex: "#FDD835",
                            keywords: ["早", "早班", "白班", "白", "D"],
                            sortOrder: 0),
            ShiftDefinition(name: "中班",
                            startMinutes: 16 * 60,
                            endMinutes: 0,          // 24:00 存 0 → 跨午夜
                            colorHex: "#FB8C00",
                            keywords: ["中", "中班", "二班", "M"],
                            sortOrder: 1),
            ShiftDefinition(name: "夜班",
                            startMinutes: 0,
                            endMinutes: 8 * 60,
                            colorHex: "#3949AB",
                            keywords: ["夜", "夜班", "晚班", "晚", "大夜", "N"],
                            sortOrder: 2),
            ShiftDefinition(name: "休",
                            startMinutes: 0,
                            endMinutes: 0,          // 0-0 = 全天休息
                            colorHex: "#757575",
                            keywords: ["休", "休息", "休班", "休假", "OFF", "O"],
                            sortOrder: 3)
        ]
    }
}
