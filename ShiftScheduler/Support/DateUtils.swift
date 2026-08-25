import Foundation

/// 日期/时间工具 —— 跨午夜判定、归属日期、月历网格的全 App 唯一实现入口
/// （架构共享知识 §8.2/§8.4）。合并了两位工程师批次中的 API 面：
/// - `noon(of:calendar:)` / `crossesMidnight(startMinutes:endMinutes:)` /
///   `timeString(minutes:)` / `date(day:minutesAfterMidnight:)` /
///   `monthGrid(firstWeekdayOfWeek:) -> [Date?]`（批次1-3 业务代码与测试依赖）
/// - `attributedDate(from:)` / `startOfDay(of:)` / `interval(startMinutes:endMinutes:on:)` /
///   `monthGrid(firstWeekday:) -> MonthGrid`（Extensions.swift 等依赖）
enum DateUtils {

    /// 归属日期统一存储的小时（12:00 本地，规避夏令时/日界）
    static let attributedDateHour = 12

    // MARK: - 归属日期（共享约定 #2）

    /// 将任意时刻归一化为"其所在自然日的 12:00 本地时间"。
    /// ScheduleEntry.attributedDate 一律经此存储。
    static func noon(of day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: attributedDateHour, minute: 0, second: 0, of: start) ?? start
    }

    /// 由班次"开始时刻"推导归属日（= 开始时刻所在自然日，存 12:00）。
    static func attributedDate(for startDate: Date, calendar: Calendar = .current) -> Date {
        noon(of: startDate, calendar: calendar)
    }

    /// 把任意时刻的日期规范化为该自然日 12:00 本地时间（归属日期统一存储格式）。
    static func attributedDate(from day: Date) -> Date {
        noon(of: day)
    }

    /// 从归属日期取回所在自然日的当天 0 点（用于月历落格比较）。
    static func startOfDay(of date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    // MARK: - 分钟数换算（共享约定 #4）

    /// 在某归属日内构造"距午夜 minutesAfterMidnight 分钟"的具体时刻。
    static func date(day attributedDay: Date,
                     minutesAfterMidnight minutes: Int,
                     calendar: Calendar = .current) -> Date {
        let clamped = max(0, min(1439, minutes))
        let start = calendar.startOfDay(for: attributedDay)
        return calendar.date(bySettingHour: clamped / 60,
                             minute: clamped % 60,
                             second: 0,
                             of: start) ?? start
    }

    /// 分钟数 → "HH:mm"（展示层统一入口为 Int.timeString，内部委托本方法）
    static func timeString(minutes: Int) -> String {
        let clamped = max(0, min(1439, minutes))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    // MARK: - 跨午夜判定（唯一入口）

    /// 共享约定 #2：endMinutes <= startMinutes 即视为跨午夜（如 22:00–06:00）。
    /// 特例：start=end=0 约定为"全天休息"（休班），不算跨午夜、时长为 0。
    static func crossesMidnight(startMinutes: Int, endMinutes: Int) -> Bool {
        if startMinutes == 0 && endMinutes == 0 { return false }
        return endMinutes <= startMinutes
    }

    /// 兼容别名（参数标签 start/end 版本，语义同上；不含 0-0 特判）。
    static func crossesMidnight(start: Int, end: Int) -> Bool {
        end <= start
    }

    /// 班次在给定"归属日"上的实际起止区间（元组版）。
    /// 归属日期 = 班次开始时刻所在自然日；跨午夜班次的结束时刻自动 +1 天。
    static func interval(startMinutes: Int,
                         endMinutes: Int,
                         on day: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let startDate = calendar.date(byAdding: .minute, value: startMinutes, to: dayStart) ?? day
        let rawEnd = calendar.date(byAdding: .minute, value: endMinutes, to: dayStart) ?? day
        let endDate = crossesMidnight(start: startMinutes, end: endMinutes)
            ? calendar.date(byAdding: .day, value: 1, to: rawEnd) ?? rawEnd
            : rawEnd
        return (startDate, endDate)
    }

    // MARK: - 月历网格（[Date?] 版：正午表示，nil 为补位）

    /// 生成年某月的月历网格（含前后补位），每行 7 格。
    /// - Parameter firstWeekdayOfWeek: 每周起始日，1=周日 ... 7=周六（周一为 2）
    static func monthGrid(year: Int,
                          month: Int,
                          firstWeekdayOfWeek: Int,
                          calendar: Calendar = .current) -> [Date?] {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        let daysInMonth = range.count
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekdayOfFirst - firstWeekdayOfWeek + 7) % 7

        var cells: [Date?] = []
        cells.reserveCapacity(leadingBlanks + daysInMonth + 7)
        cells.append(contentsOf: repeatElement(nil, count: leadingBlanks))
        for dayOffset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth) {
                cells.append(noon(of: date, calendar: calendar))
            } else {
                cells.append(nil)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    // MARK: - 月历网格（MonthGrid 结构版）

    struct MonthGrid {
        var year: Int
        var month: Int                    // 1..12
        /// 网格单元：nil 表示前导/尾随补位空白
        var cells: [Date?]
        /// 表头星期序（按周起始日偏移后），元素为 Calendar.weekday 值（1=周日…7=周六）
        var weekdayHeaders: [Int]
    }

    /// 结构版月历网格（默认周一起始）。
    static func monthGrid(year: Int, month: Int, firstWeekday: Int = 2) -> MonthGrid {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components),
              let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else {
            return MonthGrid(year: year, month: month, cells: [], weekdayHeaders: [])
        }
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekdayOfFirst - firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in 1...daysInMonth {
            var dc = DateComponents()
            dc.year = year
            dc.month = month
            dc.day = day
            if let date = calendar.date(from: dc) {
                cells.append(noon(of: date))
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        // 表头：从周起始日开始连续 7 个 weekday 序号
        let headers = (0..<7).map { index -> Int in
            let weekday = firstWeekday + index
            return weekday > 7 ? weekday - 7 : weekday
        }
        return MonthGrid(year: year, month: month, cells: cells, weekdayHeaders: headers)
    }

    /// 中文星期表头文本（1=周日…7=周六）。
    static func chineseWeekday(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        default: return ""
        }
    }

    /// 按每周起始日旋转的短星期标签，如周一开头 → ["一","二","三","四","五","六","日"]
    static func weekdaySymbols(firstWeekdayOfWeek: Int,
                               calendar: Calendar = .current) -> [String] {
        let base = calendar.veryShortWeekdaySymbols // ["日","一","二",...]
        guard (1...7).contains(firstWeekdayOfWeek), base.count == 7 else { return base }
        let offset = firstWeekdayOfWeek - 1
        return Array(base[offset...] + base[..<offset])
    }

    /// "2026年3月" 格式月份标题。
    static func monthTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }

    /// 当前月份的 (year, month)。
    static func currentYearMonth(now: Date = Date()) -> (Int, Int) {
        let calendar = Calendar.current
        return (calendar.component(.year, from: now), calendar.component(.month, from: now))
    }
}
