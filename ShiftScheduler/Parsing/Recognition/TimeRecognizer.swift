import Foundation

/// 时间段识别命中
struct TimeRangeHit: Equatable, Sendable {
    /// 开始时刻距午夜分钟数（0...1439）
    let startMinutes: Int
    /// 结束时刻距午夜分钟数（0...1439）；结束 < 开始即跨午夜（共享约定 #4）
    let endMinutes: Int
    /// 命中原文
    let rawText: String

    var crossesMidnight: Bool { endMinutes < startMinutes }
}

/// 时间段识别器：识别排班文本中的起止时间。
///
/// 支持形态：
/// - "08:00-16:00"、"22:00–06:00"（分隔符支持 - – — ～ ~ 至 到）
/// - "8点-16点"、"8点到16点"
///
/// 防误伤设计：带冒号的模式优先；"点/时" 模式要求起始侧必须带 "点/时"，
/// 且前后不紧邻数字或冒号，避免把 "08:00-16:00" 中的 "00-16" 误判为时间段。
enum TimeRecognizer {

    // MARK: - 主入口

    static func findTimeRanges(in line: String) -> [TimeRangeHit] {
        let nsLine = line as NSString
        var hits: [TimeRangeHit] = []
        var seen = Set<String>()

        for spec in Self.patternSpecs {
            guard let regex = try? NSRegularExpression(pattern: spec.pattern) else { continue }
            let matches = regex.matches(in: line,
                                        range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                guard let startHour = group(match, spec.startHour, nsLine),
                      let endHour = group(match, spec.endHour, nsLine),
                      (0...23).contains(startHour),
                      (0...23).contains(endHour) else { continue }

                let startMinute = minuteValue(match, spec.startMinute, nsLine)
                let endMinute = minuteValue(match, spec.endMinute, nsLine)

                let hit = TimeRangeHit(
                    startMinutes: startHour * 60 + startMinute,
                    endMinutes: endHour * 60 + endMinute,
                    rawText: nsLine.substring(with: match.range)
                )
                if seen.insert(hit.rawText).inserted {
                    hits.append(hit)
                }
            }
        }
        return hits.sorted { $0.startMinutes < $1.startMinutes }
    }

    // MARK: - 模式规格（正则 + 各捕获组下标）

    private struct PatternSpec {
        let pattern: String
        let startHour: Int
        let startMinute: Int?
        let endHour: Int
        let endMinute: Int?
    }

    private static let patternSpecs: [PatternSpec] = [
        // 1) HH:mm 分隔 HH:mm（分钟必选，两位）
        PatternSpec(pattern: "(\\d{1,2})[:：](\\d{2})\\s*[-–—~～至到]\\s*(\\d{1,2})[:：](\\d{2})",
                    startHour: 1, startMinute: 2, endHour: 3, endMinute: 4),
        // 2) H[点时] 分隔 H（起始侧必须带 点/时，避免与冒号时间串混淆）
        PatternSpec(pattern: "(?<![\\d:])(\\d{1,2})[点时]\\s*[-–—~～至到]\\s*(\\d{1,2})(?![\\d:])",
                    startHour: 1, startMinute: nil, endHour: 2, endMinute: nil)
    ]

    // MARK: - 工具

    private static func group(_ match: NSTextCheckingResult,
                              _ index: Int,
                              _ nsLine: NSString) -> Int? {
        guard index >= 0, index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound else { return nil }
        return Int(nsLine.substring(with: match.range(at: index)))
    }

    private static func minuteValue(_ match: NSTextCheckingResult,
                                    _ index: Int?,
                                    _ nsLine: NSString) -> Int {
        guard let index, let value = group(match, index, nsLine), (0...59).contains(value) else {
            return 0
        }
        return value
    }
}
