import SwiftUI
import SwiftData

/// 月历排班主页（R01 正式版）：
/// 月份导航头 + 星期行 + monthGrid 网格 + 底部快捷操作条
/// （⚡快速排班 / ⬆️导入，挂接批次 2 的 ImportSourceView）。
struct MonthCalendarView: View {

    // MARK: - 状态

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShiftDefinition.sortOrder) private var shifts: [ShiftDefinition]
    @State private var viewModel = CalendarViewModel()

    @State private var showQuickSchedule = false
    @State private var showImport = false

    /// sheet(item:) 需要可标识包装
    private struct PickedDay: Identifiable {
        let id: Date
        let entry: ScheduleEntry?
    }
    @State private var pickedDay: PickedDay?

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
                                onPickMonth: { month in
                                    viewModel.jumpTo(year: viewModel.displayedYearMonth.year,
                                                     month: month,
                                                     context: modelContext)
                                },
                                onPickYear: { year in
                                    viewModel.jumpTo(year: year,
                                                     month: viewModel.displayedYearMonth.month,
                                                     context: modelContext)
                                },
                                onBackToToday: { viewModel.goToToday(context: modelContext) })

                calendarCard

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
        .sheet(isPresented: $showQuickSchedule) {
            QuickScheduleView()
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showImport) {
            ImportSourceView()
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $pickedDay) { picked in
            ShiftPickerSheet(day: picked.id,
                             member: viewModel.currentMember ?? Member.selfMember(),
                             onDone: {
                viewModel.loadMonthEntries(context: modelContext)
                viewModel.loadNoteDayKeys(context: modelContext)
            },
                             existingEntry: picked.entry)
        }
    }

    // MARK: - 子视图

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

    /// 月历卡片区域（批次 A：整体玻璃浮层，网格 + 星期头内嵌其中）
    private var calendarCard: some View {
        VStack(spacing: 8) {
            weekdayHeader

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                          spacing: 4) {
                    ForEach(Array(viewModel.gridCells.enumerated()), id: \.offset) { _, item in
                        cell(for: item)
                    }
                }
                .padding(.horizontal, 8)

                if !viewModel.cachedConflicts.isEmpty {
                    conflictBanner
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .glassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, 8)
        .overlay(alignment: .bottomTrailing) {
            backToTodayButton
        }
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

    /// 单元格构建：班次索引与当日条目均来自 ViewModel 缓存，逐格零重建
    private func cell(for item: Date?) -> some View {
        Group {
            if let day = item {
                Button {
                    pickedDay = PickedDay(id: day,
                                          entry: viewModel.entries(on: day).first)
                } label: {
                    DayCellView(day: day,
                                entries: viewModel.entries(on: day),
                                shiftIndex: viewModel.shiftMap,
                                isToday: day.isSameDay(as: viewModel.todayReference),
                                hasNote: viewModel.noteDayKeys.contains(DayNote.dayKey(for: day)))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(minHeight: 52)
            }
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

    /// 底部快捷操作条：⚡快速排班 / ⬆️导入（任务清单 #9；批次 A 改为玻璃浮层）
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
