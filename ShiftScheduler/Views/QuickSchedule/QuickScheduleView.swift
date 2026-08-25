import SwiftUI
import SwiftData

/// 快速排班向导（R10）：选成员 → 日期范围 → 轮转序列 → 预览网格 → 应用；
/// 应用后提供撤销横幅。
struct QuickScheduleView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = QuickScheduleViewModel()

    var body: some View {
        NavigationStack {
            Form {
                memberSection
                rangeSection
                rotationSection
                previewSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("快速排班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                undoBanner
            }
            .alert("出错了",
                   isPresented: Binding(get: { viewModel.lastError != nil },
                                        set: { if !$0 { viewModel.lastError = nil } })) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(viewModel.lastError ?? "")
            }
        }
        .onAppear { viewModel.load(context: modelContext) }
        .onChange(of: viewModel.appliedHint) { _, _ in
            viewModel.computePreview()
        }
    }

    // MARK: - 分区（@ViewBuilder some View，供 Form 结果构造器直接内嵌）

    @ViewBuilder
    private var memberSection: some View {
        Section("成员") {
            Picker("排班成员", selection: $viewModel.selectedMemberID) {
                ForEach(viewModel.members) { member in
                    Text(member.name).tag(member.id as UUID?)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var rangeSection: some View {
        Section {
            DatePicker("起始日",
                       selection: $viewModel.rangeStart,
                       displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .listRowBackground(Color.clear)

            Stepper(value: $viewModel.numberOfDays, in: 1...366) {
                HStack {
                    Text("天数")
                    Spacer()
                    Text("\(viewModel.numberOfDays) 天")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            LabeledContent("结束于", value: viewModel.rangeEnd.chineseDayTitle)
                .listRowBackground(Color.clear)

            Button("重置为当月整月") {
                viewModel.resetToCurrentMonth()
            }
            .font(.footnote)
            .listRowBackground(Color.clear)
        } header: {
            Text("日期范围")
        }
    }

    @ViewBuilder
    private var rotationSection: some View {
        Section {
            RotationEditorView(shifts: viewModel.shifts,
                               pattern: $viewModel.pattern)
                .listRowBackground(Color.clear)
            if viewModel.pattern.isEmpty {
                Button("使用默认四班倒（早→中→夜→休）") {
                    viewModel.useDefaultFourShiftRotation()
                }
                .font(.footnote)
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("轮转序列")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section {
            Button {
                viewModel.computePreview()
            } label: {
                Label("生成预览（不写入）", systemImage: "eye")
            }
            .listRowBackground(Color.clear)

            if !viewModel.plan.isEmpty {
                previewGrid
                    .listRowBackground(Color.clear)

                Button {
                    _ = viewModel.apply(context: modelContext)
                } label: {
                    Label("应用到 \(viewModel.plan.count) 天", systemImage: "checkmark.circle.fill")
                        .bold()
                }
                .listRowBackground(Color.clear)
            }

            if let message = viewModel.lastMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text("预览与应用")
        } footer: {
            Text("应用将覆盖范围内已有排班；可在底部横幅撤销最近一次操作。")
        }
    }

    /// 预览列表：计划天逐行展示彩色胶囊
    @ViewBuilder
    private var previewGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.plan.prefix(31)) { planned in
                HStack {
                    Text(planned.day.chineseDayTitle)
                        .font(.caption.monospacedDigit())
                    Spacer()
                    capsule(for: planned.shiftID)
                }
            }
            if viewModel.plan.count > 31 {
                Text("…共 \(viewModel.plan.count) 天")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func capsule(for shiftID: UUID) -> some View {
        let shift = viewModel.shifts.first { $0.id == shiftID }
        return HStack(spacing: 4) {
            Circle().fill(Color(paletteHex: shift?.colorHex ?? "#757575"))
                .frame(width: 8, height: 8)
            Text(shift?.name ?? "?").font(.caption)
        }
    }

    // MARK: - 撤销横幅

    @ViewBuilder
    private var undoBanner: some View {
        if viewModel.canUndo {
            HStack {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                Text("已应用快速排班")
                    .font(.footnote)
                Spacer()
                Button("撤销") {
                    _ = viewModel.undo(context: modelContext)
                }
                .font(.footnote.bold())
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }
}
