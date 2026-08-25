import SwiftUI
import SwiftData
import EventKit

/// 日历同步管理页（R05/R11）：
/// 授权引导 → 目标日历选择 → 「同步本月到日历」（含 SyncReport 展示）
/// → 「从日历导入」readDrafts 转草稿，复用 PreviewConfirmView 确认后写库。
struct CalendarSyncView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    @State private var importViewModel = ImportViewModel()

    @AppStorage(SettingsViewModel.targetCalendarIDKey) private var targetCalendarID = ""

    /// 同步结果弹窗文案
    @State private var reportMessage: String?
    @State private var showPreviewImport = false

    private let eventKitService = EventKitService()

    var body: some View {
        Form {
            authSection
            if viewModel.isAuthorized {
                targetCalendarSection
                syncSection
                importSection
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("日历同步")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refresh() }
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

    // MARK: - 写入（R05）

    @ViewBuilder
    private var syncSection: some View {
        Section {
            Button {
                Task { await syncThisMonth() }
            } label: {
                Label("同步本月到日历", systemImage: "arrow.up.circle.fill")
            }
            .listRowBackground(Color.clear)
        } footer: {
            Text("以 App 数据为准：已存在的同标识事件会被删除重建，不会产生重复日程。")
        }
    }

    private func syncThisMonth() async {
        guard let calendar = viewModel.resolveTargetCalendar(preferredIdentifier: targetCalendarID) else {
            reportMessage = "没有可写的系统日历"
            return
        }
        let entries = monthEntries()
        guard !entries.isEmpty else {
            reportMessage = "本月暂无排班记录"
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
                Label("从日历导入本月计划", systemImage: "arrow.down.circle")
            }
            .listRowBackground(Color.clear)
        } footer: {
            Text("读取目标日历本月事件并转为草稿（本应用写入的标识事件会自动排除），确认后合并进排班。")
        }
    }

    private func importFromCalendar() async {
        let range = currentMonthInterval()
        let drafts = await eventKitService.readDrafts(from: range.start,
                                                      to: range.end,
                                                      in: viewModel.resolveTargetCalendar(preferredIdentifier: targetCalendarID))
        guard !drafts.isEmpty else {
            reportMessage = "本月日历中没有可导入的事件"
            return
        }
        importViewModel.loadExternal(drafts: drafts)
        showPreviewImport = true
    }

    // MARK: - 工具

    /// 本月全部成员的排班条目
    private func monthEntries() -> [ScheduleEntry] {
        let range = currentMonthInterval()
        let all = (try? modelContext.fetch(
            FetchDescriptor<ScheduleEntry>(sortBy: [SortDescriptor(\.attributedDate)])
        )) ?? []
        return all.filter { $0.attributedDate >= range.start && $0.attributedDate <= range.end }
    }

    private func currentMonthInterval() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date.now
        let components = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: DateComponents(year: components.year ?? 2026,
                                                       month: components.month ?? 1,
                                                       day: 1)) ?? now
        let lastDay = (calendar.range(of: .day, in: .month, for: start)?.count ?? 30)
        let end = calendar.date(byAdding: DateComponents(day: lastDay - 1),
                                to: calendar.startOfDay(for: start)) ?? now
        return (DateUtils.noon(of: start), DateUtils.noon(of: end))
    }
}
