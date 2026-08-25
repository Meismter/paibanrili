import Foundation

/// 日期识别命中
struct DateHit: Equatable, Sendable {
    /// 解析出的日期（正午表示，规避日界）
    let date: Date
    /// 命中的原文片段，如 "3月5日"
    let rawText: String
    /// 命中范围（NSString 坐标系，供引擎切分日期后片段）
    let nsRange: NSRange
}

/// 中文日期识别器（R06）。
///
/// 支持形态：
/// - 绝对日期：2026年3月5日 / 3月5号 / 2026-03-05 / 03-05 / 3/5
/// - 相对日期（基于 baseDate）：今天/今日、明天/次日、后天、大后天、周X/星期X/礼拜X、下周X
///
/// 无年份的绝对日期按"距离 baseDate 最近"推断年份（覆盖跨年边界：
/// 如 12 月排班表里出现 "1月5日" 推断为次年）。
/// 每个正则模式绑定独立的解析器，避免不同格式的捕获组语义混淆。
enum DateRecognizer {

    // MARK: - 主入口

    /// 在一行文本中查找全部日期（按出现位置升序、同日去重）
    static func findDates(in line: String,
                          baseDate: Date = .now,
                          calendar: Calendar = .current) -> [DateHit] {
        let nsLine = line as NSString
        var hits: [(hit: DateHit, location: Int)] = []
        var seenDays: Set<TimeInterval> = []

        for spec in Self.patternSpecs {
            for match in spec.regex.matches(in: line,
                                            range: NSRange(location: 0, length: nsLine.length)) {
                let rawText = nsLine.substring(with: match.range)
                guard let date = resolve(spec.kind, match, nsLine, rawText,
                                         baseDate: baseDate, calendar: calendar),
                      seenDays.insert(calendar.startOfDay(for: date).timeIntervalSince1970).inserted
                else { continue }
                hits.append((DateHit(date: DateUtils.noon(of: date, calendar: calendar),
                                     rawText: rawText,
                                     nsRange: match.range),
                             match.range.location))
            }
        }
        return hits.sorted { $0.location < $1.location }.map(\.hit)
    }

    // MARK: - 模式规格

    private enum Kind {
        case optionalYear       // [YYYY年]M月D[日号]
        case fullYMD            // YYYY-MM-DD / YYYY.M.D / YYYY/M/D
        case shortMonthDay      // M-D / M/D（防时间段误伤）
        case weekday            // [下|本|这]周X / 星期X / 礼拜X
        case relative           // 今天/明天/后天/大后天…
    }

    private struct PatternSpec {
        let kind: Kind
        let regex: NSRegularExpression
    }

    private static let patternSpecs: [PatternSpec] = [
        PatternSpec(kind: .optionalYear,
                    regex: try! NSRegularExpression(pattern: "(?:(\\d{4})\\s*年)?\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*[日号]")),
        PatternSpec(kind: .fullYMD,
                    regex: try! NSRegularExpression(pattern: "(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})")),
        // 短格式：前后不能紧邻数字或冒号（避开 "08:00-16:00" 时间段误伤）
        PatternSpec(kind: .shortMonthDay,
                    regex: try! NSRegularExpression(pattern: "(?<![\\d:])(\\d{1,2})[-/](\\d{1,2})(?![\\d:])")),
        PatternSpec(kind: .weekday,
                    regex: try! NSRegularExpression(pattern: "(下|本|这)?(?:周|星期|礼拜)([一二三四五六日天])")),
        PatternSpec(kind: .relative,
                    regex: try! NSRegularExpression(pattern: "(大后天|后天|明天|次日|今天|今日)"))
    ]

    // MARK: - 单匹配解析

    private static func resolve(_ kind: Kind,
                                _ match: NSTextCheckingResult,
                                _ nsLine: NSString,
                                _ rawText: String,
                                baseDate: Date,
                                calendar: Calendar) -> Date? {
        func intGroup(_ index: Int) -> Int? {
            guard index < match.numberOfRanges,
                  match.range(at: index).location != NSNotFound else { return nil }
            return Int(nsLine.substring(with: match.range(at: index)))
        }

        switch kind {
        case .optionalYear:
            guard let month = intGroup(2), let day = intGroup(3) else { return nil }
            // 年份组需 ≥100 才视为显式年份（防御性判定）
            let explicitYear = intGroup(1).flatMap { $0 >= 100 ? $0 : nil }
            return makeDate(explicitYear, month, day, baseDate: baseDate, calendar: calendar)

        case .fullYMD:
            guard let year = intGroup(1), let month = intGroup(2), let day = intGroup(3) else { return nil }
            return makeDate(year, month, day, baseDate: baseDate, calendar: calendar)

        case .shortMonthDay:
            guard let month = intGroup(1), let day = intGroup(2) else { return nil }
            return makeDate(nil, month, day, baseDate: baseDate, calendar: calendar)

        case .weekday:
            guard match.numberOfRanges >= 3,
                  match.range(at: 2).location != NSNotFound,
                  let char = nsLine.substring(with: match.range(at: 2)).first,
                  let targetWeekday = weekdayMap[char] else { return nil }
            // 前缀组（"下周"/"下"等）可选："周一" 无前缀时该组不参与匹配，
            // 直接取子串会抛 NSRangeException（QA 第 1 轮 #7）
            let prefix = match.range(at: 1).location != NSNotFound
                ? nsLine.substring(with: match.range(at: 1))
                : ""
            return weekdayDate(prefix: prefix,
                               targetWeekday: targetWeekday,
                               baseDate: baseDate, calendar: calendar)

        case .relative:
            switch rawText {
            case "今天", "今日":
                return baseDate
            case "明天", "次日":
                return calendar.date(byAdding: .day, value: 1, to: baseDate)
            case "后天":
                return calendar.date(byAdding: .day, value: 2, to: baseDate)
            case "大后天":
                return calendar.date(byAdding: .day, value: 3, to: baseDate)
            default:
                return nil
            }
        }
    }

    // MARK: - 构造与推断

    /// 由年月日构造日期；无显式年份时按"距 baseDate 最近"推断年份（跨年边界处理）
    private static func makeDate(_ explicitYear: Int?,
                                 _ month: Int,
                                 _ day: Int,
                                 baseDate: Date,
                                 calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let year = explicitYear {
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        let baseYear = calendar.component(.year, from: baseDate)
        var bestDate: Date?
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        for candidate in [baseYear - 1, baseYear, baseYear + 1] {
            guard let date = calendar.date(from: DateComponents(year: candidate,
                                                                month: month,
                                                                day: day)) else { continue }
            let distance = abs(date.timeIntervalSince(baseDate))
            if distance < bestDistance {
                bestDistance = distance
                bestDate = date
            }
        }
        return bestDate
    }

    /// 周X 解析：不带前缀取最近未来（含今天）；"下周X"再推一周
    private static func weekdayDate(prefix: String,
                                    targetWeekday: Int,
                                    baseDate: Date,
                                    calendar: Calendar) -> Date? {
        let todayWeekday = calendar.component(.weekday, from: baseDate)
        var daysAhead = (targetWeekday - todayWeekday + 7) % 7
        if prefix == "下" { daysAhead += 7 }
        return calendar.date(byAdding: .day, value: daysAhead, to: baseDate)
    }

    /// 周字 → Calendar.weekday（1=周日 ... 7=周六）
    private static let weekdayMap: [Character: Int] = [
        "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1
    ]
}
