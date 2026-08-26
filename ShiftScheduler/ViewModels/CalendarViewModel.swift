import Foundation
import SwiftData
import Observation

/// 月历主页视图模型（R01/R02）：
/// 维护当前显示月份与选中成员，按归属日分桶查询当月排班，
/// 提供单元格指派/清除入口（写库后统一刷新 Widget 快照）。
///
/// 性能约定（2026-08 优化）：
/// - 排班条目按归属日预分桶（entriesByDay），单元格查询 O(1)；
/// - 班次索引（shiftMap）只在数据加载时构建，避免每次 body 求值重建字典；
/// - 冲突检测结果随月份加载缓存一次，不在 body 中重复计算。
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

    /// 归属日正午 → 当日条目（loadMonthEntries 时一次性分桶）
    private(set) var entriesByDay: [Date: [ScheduleEntry]] = [:]

    /// shiftID → 班次定义索引（loadShifts 时构建）
    private(set) var shiftMap: [UUID: ShiftDefinition] = [:]

    /// 本月冲突缓存（loadMonthEntries 时计算一次）
    private(set) var cachedConflicts: [Conflict] = []

    /// "今天"引用（load 时快照，避免每格重复构造 Date() 与同日比较）
    private(set) var todayReference: Date = Date()

    /// 有非空备注的归属日键集合（"yyyy-MM-dd"），用于格子上的备注角标
    private(set) var noteDayKeys: Set<String> = []

    /// 归属日键 → DayNote（loadNoteDayKeys 时一次性构建，供长按预览备注）
    private(set) var notesByDayKey: [String: DayNote] = [:]

    // MARK: - 派生数据

    private var calendar: Calendar { .current }

    var monthTitle: String { displayedMonth.chineseMonthTitle }

    /// 当前显示的 (年, 月)
    var displayedYearMonth: (year: Int, month: Int) {
        (displayedMonth.year, displayedMonth.month)
    }

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

    /// 当前显示月是否包含今天
    var isShowingCurrentMonth: Bool {
        displayedMonth.year == todayReference.year && displayedMonth.month == todayReference.month
    }

    // MARK: - 单元格查询

    /// 某归属日的排班条目（O(1) 字典查找；无命中返回空数组）
    func entries(on day: Date) -> [ScheduleEntry] {
        entriesByDay[DateUtils.noon(of: day)] ?? []
    }

    // MARK: - 加载

    func load(context: ModelContext) {
        todayReference = Date()
        loadMembers(context: context)
        loadShifts(context: context)
        loadMonthEntries(context: context)
        loadNoteDayKeys(context: context)
    }

    /// 加载有备注的日期键集合（单次全量取回，量级极小）
    func loadNoteDayKeys(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<DayNote>())) ?? []
        noteDayKeys = Set(all.filter { !$0.isEmpty }.map(\.dayKey))
        notesByDayKey = Dictionary(uniqueKeysWithValues: all.map { ($0.dayKey, $0) })
    }

    /// 某日的备注记录（无则 nil），供长按菜单预览
    func note(for day: Date) -> DayNote? {
        notesByDayKey[DayNote.dayKey(for: day)]
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

    /// 构建班次索引（班次库变更后由 load 重入刷新）
    func loadShifts(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<ShiftDefinition>())) ?? []
        shiftMap = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    func loadMonthEntries(context: ModelContext) {
        guard let memberID = currentMember?.id else {
            monthEntries = []
            entriesByDay = [:]
            cachedConflicts = []
            return
        }
        // 数据窗口 = 上月 + 本月 + 下月：滑动翻页时相邻月立即有数据，无空白闪烁
        let center = monthInterval(offset: 0)
        let start = monthInterval(offset: -1).start
        let end = monthInterval(offset: 1).end
        // 日期范围下推到数据库谓词 + 数据库排序，避免全量取回后内存过滤
        let predicate = #Predicate<ScheduleEntry> {
            $0.memberID == memberID && $0.attributedDate >= start && $0.attributedDate <= end
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.attributedDate)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        monthEntries = fetched

        // 一次性按归属日分桶（覆盖三个月）
        var buckets: [Date: [ScheduleEntry]] = [:]
        buckets.reserveCapacity(fetched.count)
        for entry in fetched {
            buckets[entry.attributedDate, default: []].append(entry)
        }
        entriesByDay = buckets
        // 冲突仅统计当前月（相邻月用于预览）
        cachedConflicts = ConflictDetector.detect(entries: fetched.filter {
            $0.attributedDate >= center.start && $0.attributedDate <= center.end
        })
    }

    // MARK: - 月份/成员切换

    func changeMonth(by delta: Int, context: ModelContext) {
        guard let target = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = DateUtils.noon(of: target)
        loadMonthEntries(context: context)
    }

    /// 跳转到指定年月（长按标题快速切换入口）
    func jumpTo(year: Int, month: Int, context: ModelContext) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let target = calendar.date(from: components) else { return }
        displayedMonth = DateUtils.noon(of: target)
        loadMonthEntries(context: context)
    }

    /// 返回今天所在月份
    func goToToday(context: ModelContext) {
        todayReference = Date()
        displayedMonth = todayReference.noon
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

    /// 本月冲突（缓存在 loadMonthEntries，body 中只读，不再重复检测）
    func conflictsThisMonth() -> [Conflict] {
        cachedConflicts
    }

    // MARK: - 私有

    /// 某偏移月份的区间（offset 0 = 当前显示月；-1/+1 = 相邻月）
    private func monthInterval(offset: Int = 0) -> (start: Date, end: Date) {
        let base = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
        let components = calendar.dateComponents([.year, .month], from: base)
        let start = calendar.date(from: DateComponents(year: components.year ?? 2026,
                                                       month: components.month ?? 1,
                                                       day: 1)) ?? base
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1),
                                to: calendar.startOfDay(for: start)) ?? start
        return (DateUtils.noon(of: start), DateUtils.noon(of: end))
    }
}
