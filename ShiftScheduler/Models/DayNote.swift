import Foundation
import SwiftData

/// 日备注的艾森豪威尔四象限枚举
enum NoteQuadrant: Int, CaseIterable {
    case importantUrgent = 0        // 重要且紧急
    case importantNotUrgent = 1     // 重要不紧急
    case notImportantUrgent = 2     // 紧急不重要
    case neither = 3                // 不重要不紧急

    var title: String {
        switch self {
        case .importantUrgent: return "重要且紧急"
        case .importantNotUrgent: return "重要不紧急"
        case .notImportantUrgent: return "紧急不重要"
        case .neither: return "不重要不紧急"
        }
    }

    var strategy: String {
        switch self {
        case .importantUrgent: return "立即做"
        case .importantNotUrgent: return "计划做"
        case .notImportantUrgent: return "委托做"
        case .neither: return "减少做"
        }
    }

    /// 象限主题色（hex，供 Color(paletteHex:) 复用既有调色板解析）
    var colorHex: String {
        switch self {
        case .importantUrgent: return "#E74C3C"   // 红：立刻处理
        case .importantNotUrgent: return "#3498DB" // 蓝：从容规划
        case .notImportantUrgent: return "#F39C12" // 橙：转交他人
        case .neither: return "#95A5A6"            // 灰：尽量精简
        }
    }

    var iconName: String {
        switch self {
        case .importantUrgent: return "flame.fill"
        case .importantNotUrgent: return "calendar.badge.clock"
        case .notImportantUrgent: return "person.2.fill"
        case .neither: return "leaf.fill"
        }
    }
}

/// 日期备注模型（R15）：每个自然日一份四象限备注。
///
/// 约定：
/// - dayKey 为该自然日 "yyyy-MM-dd"，唯一索引，一天最多一份备注；
/// - 四个象限各自存一组短文本条目；与排班（ScheduleEntry.note）互不影响，
///   备注独立于班次存在——没有排班的日期也可以写备注。
@Model
final class DayNote {

    @Attribute(.unique) private(set) var id: UUID

    /// 归属日键："yyyy-MM-dd"（本地时区）
    @Attribute(.unique) var dayKey: String

    /// 第一象限：重要且紧急
    var importantUrgent: [String] = []
    /// 第二象限：重要不紧急
    var importantNotUrgent: [String] = []
    /// 第三象限：紧急不重要
    var notImportantUrgent: [String] = []
    /// 第四象限：不重要不紧急
    var neither: [String] = []

    var createdAt: Date
    var updatedAt: Date

    init(dayKey: String,
         id: UUID = UUID(),
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.dayKey = dayKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - 象限读写

    /// 读取某象限条目
    func items(for quadrant: NoteQuadrant) -> [String] {
        switch quadrant {
        case .importantUrgent: return importantUrgent
        case .importantNotUrgent: return importantNotUrgent
        case .notImportantUrgent: return notImportantUrgent
        case .neither: return neither
        }
    }

    /// 写回某象限条目（整体替换）
    func setItems(_ items: [String], for quadrant: NoteQuadrant) {
        switch quadrant {
        case .importantUrgent: importantUrgent = items
        case .importantNotUrgent: importantNotUrgent = items
        case .notImportantUrgent: notImportantUrgent = items
        case .neither: neither = items
        }
        updatedAt = .now
    }

    /// 是否完全没有内容
    var isEmpty: Bool {
        NoteQuadrant.allCases.allSatisfy { items(for: $0).isEmpty }
    }

    // MARK: - 工具

    /// 任意日期 → 归属日键 "yyyy-MM-dd"
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 2026,
                      components.month ?? 1,
                      components.day ?? 1)
    }
}
