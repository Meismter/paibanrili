import SwiftUI
import SwiftData

/// 月历排班主页（R01 正式版）：
/// 月份导航头 + 可横向滑动翻页的月历网格 + 底部快捷操作条。
///
/// 2026-08 迭代：
/// - 滑动翻页：TabView(.page) 无限翻页（上/本/下三页，滑动后回中，弹簧非线性动画）；
/// - 长按年月标题：弹出左右双滚轮选择器（左年右月）快速跳转；
/// - 长按日期：弹出备注预览与编辑入口（艾森豪威尔矩阵）；
/// - 有备注的日期右上角显示象限彩色迷你标签（≤4 个，不挤占相邻日期）；
/// - 性能：数据按归属日分桶 + 班次索引缓存，相邻月数据窗口预载，翻页无空白。
struct MonthCalendarView: View {

    // MARK: - 状态

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CalendarViewModel()

    @State private var showQuickSchedule = false
    @State private var showImport = false

    /// 翻页标识：prev/current/next（物理分页滚动，回中无动画无闪烁）
    private enum PageID: Hashable {
        case prev, current, next
    }
    @State private var scrollID: PageID? = .current

    /// sheet(item:) 需要可标识包装
    private struct PickedDay: Identifiable {
        let id: Date
        let entry: ScheduleEntry?
    }
    @State private var pickedDay: PickedDay?

    /// 长按菜单 → 编辑备注（present DayNoteMatrixView；sheet(item:) 需要 Identifiable 包装）
    private struct NoteDayRequest: Identifiable {
        let id: Date
    }
    @State private var noteDayRequest: NoteDayRequest?

    /// 长按年月标题 → 滚轮选择器
    @State private var showWheelPicker = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                MonthHeaderView(monthTitle: viewModel.monthTitle,
                                displayedYear: viewModel.displayedYearMonth.year,
                                displayedMonthNumber: viewModel.displayedYearMonth.month,
                                members: viewModel.members,
                                currentMember: viewModel.currentMember,
                                onPrevious: { viewModel.changeMonth(by: -1, context: modelContext) },
                                onNext: { viewModel.changeMonth(by: 1, context: modelContext) },
                                onSelectMember: { member in
                                    viewModel.select(memberID: member.id, context: modelContext)
                                },
                                onLongPressTitle: { showWheelPicker = true })

                monthPager

                quickActionBar
            }
            .navigationTitle("排班")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            viewModel.load(context: modelContext)
            viewModel.loadShifts(context: modelContext)
        }
        .onChange(of: showQuickSchedule) { _, showing in
            if !showing { viewModel.loadMonthEntries(context: modelContext) }
        }
        .onChange(of: showImport) { _, showing in
            if !showing { viewModel.loadMonthEntries(context: modelContext) }
        }
        .sheet(isPresented: $showWheelPicker) {
            YearMonthWheelPickerView(
                initialYear: viewModel.displayedYearMonth.year,
                initialMonth: viewModel.displayedYearMonth.month
            ) { year, month in
                viewModel.jumpTo(year: year, month: month, context: modelContext)
            }
        }
        .sheet(isPresented: $showQuickSchedule) {
            QuickScheduleView()
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showImport) {
            ImportSourceView()
                .presentationBackground(.ultraThinMaterial)
        }
        // onDismiss 刷新备注索引：用户可能只编辑备注、不指派班次（onDone 不触发），
        // 否则备注标签要切走 Tab 再回来才显示（Bug 修复 2026-09-06）
        .sheet(item: $pickedDay,
               onDismiss: { viewModel.loadNoteDayKeys(context: modelContext) }) { picked in
            ShiftPickerSheet(day: picked.id,
                             member: viewModel.currentMember ?? Member.selfMember(),
                             onDone: {
                viewModel.loadMonthEntries(context: modelContext)
                viewModel.loadNoteDayKeys(context: modelContext)
            },
                             existingEntry: picked.entry)
        }
        .sheet(item: $noteDayRequest,
               onDismiss: { viewModel.loadNoteDayKeys(context: modelContext) }) { request in
            NavigationStack {
                DayNoteMatrixView(day: request.id)
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - 滑动翻页

    /// 横向翻页：物理分页滚动（跟手），上/本/下三页。
    /// 滑到相邻页后：切换真实月份并把内容无动画回中（新月份已渲染，视觉无缝无闪烁）。
    private var monthPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                MonthGridPage(month: viewModel.displayedMonth.adding(months: -1),
                              viewModel: viewModel,
                              onSelectDay: selectDay,
                              onEditNote: { noteDayRequest = NoteDayRequest(id: $0) })
                    .containerRelativeFrame(.horizontal)
                    .id(PageID.prev)

                MonthGridPage(month: viewModel.displayedMonth,
                              viewModel: viewModel,
                              onSelectDay: selectDay,
                              onEditNote: { noteDayRequest = NoteDayRequest(id: $0) })
                    .containerRelativeFrame(.horizontal)
                    .id(PageID.current)

                MonthGridPage(month: viewModel.displayedMonth.adding(months: 1),
                              viewModel: viewModel,
                              onSelectDay: selectDay,
                              onEditNote: { noteDayRequest = NoteDayRequest(id: $0) })
                    .containerRelativeFrame(.horizontal)
                    .id(PageID.next)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollID)
        .defaultScrollAnchor(.center)
        .scrollIndicators(.hidden)
        .onChange(of: scrollID) { _, newID in
            guard let newID, newID != .current else { return }
            let delta = newID == .prev ? -1 : 1
            viewModel.changeMonth(by: delta, context: modelContext)
            // 立即回中（不带动画）：新月份已在当前页渲染，视觉上无跳变、无末帧闪烁
            withAnimation(nil) {
                scrollID = .current
            }
        }
        .overlay(alignment: .bottomTrailing) {
            backToTodayButton
        }
    }

    private func selectDay(_ day: Date, _ entry: ScheduleEntry?) {
        pickedDay = PickedDay(id: day, entry: entry)
    }

    /// 右下角"返回今日"悬浮按钮：不在本月时显示，点击回到今天所在月份
    @ViewBuilder
    private var backToTodayButton: some View {
        if !viewModel.isShowingCurrentMonth {
            Button {
                withAnimation(.snappy) {
                    viewModel.goToToday(context: modelContext)
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15, weight: .semibold))
                    Text("今日")
                        .font(.caption2.bold())
                }
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回今天")
            .padding(.trailing, 14)
            .padding(.bottom, 14)
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// 底部快捷操作条：⚡快速排班 / ⬆️导入（批次 A 玻璃浮层）
    private var quickActionBar: some View {
        HStack(spacing: 12) {
            Button {
                showQuickSchedule = true
            } label: {
                Label("快速排班", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showImport = true
            } label: {
                Label("导入", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

// MARK: - 单月网格页

/// 一个月历网格页（滑动翻页的每一页）：星期头 + 网格 + 冲突横幅。
/// 数据直接读取 viewModel 的三月窗口分桶，相邻月无需重新取库。
private struct MonthGridPage: View {

    let month: Date
    let viewModel: CalendarViewModel
    let onSelectDay: (Date, ScheduleEntry?) -> Void
    let onEditNote: (Date) -> Void

    /// 是否为"正在显示的中心月"（决定是否展示冲突横幅与"今天"高亮语义）
    private var isCenterMonth: Bool {
        viewModel.displayedMonth.year == month.year && viewModel.displayedMonth.month == month.month
    }

    private var gridCells: [Date?] {
        DateUtils.monthGrid(year: month.year,
                            month: month.month,
                            firstWeekdayOfWeek: viewModel.firstWeekday,
                            calendar: .current)
    }

    var body: some View {
        VStack(spacing: 8) {
            weekdayHeader

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                          spacing: 4) {
                    ForEach(Array(gridCells.enumerated()), id: \.offset) { _, item in
                        cell(for: item)
                    }
                }
                .padding(.horizontal, 8)

                if isCenterMonth && !viewModel.cachedConflicts.isEmpty {
                    conflictBanner
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .glassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, 8)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(DateUtils.weekdaySymbols(firstWeekdayOfWeek: viewModel.firstWeekday),
                    id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    /// 单元格：点击选班次；长按预览/编辑备注
    private func cell(for item: Date?) -> some View {
        Group {
            if let day = item {
                Button {
                    onSelectDay(day, viewModel.entries(on: day).first)
                } label: {
                    DayCellView(day: day,
                                entries: viewModel.entries(on: day),
                                shiftIndex: viewModel.shiftMap,
                                isToday: day.isSameDay(as: viewModel.todayReference),
                                noteQuadrants: noteQuadrants(for: day))
                }
                .buttonStyle(.plain)
                .contextMenu { contextMenuItems(for: day) }
            } else {
                Color.clear.frame(minHeight: 52)
            }
        }
    }

    /// 该日有内容的备注象限（保持象限顺序，最多 4 个）
    private func noteQuadrants(for day: Date) -> [NoteQuadrant] {
        guard let note = viewModel.note(for: day) else { return [] }
        return NoteQuadrant.allCases.filter { !note.items(for: $0).isEmpty }
    }

    /// 长按菜单：备注预览（若有）+ 编辑备注 + 选择班次
    @ViewBuilder
    private func contextMenuItems(for day: Date) -> some View {
        let note = viewModel.note(for: day)

        if let note, !note.isEmpty {
            ForEach(NoteQuadrant.allCases, id: \.rawValue) { quadrant in
                let items = note.items(for: quadrant)
                if !items.isEmpty {
                    Button {
                        onEditNote(day)
                    } label: {
                        Label("\(quadrant.title)：\(items.prefix(2).joined(separator: "、"))",
                              systemImage: quadrant.iconName)
                    }
                }
            }
        } else {
            Button {
                onEditNote(day)
            } label: {
                Label("暂无备注，点击添加", systemImage: "square.grid.2x2")
            }
        }

        Divider()

        Button {
            onEditNote(day)
        } label: {
            Label("编辑备注（艾森豪威尔矩阵）", systemImage: "square.and.pencil")
        }

        Button {
            onSelectDay(day, viewModel.entries(on: day).first)
        } label: {
            Label("选择班次", systemImage: "calendar.badge.plus")
        }
    }

    private var conflictBanner: some View {
        Label("本月有 \(viewModel.cachedConflicts.count) 天存在重复排班，点击格子可修正",
              systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
    }
}
