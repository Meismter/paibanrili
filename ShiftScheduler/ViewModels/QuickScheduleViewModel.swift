import Foundation
import SwiftData
import Observation

/// 快速排班视图模型（R10）：
/// 成员选择 → 日期范围 → 轮转序列编辑 → computePlan 预览 → applyRotation 应用 → undo。
@MainActor
@Observable
final class QuickScheduleViewModel {

    // MARK: - 状态

    private(set) var members: [Member] = []
    var selectedMemberID: UUID?

    /// 范围起始日（默认当月 1 日正午）
    var rangeStart: Date = Self.defaultMonthStart()

    /// 天数（默认当月天数）
    var numberOfDays: Int = Self.defaultDaysInMonth()

    /// 轮转序列（ShiftDefinition.id 循环填充）
    var pattern: [UUID] = []

    private(set) var shifts: [ShiftDefinition] = []
    private(set) var plan: [PlannedDay] = []
    private(set) var lastMessage: String?
    /// 可 externally 置 nil 以便视图关闭错误弹窗
    var lastError: String?
    /// 应用成功信号：+1 触发撤销横幅
    private(set) var appliedHint = 0

    private let service = QuickScheduleService()

    // MARK: - 派生

    var currentMember: Member? {
        members.first { $0.id == selectedMemberID } ?? members.first { $0.isSelf } ?? members.first
    }

    var canUndo: Bool { service.lastOperationID != nil }

    var rangeEnd: Date {
        rangeStart.adding(days: max(numberOfDays, 1) - 1)
    }

    // MARK: - 加载

    func load(context: ModelContext) {
        members = (try? context.fetch(
            FetchDescriptor<Member>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? []
        if members.isEmpty {
            let member = Member.selfMember()
            context.insert(member)
            try? context.save()
            members = [member]
        }
        shifts = (try? context.fetch(
            FetchDescriptor<ShiftDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
        )) ?? []
    }

    // MARK: - 预览 / 应用 / 撤销

    /// 计算预览计划（不落库，架构 §4.2）
    func computePreview() {
        guard let memberID = currentMember?.id else { return }
        plan = service.computePlan(pattern: normalizedPattern,
                                   startDay: rangeStart,
                                   numDays: numberOfDays)
    }

    /// 批量应用（覆盖已有排班），返回是否成功
    @discardableResult
    func apply(context: ModelContext) -> Bool {
        guard let memberID = currentMember?.id else {
            lastError = "没有可用成员"
            return false
        }
        guard !normalizedPattern.isEmpty else {
            lastError = "轮转序列为空，请先添加班次"
            return false
        }
        do {
            guard let operation = try service.applyRotation(memberID: memberID,
                                                            pattern: normalizedPattern,
                                                            startDay: rangeStart,
                                                            numDays: numberOfDays,
                                                            overwriteExisting: true,
                                                            context: context) else {
                lastError = "日期范围无效"
                return false
            }
            lastMessage = "已写入 \(operation.writtenCount) 天排班"
            lastError = nil
            appliedHint += 1
            return true
        } catch {
            lastError = "应用失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 撤销最近一次批量操作
    @discardableResult
    func undo(context: ModelContext) -> Bool {
        do {
            let restored = try service.undo(context: context)
            lastMessage = restored ? "已撤销最近一次快速排班" : "没有可撤销的操作"
            return restored
        } catch {
            lastError = "撤销失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 便捷动作

    /// 重置范围为当月整月
    func resetToCurrentMonth() {
        rangeStart = Self.defaultMonthStart()
        numberOfDays = Self.defaultDaysInMonth()
    }

    /// 套用内置四班倒轮转（按 sortOrder 取 早/中/夜/休）
    func useDefaultFourShiftRotation() {
        pattern = shifts
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { ["早班", "中班", "夜班", "休"].contains($0.name) }
            .map(\.id)
    }

    // MARK: - 私有

    /// 过滤掉已不存在的班次 id，保证写入有效引用
    private var normalizedPattern: [UUID] {
        let validIDs = Set(shifts.map(\.id))
        return pattern.filter { validIDs.contains($0) }
    }

    private static func defaultMonthStart() -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return calendar.date(from: DateComponents(year: components.year ?? 2026,
                                                  month: components.month ?? 1,
                                                  day: 1)) ?? Date()
    }

    private static func defaultDaysInMonth() -> Int {
        calendar.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    private static var calendar: Calendar { .current }
}
