import SwiftUI
import SwiftData

/// 预览确认页（R06 兜底 UI，架构 §4.1）：
/// 草稿表格逐条展示——confidence ≥0.8 绿勾 / 0.6~0.8 正常 / <0.6 黄色高亮强制过目；
/// 每条可改人员/班次/日期/删除；底部"确认导入 N 条"。
struct PreviewConfirmView: View {

    @Bindable var viewModel: ImportViewModel

    /// 确认成功后回调
    let onConfirmed: (Int) -> Void
    /// 确认失败回调（含错误信息）
    let onFailure: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShiftDefinition.sortOrder) private var shifts: [ShiftDefinition]

    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.warnings.isEmpty && viewModel.drafts.isEmpty {
                ContentUnavailableView("无可导入内容", systemImage: "tray")
                Spacer()
            } else {
                warningBanner
                draftList
                confirmFooter
            }
        }
        .navigationTitle("预览确认")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { onConfirmed(0) }
            }
        }
    }

    // MARK: - 警告横幅

    private var warningBanner: some View {
        Group {
            if !viewModel.warnings.isEmpty {
                DisclosureGroup("\(viewModel.warnings.count) 行未能完整识别") {
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                }
                .font(.footnote)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.12))
            }
        }
    }

    // MARK: - 草稿列表

    private var draftList: some View {
        List {
            ForEach($viewModel.drafts) { $draft in
                DraftRow(draft: $draft, shifts: shifts) { shift in
                    viewModel.assignShift(shift, to: draft.id)
                }
                .listRowBackground(rowBackground(for: draft))
            }
            .onDelete { offsets in
                viewModel.removeDraft(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
    }

    /// <0.6 的条目整行黄色底（共享约定 #7）
    private func rowBackground(for draft: DraftEntry) -> Color {
        draft.confidenceLevel == .manualReview ? Color.yellow.opacity(0.18) : .clear
    }

    // MARK: - 底部确认栏

    private var confirmFooter: some View {
        VStack(spacing: 6) {
            if !viewModel.skippedLabels.isEmpty {
                Text("上次跳过：\(viewModel.skippedLabels.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                importDrafts()
            } label: {
                HStack {
                    if isImporting {
                        ProgressView().tint(.white)
                    }
                    Text("确认导入 \(viewModel.drafts.count) 条").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting || viewModel.drafts.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    private func importDrafts() {
        isImporting = true
        do {
            let count = try viewModel.confirmImport(context: modelContext)
            isImporting = false
            onConfirmed(count)
        } catch {
            isImporting = false
            onFailure("导入失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 单行草稿

private struct DraftRow: View {

    @Binding var draft: DraftEntry
    let shifts: [ShiftDefinition]
    /// 选择新班次的回调（同步更新 matchedShiftID 与置信度）
    let onSelectShift: (ShiftDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 首行：置信度标识 + 原始行
            HStack(spacing: 8) {
                confidenceIcon
                Text(draft.rawLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            // 第二行：成员 / 班次 / 日期 三项可编辑
            HStack(spacing: 10) {
                TextField("成员", text: $draft.memberName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 90)

                Menu {
                    ForEach(shifts) { shift in
                        Button {
                            onSelectShift(shift)
                        } label: {
                            Label(shift.name,
                                  systemImage: draft.matchedShiftID == shift.id ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Color(paletteHex: currentColorHex)).frame(width: 9, height: 9)
                        Text(currentShiftName).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                }

                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 子元素

    private var confidenceIcon: some View {
        switch draft.confidenceLevel {
        case .autoConfirm:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .normal:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .manualReview:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }

    private var currentShiftName: String {
        if let id = draft.matchedShiftID,
           let shift = shifts.first(where: { $0.id == id }) {
            return shift.name
        }
        return draft.shiftLabel.isEmpty ? "选择班次" : draft.shiftLabel
    }

    private var currentColorHex: String {
        if let id = draft.matchedShiftID,
           let shift = shifts.first(where: { $0.id == id }) {
            return shift.colorHex
        }
        return "#757575"
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { draft.attributedDate },
                set: { draft.attributedDate = $0 })
    }
}
