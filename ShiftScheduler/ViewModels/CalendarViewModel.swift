import Foundation
import SwiftData
import Observation

/// 月历主页视图模型（R01/R02）：
/// 维护当前显示月份与选中成员，按归属日分桶查询当月排班，
/// 提供单元格指派/清除入口（写库后统一刷新 Widget 快照）。
@MainActor
@Observable
final class CalendarViewModel {

    // MARK: - 状态

    /// 当前显示月份（取该月 1 日正午表示）
    var displayedMonth: Date = Date().noon

    /// 选中的查看成员；nil 表示"我自己"（裁决 #1）
    var selectedMemberID: UUID?

    /// 点击选中的日期（驱动 ShiftPickerSheet）
    var selectedDay: Date?

    /// 当月排班条目（手动拉取，便于按月份/成员过滤）
    private(set) var monthEntries: [ScheduleEntry] = []

    private(set) var members: [Member] = []

    // MARK: - 派生数据

    private var calendar: Calendar { .current }

    var monthTitle: String { displayedMonth.chineseMonthTitle }

    /// 周起始日偏好（1=周日 ... 7=周六；默认周一），与 SettingsView 共用同一 AppStorage 键
    static let firstWeekdayKey = "settings.firstWeekday"
    var firstWeekday: Int {
        let value = UserDefaults.standard.integer(forKey: Self.firstWeekdayKey)
        return (1...7).contains(value) ? value : 2
    }

    /// 当前生效成员（保证非空：回退到 isSelf 成员或首个成员）
    var currentMember: Member? {
        members.first { $0.id == selectedMemberID }
            ?? members.first { $0.isSelf }
            ?? members.first
    }

    /// 当月网格日期单元（nil 为补位）
    var gridCells: [Date?] {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return DateUtils.monthGrid(year: components.year ?? 2026,
                                   month: components.month ?? 1,
                                   firstWeekdayOfWeek: firstWeekday,
                                   calendar: calendar)
    }

    /// 某归属日的排班条目
    func entries(on day: Date) -> [ScheduleEntry] {
        let key = DateUtils.noon(of: day)
        return monthEntries.filter { $0.attributedDate == key }
    }

    // MARK: - 加载

    func load(context: ModelContext) {
        loadMembers(context: context)
        loadMonthEntries(context: context)
    }

    func loadMembers(context: ModelContext) {
        members = (try? context.fetch(
            FetchDescriptor<Member>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? []
        if currentMember == nil {
            // 空库兜底：确保"我自己"存在
            let member = Member.selfMember()
            context.insert(member)
            try? context.save()
            members = [member]
        }
    }

    func loadMonthEntries(context: ModelContext) {
        guard let memberID = currentMember?.id else {
            monthEntries = []
            return
        }
        let range = monthInterval()
        let predicate = #Predicate<ScheduleEntry> { $0.memberID == memberID }
        let all = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        monthEntries = all
            .filter { $0.attributedDate >= range.start && $0.attributedDate <= range.end }
            .sorted { $0.attributedDate < $1.attributedDate }
    }

    // MARK: - 月份/成员切换

    func changeMonth(by delta: Int, context: ModelContext) {
        guard let target = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = DateUtils.noon(of: target)
        loadMonthEntries(context: context)
    }

    func select(memberID: UUID?, context: ModelContext) {
        selectedMemberID = memberID
        loadMonthEntries(context: context)
    }

    // MARK: - 指派 / 清除（R02）

    /// 指派班次到某天（shift 传 nil 即清除该日排班）
    @discardableResult
    func assign(shift: ShiftDefinition?,
                to day: Date,
                member: Member? = nil,
                context: ModelContext) throws -> Bool {
        guard let member = member ?? currentMember else { return false }
        try Self.upsertEntry(member: member, day: day, shift: shift, context: context)
        loadMonthEntries(context: context)
        return true
    }

    /// 单点写库的共享实现（月历指派与 ShiftPickerSheet 复用）：
    /// 同成员同归属日先删后插；shift=nil 表示仅删除。
    static func upsertEntry(member: Member,
                            day: Date,
                            shift: ShiftDefinition?,
                            context: ModelContext) throws {
        let dayNoon = DateUtils.noon(of: day)
        let memberID = member.id // 捕获值：SwiftData #Predicate 内不可直接引用模型实例属性
        let predicate = #Predicate<ScheduleEntry> { $0.memberID == memberID }
        let existing = ((try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [])
            .filter { $0.attributedDate == dayNoon }
        existing.forEach { context.delete($0) }

        if let shift {
            context.insert(ScheduleEntry(memberID: member.id, shift: shift, attributedDate: dayNoon))
        }
        try context.save()
        WidgetRefresher.refreshAfterWrite(context: context)
    }

    // MARK: - 冲突提示（R14 预留接口的消费示例）

    func conflictsThisMonth() -> [Conflict] {
        ConflictDetector.detect(entries: monthEntries)
    }

    // MARK: - 私有

    private func monthInterval() -> (start: Date, end: Date) {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        let start = calendar.date(from: DateComponents(year: components.year ?? 2026,
                                                       month: components.month ?? 1,
                                                       day: 1)) ?? displayedMonth
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1),
                                to: calendar.startOfDay(for: start)) ?? start
        return (DateUtils.noon(of: start), DateUtils.noon(of: end))
    }
}
