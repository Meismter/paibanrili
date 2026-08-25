import Foundation
import SwiftData
import Observation

/// 导入流程视图模型（R06/R07/R08/R09）：
/// 选来源 → ParseEngine 解析 → 维护草稿列表供预览修正 → confirm 后 upsert 写库。
///
/// 模型转换只发生在本层（共享约定 #6）：ParseEngine 输出值类型草稿，
/// 在 confirmImport(context:) 中才转换为 ScheduleEntry 落库。
@MainActor
@Observable
final class ImportViewModel {

    // MARK: - 状态

    /// 粘贴文本输入
    var pasteText: String = ""

    /// 是否正在解析（驱动进度指示）
    private(set) var isParsing = false

    /// 预览修正用的可变草稿列表（解析结果的副本，逐条可改）
    private(set) var drafts: [DraftEntry] = []

    /// 无法解析行的汇总提示
    private(set) var warnings: [String] = []

    /// 写库时因无法匹配班次被跳过的标签（供失败提示）
    private(set) var skippedLabels: [String] = []

    /// 错误信息（文件读取/写库异常）
    private(set) var errorMessage: String?

    /// 展示信号：解析完成后 +1，View 据此弹出预览页
    private(set) var presentationHint = 0

    /// 最近一次成功导入条数（成功提示用）
    private(set) var lastImportedCount: Int?

    private let engine = ParseEngine()

    // MARK: - 来源解析

    /// 微信粘贴 / TXT 文本直接解析
    func parsePaste() async {
        guard !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先粘贴排班内容"
            return
        }
        await run { [engine] in
            await engine.parse(source: .paste($0))
        }
    }

    /// 文件导入（.txt / .docx / .xlsx）
    func parseFile(at url: URL) async {
        isParsing = true
        resetResult()
        let result = engine.parseFile(at: url)
        apply(result)
        isParsing = false
    }

    // MARK: - 草稿修正

    /// 人工选择班次：更新标签、matchedShiftID 并抬升置信度
    func assignShift(_ shift: ShiftDefinition, to draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].shiftLabel = shift.name
        drafts[index].matchedShiftID = shift.id
        drafts[index].confidence = ConfidenceScorer.manuallyConfirmedScore
    }

    /// 人工修改归属日期
    func updateDate(_ date: Date, for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].attributedDate = DateUtils.noon(of: date)
        drafts[index].confidence = ConfidenceScorer.manuallyConfirmedScore
    }

    /// 人工修改成员名
    func updateMemberName(_ name: String, for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].memberName = name
        drafts[index].matchedMemberID = nil
    }

    /// 删除一条草稿
    func removeDraft(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
    }

    func removeDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    /// 外部来源注入草稿（日历导入 R11 复用预览确认流程）
    func loadExternal(drafts: [DraftEntry]) {
        resetResult()
        self.drafts = drafts
        warnings = ["来自系统日历的事件，请核对成员与班次后确认导入"]
    }

    // MARK: - 确认写入（upsert）

    /// 将修正后的草稿批量写库：
    /// - 成员匹配：按名字精确匹配；未匹配归入"我自己"（裁决 #1），并回填 matchedMemberID；
    /// - 班次匹配：规范名 → 关键词别名 → 词典规范名三级匹配（含用户自定义关键词合并）；
    /// - upsert 语义：同成员同归属日先删后插（与架构 §4.1 writeEntries 一致）。
    /// - Returns: 成功写入条数；抛错时由调用方展示 errorMessage
    @discardableResult
    func confirmImport(context: ModelContext) throws -> Int {
        let members = (try? context.fetch(FetchDescriptor<Member>())) ?? []
        let shifts = (try? context.fetch(
            FetchDescriptor<ShiftDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
        )) ?? []

        skippedLabels = []
        var written = 0

        for draft in drafts {
            // 1) 成员解析
            let member = members.first { $0.name == draft.memberName }
                ?? members.first { $0.isSelf }
            guard let member else {
                skippedLabels.append(draft.shiftLabel.isEmpty ? "(无班次)" : draft.shiftLabel)
                continue
            }

            // 2) 班次解析
            guard let shift = Self.resolveShift(for: draft, in: shifts) else {
                skippedLabels.append(draft.shiftLabel.isEmpty ? "(无法识别)" : draft.shiftLabel)
                continue
            }

            // 3) upsert：同成员同归属日覆盖
            let day = DateUtils.noon(of: draft.attributedDate)
            let predicate = #Predicate<ScheduleEntry> { $0.memberID == member.id }
            let existing = ((try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [])
                .filter { $0.attributedDate == day }
            existing.forEach { context.delete($0) }

            context.insert(ScheduleEntry(memberID: member.id,
                                         shift: shift,
                                         attributedDate: day))
            written += 1
        }

        try context.save()
        lastImportedCount = written
        // 挂接点（主理人裁决①）：写库后重建 Widget 快照并即时刷新时间线
        WidgetRefresher.refreshAfterWrite(context: context)
        resetResult()
        return written
    }

    // MARK: - 班次匹配（静态便于测试）

    /// 三级班次匹配：精确名称 → 关键词别名 → 词典规范名对齐
    static func resolveShift(for draft: DraftEntry, in shifts: [ShiftDefinition]) -> ShiftDefinition? {
        let label = ShiftKeywordDictionary.normalize(draft.shiftLabel)
        guard !label.isEmpty else { return nil }

        if let exact = shifts.first(where: { ShiftKeywordDictionary.normalize($0.name) == label }) {
            return exact
        }
        if let byKeyword = shifts.first(where: { definition in
            definition.keywords.contains { ShiftKeywordDictionary.normalize($0) == label }
        }) {
            return byKeyword
        }
        // 用户自定义班次的别名并入词典后做规范名对齐
        // （uniquingKeysWith：用户可能创建同名班次，重名时取首个，避免运行时崩溃）
        let userExtra = Dictionary(shifts.map { ($0.name, $0.keywords) },
                                   uniquingKeysWith: { first, _ in first })
        if let canonical = ShiftKeywordDictionary.match(token: draft.shiftLabel, using: ShiftKeywordDictionary.merged(userExtra: userExtra)) {
            let canonicalKey = ShiftKeywordDictionary.normalize(canonical)
            return shifts.first { ShiftKeywordDictionary.normalize($0.name) == canonicalKey }
        }
        return nil
    }

    // MARK: - 私有

    private func run(_ parse: @MainActor (String) async -> ParseResult) async {
        isParsing = true
        resetResult()
        let result = await parse(pasteText)
        apply(result)
        isParsing = false
    }

    private func apply(_ result: ParseResult) {
        drafts = result.drafts
        warnings = result.warnings
        if result.drafts.isEmpty && result.warnings.isEmpty {
            errorMessage = "未能识别出任何排班内容"
        } else if !result.drafts.isEmpty {
            presentationHint += 1 // 触发 View 弹出预览确认页
        }
    }

    private func resetResult() {
        drafts = []
        warnings = []
        skippedLabels = []
        errorMessage = nil
    }
}
