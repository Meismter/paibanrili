import Foundation

/// 解析编排器（R06）：提取 → 切分识别 → 打分 → 草稿。
///
/// 纯函数式独立层（架构 §1.3）：只消费文本与词典，不触碰数据库、不依赖网络；
/// 班次仅映射到规范名，shiftID/memberID 的数据库匹配发生在 ViewModel 层（共享约定 #6）。
final class ParseEngine {

    /// 相对日期（今天/明天/周X）的基准时刻
    private let baseDate: Date
    private let calendar: Calendar

    init(baseDate: Date = .now, calendar: Calendar = .current) {
        self.baseDate = baseDate
        self.calendar = calendar
    }

    // MARK: - 主入口（架构 §3 parse(source:)）

    /// 解析一个导入来源，输出可预览修正的草稿结果。
    func parse(source: ImportSource) async -> ParseResult {
        switch source {
        case .paste(let text):
            let lines = TxtExtractor.splitLines(text)
            return recognize(lines: lines)
        case .file(let url):
            return parseFile(at: url)
        }
    }

    /// 同步版文件解析入口（测试可直接调用）
    func parseFile(at url: URL) -> ParseResult {
        let fileExtension = url.pathExtension.lowercased()
        guard let extractor = ExtractorRegistry.extractor(for: fileExtension) else {
            return ParseResult(warnings: ["暂不支持该文件类型：\(fileExtension)"])
        }
        do {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let output = try extractor.extract(data: data)
            var result = recognize(lines: output.lines)
            result.warnings.insert(contentsOf: output.warnings, at: 0)
            return result
        } catch {
            return ParseResult(warnings: ["文件解析失败：\(error.localizedDescription)"])
        }
    }

    // MARK: - 识别与打分

    /// 对文本行做日期/人名/时间段/班次关键词识别并生成草稿（架构 recognize(lines:)）
    func recognize(lines: [String]) -> ParseResult {
        var drafts: [DraftEntry] = []
        var warnings: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let dates = DateRecognizer.findDates(in: line, baseDate: baseDate, calendar: calendar)
            if dates.isEmpty {
                // 无日期：只有当行内存在人名或班次线索时才提示（纯噪声行静默跳过）
                if !NameRecognizer.findNames(in: line).isEmpty || ShiftKeywordDictionary.match(token: line) != nil {
                    warnings.append("无法识别日期：「\(trimmed)」")
                }
                continue
            }

            let names = NameRecognizer.findNames(in: line)
            let timeRanges = TimeRecognizer.findTimeRanges(in: line)
            let segmentsAfter = segments(afterDates: dates, in: line)

            // 成员 × 日期 生成草稿：单行多人视为矩阵语义；无姓名归入"我自己"（裁决 #1）
            let memberNames = names.isEmpty ? [SharedConstants.selfMemberName] : names
            for (dateIndex, dateHit) in dates.enumerated() {
                let shiftToken = firstShiftToken(in: segmentsAfter[dateIndex] ?? "")
                let canonicalMatched = shiftToken.flatMap { ShiftKeywordDictionary.match(token: $0) } != nil
                for memberName in memberNames {
                    let confidence = ConfidenceScorer.score(hasDate: true,
                                                            hasTimeRange: !timeRanges.isEmpty,
                                                            hasShiftMatch: canonicalMatched,
                                                            hasName: !names.isEmpty)
                    drafts.append(DraftEntry(
                        attributedDate: DateUtils.noon(of: dateHit.date, calendar: calendar),
                        memberName: memberName,
                        shiftLabel: shiftToken ?? "",
                        confidence: confidence,
                        rawLine: trimmed
                    ))
                }
            }
        }

        // 稳定排序：按归属日升序，便于预览页阅读
        drafts.sort { $0.attributedDate < $1.attributedDate }
        return ParseResult(drafts: drafts, warnings: warnings)
    }

    // MARK: - 私有切分工具

    /// 计算每个日期命中（按位置升序，即 dates 的下标）之后、下一个日期之前的片段
    private func segments(afterDates hits: [DateHit], in line: String) -> [Int: String] {
        let nsLine = line as NSString
        var result: [Int: String] = [:]
        let sorted = hits.sorted { $0.nsRange.location < $1.nsRange.location }

        for (index, hit) in sorted.enumerated() {
            let segmentStart = hit.nsRange.location + hit.nsRange.length
            let segmentEnd: Int
            if index + 1 < sorted.count {
                segmentEnd = sorted[index + 1].nsRange.location
            } else {
                segmentEnd = nsLine.length
            }
            guard segmentEnd > segmentStart else {
                result[index] = ""
                continue
            }
            result[index] = nsLine.substring(with: NSRange(location: segmentStart,
                                                           length: segmentEnd - segmentStart))
        }
        return result
    }

    /// 在片段中找第一个能被词典匹配的班次 token：
    /// 按 | , 、 空格等分隔符切词后过滤含数字的 token（时间串），再逐个查词典。
    private func firstShiftToken(in segment: String) -> String? {
        let separators = CharacterSet(charactersIn: "|｜,，、;；=＝·•\t /\\()（）[]【】")
        let tokens = segment.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(where: { $0.isNumber }) }

        let dictionary = ShiftKeywordDictionary.merged()
        return tokens.first { ShiftKeywordDictionary.match(token: $0, using: dictionary) != nil }
    }
}
