import SwiftUI
import SwiftData

/// 日期备注编辑页（R15）：艾森豪威尔矩阵四象限布局。
/// 点选象限"+"添加事项，左滑/长按删除；内容实时写库。
struct DayNoteMatrixView: View {

    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 当日备注（onAppear 查询或创建，一天一份）
    @State private var note: DayNote?

    /// 正在添加事项的象限（驱动输入弹窗）
    @State private var activeQuadrant: NoteQuadrant?
    @State private var draftText = ""

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                matrixHeader
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(NoteQuadrant.allCases, id: \.rawValue) { quadrant in
                        quadrantCard(quadrant)
                    }
                }
                .padding(.horizontal, 12)

                Text("提示：备注按日期独立保存，与排班班次互不影响。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).opacity(0.4))
        .navigationTitle(day.chineseDateString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear { loadOrCreateNote() }
        .confirmationDialog("删除该条事项？",
                            isPresented: .init(get: { pendingDelete != nil },
                                               set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) { commitDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(pendingDelete?.text ?? "")
        }
        .alert("添加到「\(activeQuadrant?.title ?? "")」",
               isPresented: .init(get: { activeQuadrant != nil },
                                  set: { if !$0 { activeQuadrant = nil } })) {
            TextField("事项内容", text: $draftText)
            Button("添加") { commitDraft() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(activeQuadrant?.strategy ?? "")
        }
    }

    // MARK: - 头部

    /// 矩阵坐标轴说明头
    private var matrixHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("艾森豪威尔矩阵")
                .font(.headline)
            Text("按「重要性 × 紧急性」把当天要记的事放进四个象限")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 14)
        .padding(.horizontal, 12)
    }

    // MARK: - 象限卡片

    private func quadrantCard(_ quadrant: NoteQuadrant) -> some View {
        let items = note?.items(for: quadrant) ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: quadrant.iconName)
                    .font(.caption)
                    .foregroundStyle(Color(paletteHex: quadrant.colorHex))
                VStack(alignment: .leading, spacing: 1) {
                    Text(quadrant.title)
                        .font(.footnote.bold())
                        .lineLimit(1)
                    Text(quadrant.strategy)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    draftText = ""
                    activeQuadrant = quadrant
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color(paletteHex: quadrant.colorHex))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加\(quadrant.title)事项")
            }

            if items.isEmpty {
                Text("点击 + 添加")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    itemRow(item, quadrant: quadrant, index: index)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(paletteHex: quadrant.colorHex).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(paletteHex: quadrant.colorHex).opacity(0.35), lineWidth: 1)
        )
    }

    /// 单条事项行：点击弹出删除确认
    private func itemRow(_ item: String, quadrant: NoteQuadrant, index: Int) -> some View {
        Button {
            pendingDelete = PendingDelete(quadrant: quadrant, index: index, text: item)
        } label: {
            HStack(alignment: .top, spacing: 5) {
                Circle()
                    .fill(Color(paletteHex: quadrant.colorHex))
                    .frame(width: 5, height: 5)
                    .padding(.top, 4)
                Text(item)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    /// 删除确认所需的标识包装
    private struct PendingDelete: Identifiable {
        let id = UUID()
        let quadrant: NoteQuadrant
        let index: Int
        let text: String
    }
    @State private var pendingDelete: PendingDelete?

    // MARK: - 数据操作

    private func loadOrCreateNote() {
        let key = DayNote.dayKey(for: day)
        let predicate = #Predicate<DayNote> { $0.dayKey == key }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            note = existing
        } else {
            let created = DayNote(dayKey: key)
            modelContext.insert(created)
            try? modelContext.save()
            note = created
        }
    }

    private func commitDraft() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quadrant = activeQuadrant, let note, !text.isEmpty else {
            activeQuadrant = nil
            return
        }
        var items = note.items(for: quadrant)
        items.append(text)
        note.setItems(items, for: quadrant)
        try? modelContext.save()
        activeQuadrant = nil
    }

    private func commitDelete() {
        guard let target = pendingDelete, let note else { return }
        var items = note.items(for: target.quadrant)
        guard target.index < items.count else { pendingDelete = nil; return }
        items.remove(at: target.index)
        note.setItems(items, for: target.quadrant)
        // 全部清空时保留记录（保持"一天一份"结构简单），仅标记更新时间
        try? modelContext.save()
        pendingDelete = nil
    }
}
