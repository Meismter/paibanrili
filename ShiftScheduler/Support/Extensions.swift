import Foundation

// MARK: - Date 扩展

extension Date {

    /// 规范化为该自然日 12:00 本地时间（归属日期统一存储格式）。
    var asAttributedDate: Date { DateUtils.attributedDate(from: self) }

    /// 该自然日 12:00 本地时间（归属日正午表示，唯一定义在 DateUtils）。
    var noon: Date { DateUtils.noon(of: self) }

    /// 加/减若干天（保持当日时刻不变；DST 由 Calendar 处理）。
    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// 是否为同一自然日（本地时区比较）。
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    var startOfDay: Date { DateUtils.startOfDay(of: self) }

    /// "HH:mm" 格式。
    var timeString: String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// "2026年3月5日" 格式。
    var chineseDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: self)
    }

    var year: Int { Calendar.current.component(.year, from: self) }
    var month: Int { Calendar.current.component(.month, from: self) }
    var day: Int { Calendar.current.component(.day, from: self) }
}

// MARK: - Int 分钟扩展（距午夜分钟数 <-> 文本）

extension Int {

    // 注：Int.timeString 唯一定义在 SharedKit/SharedFormatting.swift
    //（Widget 扩展视图亦需使用），此处不再重复声明。

    /// "HH:mm" 或 "H点" 等宽松文本 -> 距午夜的分钟数；解析失败返回 nil。
    static func minutes(fromTimeText text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "：", with: ":")
        // 24 小时制 HH:mm
        if let idx = s.firstIndex(of: ":") {
            let h = Int(s[s.startIndex..<idx])
            let m = Int(s[s.index(after: idx)...])
            if let h, let m, (0...23).contains(h), (0...59).contains(m) {
                return h * 60 + m
            }
        }
        // "晚8点" / "8点30" 类：提取数字按小时处理
        let digits = s.filter(\.isNumber)
        if let h = Int(digits), (0...23).contains(h) {
            return h * 60
        }
        return nil
    }
}

// MARK: - String 扩展

extension String {

    /// 是否包含任一关键词（用于班次词典匹配）。
    func containsAny(of keywords: [String]) -> Bool {
        keywords.contains { contains($0) }
    }

    /// 去除首尾空白与常见标点。
    var trimmedClean: String {
        trimmingCharacters(in: .whitespacesAndCNPunctuation)
    }
}

private extension CharacterSet {
    /// whitespace/newline + 中文常用标点
    static var whitespacesAndCNPunctuation: CharacterSet {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "，。、；：！？·…-—_")
        return set
    }
}

// MARK: - Collection 扩展

extension Array where Element == UUID {
    /// 去重保持顺序。
    var uniqued: [UUID] {
        var seen = Set<UUID>()
        return filter { seen.insert($0).inserted }
    }
}
