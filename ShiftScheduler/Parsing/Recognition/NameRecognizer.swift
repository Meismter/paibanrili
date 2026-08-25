import Foundation

/// 中文姓名启发式识别器（R06）。
///
/// 策略（架构文件列表注释）：
/// 1. "XX：" / "XX:" 前缀模式 → 冒号前 2~4 字中文词为姓名；
/// 2. 按分隔符切 token，2~4 字、全部汉字且首字命中常见姓氏表者视为姓名。
///
/// 启发式必有误差：所有识别结果都会进入预览确认页由人工修正兜底（架构 §1.1）。
enum NameRecognizer {

    // MARK: - 主入口

    /// 在一行文本中查找候选姓名（去重、保持出现顺序）
    static func findNames(in line: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func append(_ name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleName(trimmed), !blacklist.contains(trimmed),
                  seen.insert(trimmed).inserted else { return }
            result.append(trimmed)
        }

        // 1) "姓名：" 前缀模式
        if let regex = try? NSRegularExpression(pattern: "([\\u{4E00}-\\u{9FFF}]{2,4})[：:]") {
            let nsLine = line as NSString
            for match in regex.matches(in: line,
                                       range: NSRange(location: 0, length: nsLine.length)) {
                append(nsLine.substring(with: match.range(at: 1)))
            }
        }

        // 2) token 扫描
        for token in Self.tokenize(line) {
            append(token)
        }
        return result
    }

    /// 单 token 是否"像"中文姓名：2~4 字、全为常用汉字、首字在姓氏表内、不在黑名单
    static func looksLikeName(_ token: String) -> Bool {
        isPlausibleName(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - 私有判定

    private static func isPlausibleName(_ name: String) -> Bool {
        guard (2...4).contains(name.count) else { return false }
        let scalars = Array(name.unicodeScalars)
        guard scalars.allSatisfy({ $0.value >= 0x4E00 && $0.value <= 0x9FFF }) else { return false }
        guard let first = name.first, surnames.contains(String(first)) else { return false }
        return !blacklist.contains(name)
    }

    /// 按常见分隔符切词
    private static func tokenize(_ line: String) -> [String] {
        let separators = CharacterSet(charactersIn: "|｜,，、;；:：/\\ \t=＝·•")
        return line.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 明显非姓名的高频词（即使首字撞上姓氏表也不当作人名）
    private static let blacklist: Set<String> = [
        "休息", "排班", "日期", "时间", "姓名", "班次", "星期", "上午",
        "下午", "中午", "晚上", "白班", "夜班", "早班", "中班", "晚班"
    ]

    /// 常见姓氏表（覆盖绝大多数场景；漏网姓名由预览确认页人工修正兜底）
    private static let surnames: Set<String> = [
        "李", "王", "张", "刘", "陈", "杨", "黄", "赵", "吴", "周",
        "徐", "孙", "马", "朱", "胡", "郭", "何", "林", "罗", "高",
        "郑", "梁", "谢", "宋", "唐", "许", "韩", "冯", "邓", "曹",
        "彭", "曾", "肖", "田", "董", "潘", "袁", "蔡", "蒋", "余",
        "杜", "叶", "程", "苏", "魏", "吕", "丁", "任", "沈", "姚",
        "卢", "姜", "崔", "钟", "谭", "陆", "汪", "范", "金", "石",
        "廖", "贾", "夏", "韦", "付", "方", "白", "邹", "孟", "熊",
        "秦", "邱", "江", "尹", "薛", "闫", "段", "雷", "侯", "龙",
        "史", "陶", "黎", "贺", "顾", "毛", "郝", "龚", "邵", "万",
        "钱", "严", "覃", "武", "戴", "莫", "孔", "向", "汤", "常"
    ]
}
