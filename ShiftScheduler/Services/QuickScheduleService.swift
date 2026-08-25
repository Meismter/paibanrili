import Foundation
import SwiftData

/// 快速排班条目快照：撤销时按此恢复原始记录（含原 id 与日历事件标识）。
struct EntrySnapshot: Sendable {
    let id: UUID
    let memberID: UUID
    let shiftID: UUID?
    let attributedDate: Date
    let note: String?
    let eventIdentifier: String?

    init(from entry: ScheduleEntry) {
        self.id = entry.id
        self.memberID = entry.memberID
        self.shiftID = entry.shiftID
        self.attributedDate = entry.attributedDate
        self.note = entry.note
        self.eventIdentifier = entry.eventIdentifier
    }

    /// 从快照重建 ScheduleEntry（保留原 id，保证日历去重标识稳定）
    func makeEntry() -> ScheduleEntry {
        let entry = ScheduleEntry(memberID: memberID,
                                  shiftID: shiftID,
                                  attributedDate: attributedDate,
                                  note: note,
                                  id: id)
        // 回填日历事件标识：撤销后 EventKit 去重（"[SS:<id>]" 查旧删旧建新）仍能定位旧事件
        entry.eventIdentifier = eventIdentifier
        return entry
    }
}

/// 一次快速排班批量操作的回执（架构假设 #5：仅支持最近一次撤销）
struct QuickScheduleOperation: Identifiable, Sendable {
    let id: UUID
    let memberID: UUID
    /// 操作覆盖的归属日范围（正午表示）
    let firstDay: Date
    let lastDay: Date
    /// 应用前的存量快照（撤销依据）
    let snapshot: [EntrySnapshot]
    let writtenCount: Int
}

/// 快速排班计划项：不落库的预览数据（类图 computePlan 输出）
struct PlannedDay: Identifiable, Hashable, Sendable {
    /// 归属日（正午表示）
    let day: Date
    let shiftID: UUID

    var id: Date { day }
}

/// 快速排班服务（R10）：轮转序列铺满日期范围 + 可撤销。
///
/// 流程（架构 §4.2）：
/// 1. `computePlan` 纯计算预览，不触碰数据库；
/// 2. `applyRotation` 先对范围内存量做内存快照 → 批量写入；
/// 3. `undo` 仅针对最近一次操作，按快照整体恢复。
final class QuickScheduleService {

    /// 最近一次成功应用的操作 id（供 ViewModel 判断"可否撤销"）
    private(set) var lastOperationID: UUID?

    private var lastOperation: QuickScheduleOperation?

    // MARK: - 预览计算（不落库）

    /// 按轮转序列 pattern 循环填充自 startDay 起 numDays 天的计划。
    /// - Parameters:
    ///   - pattern: 轮转序列（如 早→中→夜→休 的 ShiftDefinition.id），为空返回空计划
    ///   - startDay: 起始归属日（任意时刻，内部归一化正午）
    ///   - numDays: 天数（>0）
    static func computePlan(pattern: [UUID], startDay: Date, numDays: Int) -> [PlannedDay] {
        guard !pattern.isEmpty, numDays > 0 else { return [] }
        let base = DateUtils.noon(of: startDay)
        return (0..<numDays).map { offset in
            PlannedDay(day: base.adding(days: offset),
                       shiftID: pattern[offset % pattern.count])
        }
    }

    /// 实例便捷入口（保持与类图 computePlan 对应的调用形态）
    func computePlan(pattern: [UUID], startDay: Date, numDays: Int) -> [PlannedDay] {
        Self.computePlan(pattern: pattern, startDay: startDay, numDays: numDays)
    }

    // MARK: - 应用写入

    /// 将轮转计划批量写入数据库。
    ///
    /// 步骤：快照范围内该成员全部存量条目 → （可选）删除存量 → 写入新条目 → save。
    /// 快照保留在内存中供 undo 使用；已写入日历的旧条目其 EKEvent 清理由 T05 联调统一处理。
    /// - Parameters:
    ///   - memberID: 目标成员
    ///   - pattern: 轮转序列（ShiftDefinition.id 数组）
    ///   - startDay: 起始归属日
    ///   - numDays: 天数
    ///   - overwriteExisting: true 时覆盖范围内已有排班；false 时跳过已有排班的日期
    ///   - context: 模型上下文
    /// - Returns: 操作回执（含 operationID）；参数非法或无可写内容时返回 nil
    @discardableResult
    func applyRotation(memberID: UUID,
                       pattern: [UUID],
                       startDay: Date,
                       numDays: Int,
                       overwriteExisting: Bool = true,
                       context: ModelContext) throws -> QuickScheduleOperation? {
        let plan = Self.computePlan(pattern: pattern, startDay: startDay, numDays: numDays)
        guard let firstDay = plan.first?.day, let lastDay = plan.last?.day else { return nil }

        // 1) 快照：范围内该成员的全部存量条目（先查后改，保证可回滚）
        let existingInRange = try fetchEntries(memberID: memberID,
                                               from: firstDay,
                                               to: lastDay,
                                               context: context)
        let snapshot = existingInRange.map { EntrySnapshot(from: $0) }

        // 2) 处理存量
        if overwriteExisting {
            for entry in existingInRange {
                context.delete(entry)
            }
        }

        // 3) 写入新条目
        var writtenCount = 0
        for planned in plan {
            if !overwriteExisting,
               existingInRange.contains(where: { $0.attributedDate == planned.day }) {
                continue // 保留已有排班
            }
            context.insert(ScheduleEntry(memberID: memberID,
                                         shiftID: planned.shiftID,
                                         attributedDate: planned.day))
            writtenCount += 1
        }

        try context.save()

        // 共享约定 #9：任何写库出口都要重建 Widget 快照并刷新时间线
        WidgetRefresher.refreshAfterWrite(context: context)

        // 4) 登记最近一次操作
        let operation = QuickScheduleOperation(id: UUID(),
                                               memberID: memberID,
                                               firstDay: firstDay,
                                               lastDay: lastDay,
                                               snapshot: snapshot,
                                               writtenCount: writtenCount)
        lastOperation = operation
        lastOperationID = operation.id
        return operation
    }

    // MARK: - 撤销

    /// 撤销最近一次快速排班操作（架构假设 #5：仅内存快照、单层撤销）。
    /// 恢复语义：删除范围内当前全部条目 → 原样重建快照条目（保留原 id 与 eventIdentifier）。
    /// - Parameter operationID: 指定要撤销的操作；nil 表示"最近一次"
    @discardableResult
    func undo(operationID: UUID? = nil, context: ModelContext) throws -> Bool {
        guard let operation = lastOperation,
              operationID == nil || operation.id == operationID else {
            return false
        }

        // 1) 清空范围内当前状态
        let currentEntries = try fetchEntries(memberID: operation.memberID,
                                              from: operation.firstDay,
                                              to: operation.lastDay,
                                              context: context)
        for entry in currentEntries {
            context.delete(entry)
        }

        // 2) 按快照恢复（保留原 id / eventIdentifier / note）
        for snapshotItem in operation.snapshot {
            context.insert(snapshotItem.makeEntry())
        }

        try context.save()

        // 共享约定 #9：撤销同样改变了数据库与 Widget 展示内容
        WidgetRefresher.refreshAfterWrite(context: context)

        lastOperation = nil
        lastOperationID = nil
        return true
    }

    // MARK: - Private

    /// 查询成员在 [from, to] 归属日范围内的全部条目（按归属日升序）
    private func fetchEntries(memberID: UUID,
                              from: Date,
                              to: Date,
                              context: ModelContext) throws -> [ScheduleEntry] {
        let predicate = #Predicate<ScheduleEntry> { $0.memberID == memberID }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.attributedDate)])
        return try context.fetch(descriptor)
            .filter { $0.attributedDate >= from && $0.attributedDate <= to }
    }
}
