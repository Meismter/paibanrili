import Foundation

/// 班次关键词词典：解析引擎（T03）用它把文本中的班次写法映射到已定义的 ShiftDefinition。
/// 规则：
/// 1. 内置词典给出"关键词 → 默认班次名"的基础映射；
/// 2. 实际匹配时优先用用户自定义 ShiftDefinition.keywords（用户别名优先于内置）；
/// 3. 关键词按长度降序匹配，避免"大夜"被"夜"抢先命中。
enum ShiftKeywordDictionary {

    /// 内置词典：关键词 -> 默认班次名。
    static let builtin: [String: String] = [
        // 早班
        "早": "早班", "早班": "早班", "白": "早班", "白班": "早班",
        "上午": "早班", "M": "早班", "m": "早班",
        // 中班
        "中": "中班", "中班": "中班",
        "下午": "中班", "P": "中班", "p": "中班",
        // 晚班（如单位同时存在晚/夜两套，可在班次编辑里改别名）
        "晚": "晚班", "晚班": "晚班", "小夜": "晚班",
        // 夜班
        "夜": "夜班", "夜班": "夜班", "大夜": "夜班",
        "N": "夜班", "n": "夜班", "凌晨": "夜班",
        // 休息
        "休": "休息", "休息": "休息", "off": "休息", "OFF": "休息",
        "Off": "休息", "O": "休息", "o": "休息", "—": "休息", "-": "休息"
    ]

    /// 全部内置关键词，按长度降序排列（长词优先，避免子串误命中）。
    static var sortedKeywords: [String] {
        builtin.keys.sorted { $0.count > $1.count }
    }

    /// 在一行文本中查找命中的默认班次名。
    /// - Returns: 第一个命中的默认班次名；未命中返回 nil。
    static func match(in text: String) -> String? {
        for keyword in sortedKeywords where text.contains(keyword) {
            return builtin[keyword]
        }
        return nil
    }

    // MARK: - 规范化与合并词典（ParseEngine / ImportViewModel 调用面）

    /// 关键词规范化：去首尾空白 + 英文字母大写归一（"off"/"Off" → "OFF"，中文不变）。
    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// 合并词典：内置词典 + 用户自定义别名。
    /// - Parameter userExtra: 班次规范名 → 该班次的全部关键词别名
    ///   （如 ["行政班": ["行", "行政"]]）；默认空表示仅内置词典。
    /// - Returns: 关键词 → 规范班次名 的扁平映射（用户条目覆盖内置同名键），
    ///   键统一做 normalize，按关键词长度降序排列供最长包含匹配。
    static func merged(userExtra: [String: [String]] = [:]) -> [String: String] {
        var result: [String: String] = [:]
        for (keyword, name) in builtin {
            result[normalize(keyword)] = name
        }
        for (canonicalName, keywords) in userExtra {
            let canonical = normalize(canonicalName)
            // 规范班次名本身也可作为匹配词
            if !canonical.isEmpty {
                result[canonical] = canonical
            }
            for keyword in keywords {
                let key = normalize(keyword)
                if !key.isEmpty {
                    result[key] = canonical
                }
            }
        }
        return result
    }

    /// 在合并词典中匹配单个 token：
    /// 1) token 整体精确命中；
    /// 2) 否则取词典中最长的、被 token 包含的关键词（长词优先防子串误命中）。
    /// - Returns: 规范班次名；未命中返回 nil。
    static func match(token: String, using dictionary: [String: String]) -> String? {
        let key = normalize(token)
        guard !key.isEmpty else { return nil }
        if let exact = dictionary[key] { return exact }
        let hit = dictionary.keys
            .filter { key.contains($0) }
            .max { $0.count < $1.count }
        return hit.flatMap { dictionary[$0] }
    }

    /// 便捷重载：仅对内置词典匹配（ParseEngine 判定"行内是否出现班次词"用）。
    static func match(token: String) -> String? {
        match(token: token, using: merged())
    }

    /// 便捷重载：内置 + 指定班次库的别名合并词典。
    /// （uniquingKeysWith：重名班次取首个，防御 Dictionary 重复键崩溃）
    static func match(token: String, definitions: [ShiftDefinition]) -> String? {
        let extra = Dictionary(definitions.map { ($0.name, $0.keywords) },
                               uniquingKeysWith: { first, _ in first })
        return match(token: token, using: merged(userExtra: extra))
    }

    /// 用用户自定义班次的 keywords 做优先匹配；
    /// 未命中再回退到内置词典映射到默认名。
    /// - Parameters:
    ///   - definitions: 当前库中的全部班次（含其 keywords 别名）
    /// - Returns: 命中的 ShiftDefinition.id 或默认班次名（二选一）
    enum MatchOutcome {
        case definition(UUID)   // 直接命中用户自定义班次
        case defaultName(String) // 回退内置词典，由调用方按名称找班次或提示新建
    }

    static func resolve(in text: String, definitions: [ShiftDefinition]) -> MatchOutcome? {
        // 1) 用户自定义别名优先（同样长词优先）
        let userKeywords = definitions
            .flatMap { def in def.keywords.map { ($0, def.id) } }
            .sorted { $0.0.count > $1.0.count }
        for (keyword, defID) in userKeywords where text.contains(keyword) {
            return .definition(defID)
        }
        // 2) 用户班次名本身也可作为匹配词（如自定义"行政班"）
        for def in definitions.sorted(by: { $0.name.count > $1.name.count })
        where !def.name.isEmpty && text.contains(def.name) {
            return .definition(def.id)
        }
        // 3) 内置词典兜底
        if let name = match(in: text) {
            return .defaultName(name)
        }
        return nil
    }
}
