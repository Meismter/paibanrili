import SwiftUI
import SwiftData
import EventKit

/// 日历同步管理页（R05/R11）：
/// 授权引导 → 目标日历选择 → 同步月份勾选 → 「同步所选月份到日历」（含 SyncReport 展示）
/// → 「从日历导入」readDrafts 转草稿，复用 PreviewConfirmView 确认后写库。
///
/// 2026-08 新增：同步/导入均支持勾选多个月份（默认仅当前月）。
struct CalendarSyncView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    @State private var importViewModel = ImportViewModel()

    @AppStorage(SettingsViewModel.targetCalendarIDKey) private var targetCalendarID = ""

    /// 同步结果弹窗文案
    @State private var reportMessage: String?
    @State private var showPreviewImport = false

    /// 勾选的月份集合（key 格式 "yyyy-MM"，默认含当前月）
    @State private var selectedMonthKeys: Set<String> = []

    /// 各候选月份的排班天数缓存（onAppear 计算一次，避免逐行重复取库）
    @State private var monthEntryCounts: [String: Int] = [:]

    private let eventKitService = EventKitService()

    /// 候选月份：当前月前后各 12 个月（共 25 个月）
    private var monthOptions: [MonthOption] {
        let calendar = Calendar.current
        let now = Date.now
        return (-12...12).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset, to: now) else { return nil }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return MonthOption(year: year,
                               month: month,
                               isCurrent: offset == 0)
        }
    }

    /// 候选月份按年份分组（保持时间序）
    private var monthGroups: [(year: Int, months: [MonthOption])] {
        var groups: [(year: Int, months: [MonthOption])] = []
        var currentYear: Int?
        var bucket: [MonthOption] = []
        for option in monthOptions {
            if option.year != currentYear {
                if !bucket.isEmpty {
                    groups.append((currentYear ?? option.year, bucket))
                }
                currentYear = option.year
                bucket = []
            }
            bucket.append(option)
        }
        if !bucket.isEmpty {
            groups.append((currentYear ?? 0, bucket))
        }
        return groups
    }

    /// 候选月份模型
    private struct MonthOption: Identifiable {
        let year: Int
        let month: Int
        let isCurrent: Bool

        var id: String { String(format: "%04d-%02d", year, month) }
        var label: String { "\(year)年\(month)月" + (isCurrent ? "（本月）" : "") }
        var shortLabel: String { "\(month)月" + (isCurrent ? "·今" : "") }
    }

    var body: some View {
        Form {
            authSection
            if viewModel.isAuthorized {
                targetCalendarSection
                monthSelectSection
                syncSection
                importSection
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("日历同步")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refresh()
            if selectedMonthKeys.isEmpty {
                selectedMonthKeys = [monthOptions.first { $0.isCurrent }?.id ?? ""]
            }
            refreshMonthCounts()
        }
        .alert("同步结果", isPresented: .init(get: { reportMessage != nil },
                                             set: { if !$0 { reportMessage = nil } })) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(reportMessage ?? "")
        }
        .sheet(isPresented: $showPreviewImport) {
            NavigationStack {
                PreviewConfirmView(viewModel: importViewModel) { _ in
                    showPreviewImport = false
                } onFailure: { message in
                    showPreviewImport = false
                    reportMessage = message
                }
            }
        }
    }

    // MARK: - 授权

    @ViewBuilder
    private var authSection: some View {
        Section {
            HStack {
                Image(systemName: viewModel.isAuthorized ? "checkmark.seal.fill" : "lock.shield")
                    .foregroundStyle(viewModel.isAuthorized ? .green : .orange)
                Text(viewModel.authStatusText)
                Spacer()
                if !viewModel.isAuthorized {
                    Button("请求授权") {
                        Task { await viewModel.requestAccess() }
                    }
                    .font(.footnote.bold())
                }
            }
            .listRowBackground(Color.clear)
        } header: {
            Text("日历权限")
        } footer: {
            Text("写入排班与读取日历计划需要系统日历访问授权。")
        }
    }

    // MARK: - 目标日历

    @ViewBuilder
    private var targetCalendarSection: some View {
        if !viewModel.calendars.isEmpty {
            Section("目标日历") {
                Picker("写入日历", selection: $targetCalendarID) {
                    ForEach(viewModel.calendars, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(calendar.calendarIdentifier)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - 月份勾选

    /// 紧凑月份网格：按年份分组，每月一个小格子，点击切换选中
    private var monthSelectSection: some View {
        Section {
            ForEach(Array(monthGroups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(String(group.year))年")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("已选 \(group.months.filter { selectedMonthKeys.contains($0.id) }.count)/\(group.months.count)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                              spacing: 6) {
                        ForEach(group.months) { option in
                            monthCell(option)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("同步月份（点击勾选，可多选）")
        } footer: {
            Text("范围覆盖当前月前后各 12 个月，勾选后同步/导入均按所选月份执行。")
        }
    }

    /// 单个月份格子：选中高亮 + 对勾，未选中为浅灰
    private func monthCell(_ option: MonthOption) -> some View {
        let isSelected = selectedMonthKeys.contains(option.id)
        let dayCount = monthEntryCounts[option.id, default: 0]
        return Button {
            toggle(option)
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    Text(option.shortLabel)
                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                Text(dayCount > 0 ? "\(dayCount)天" : "·")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label + (isSelected ? "，已选择" : ""))
    }

    /// 切换选中状态
    private func toggle(_ option: MonthOption) {
        if selectedMonthKeys.contains(option.id) {
            selectedMonthKeys.remove(option.id)
        } else {
            selectedMonthKeys.insert(option.id)
        }
    }

    // MARK: - 写入（R05）

    @ViewBuilder
    private var syncSection: some View {
        Section {
            Button {
                Task { await syncSelectedMonths() }
            } label: {
                Label("同步所选择的月份到日历（\(selectedMonthKeys.count)）",
                      systemImage: "arrow.up.circle.fill")
            }
            .disabled(selectedMonthKeys.isEmpty)
            .listRowBackground(Color.clear)

            Button("全选 / 取消全选") {
                if selectedMonthKeys.count == monthOptions.count {
                    selectedMonthKeys.removeAll()
                } else {
                    selectedMonthKeys = Set(monthOptions.map(\.id))
                }
            }
            .font(.footnote)
            .listRowBackground(Color.clear)
        } footer: {
            Text("以 App 数据为准：已存在的同标识事件会被删除重建，不会产生重复日程。")
        }
    }

    private func syncSelectedMonths() async {
        guard let calendar = viewModel.resolveTargetCalendar(preferredIdentifier: targetCalendarID) else {
            reportMessage = "没有可写的系统日历"
            return
        }
        let entries = entries(inMonths: selectedMonthKeys)
        guard !entries.isEmpty else {
            reportMessage = "所选月份暂无排班记录"
            return
        }
        let report = await eventKitService.syncToCalendar(entries,
                                                          in: calendar,
                                                          context: modelContext)
        try? modelContext.save() // 持久化回写的 eventIdentifier
        WidgetRefresher.refreshAfterWrite(context: modelContext)
        var lines = ["新建 \(report.created)，更新 \(report.updated)"]
        if report.failed > 0 {
            lines.append("失败 \(report.failed)")
            lines.append(contentsOf: report.errors.prefix(3))
        }
        reportMessage = lines.joined(separator: "\n")
    }

    // MARK: - 读取转草稿（R11）

    @ViewBuilder
    private var importSection: some View {
        Section {
            Button {
                Task { await importFromCalendar() }
            } label: {
                Label("从日历导入所选月份计划", systemImage: "arrow.down.circle")
            }
            .disabled(selectedMonthKeys.isEmpty)
            .listRowBackground(Color.clear)
        } footer: {
            Text("读取目标日历所选月份的事件并转为草稿（本应用写入的标识事件会自动排除），确认后合并进排班。")
        }
    }

    private func importFromCalendar() async {
        let range = selectedMonthsInterval()
        guard let start = range?.start, let end = range?.end else {
            reportMessage = "请先勾选至少一个月份"
            return
        }
        let drafts = await eventKitService.readDrafts(from: start,
                                                      to: end,
                                                      in: viewModel.resolveTargetCalendar(preferredIdentifier: targetCalendarID))
        guard !drafts.isEmpty else {
            reportMessage = "所选月份的日历中没有可导入的事件"
            return
        }
        importViewModel.loadExternal(drafts: drafts)
        showPreviewImport = true
    }

    // MARK: - 工具

    /// 一次性统计全部候选月份的排班天数（单次取库，逐月计数）
    private func refreshMonthCounts() {
        let all = (try? modelContext.fetch(
            FetchDescriptor<ScheduleEntry>(sortBy: [SortDescriptor(\.attributedDate)])
        )) ?? []
        var counts: [String: Int] = [:]
        for option in monthOptions {
            guard let range = interval(forMonthKey: option.id) else { continue }
            counts[option.id] = all.filter { $0.attributedDate >= range.start && $0.attributedDate <= range.end }.count
        }
        monthEntryCounts = counts
    }

    /// "yyyy-MM" → 该月 (正午起, 正午止)
    private func interval(forMonthKey key: String) -> (start: Date, end: Date)? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = 1
        guard let start = calendar.date(from: components),
              let daysInMonth = calendar.range(of: .day, in: .month, for: start)?.count else { return nil }
        let end = calendar.date(byAdding: DateComponents(day: daysInMonth - 1), to: start) ?? start
        return (DateUtils.noon(of: start), DateUtils.noon(of: end))
    }

    /// 所选月份的整体区间（最早月初 ~ 最晚月末）
    private func selectedMonthsInterval() -> (start: Date, end: Date)? {
        let intervals = selectedMonthKeys.compactMap { interval(forMonthKey: $0) }.sorted { $0.start < $1.start }
        guard let first = intervals.first, let last = intervals.last else { return nil }
        return (first.start, last.end)
    }

    /// 指定月份键集合内的全部成员排班条目（单次全量取回 + 内存过滤）
    private func entries(inMonths keys: Set<String>) -> [ScheduleEntry] {
        guard !keys.isEmpty else { return [] }
        let intervals: [(start: Date, end: Date)] = keys.compactMap { interval(forMonthKey: $0) }
        guard !intervals.isEmpty else { return [] }
        let all = (try? modelContext.fetch(
            FetchDescriptor<ScheduleEntry>(sortBy: [SortDescriptor(\.attributedDate)])
        )) ?? []
        return all.filter { entry in
            intervals.contains { range in
                entry.attributedDate >= range.start && entry.attributedDate <= range.end
            }
        }
    }
}
