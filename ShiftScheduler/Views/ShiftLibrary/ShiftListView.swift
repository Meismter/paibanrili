import SwiftUI
import SwiftData

/// 班次库列表页（R03 正式版）：班次卡片（名称、时间段、色块），右上角"+"新增。
struct ShiftListView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShiftDefinition.sortOrder) private var shifts: [ShiftDefinition]
    @State private var viewModel = ShiftLibraryViewModel()
    @State private var editingShift: ShiftDefinition?
    @State private var showNewSheet = false
    /// 待删除确认的班次
    @State private var deleting: ShiftDefinition?

    var body: some View {
        NavigationStack {
            List {
                if shifts.isEmpty {
                    Text("暂无班次，点击右上角 + 创建")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(shifts) { shift in
                    card(for: shift)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("班次")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建班次")
                }
                ToolbarItem(placement: .cancellationAction) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showNewSheet) {
                ShiftEditView(existing: nil)
            }
            .sheet(item: $editingShift) { shift in
                ShiftEditView(existing: shift)
            }
            .confirmationDialog("删除「\(deleting?.name ?? "")」？",
                                isPresented: .init(get: { deleting != nil },
                                                   set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("同时删除其排班记录", role: .destructive) {
                    if let shift = deleting {
                        _ = viewModel.delete(shift, context: modelContext)
                    }
                    deleting = nil
                }
                Button("取消", role: .cancel) { deleting = nil }
            } message: {
                Text("引用该班次的排班记录将被一并删除。")
            }
        }
    }

    // MARK: - 卡片

    private func card(for shift: ShiftDefinition) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(paletteHex: shift.colorHex))
                .frame(width: 44, height: 44)
                .overlay(alignment: .center) {
                    Text(String(shift.name.prefix(1)))
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(shift.name).font(.headline)
                    if shift.crossesMidnight && !shift.isRestShift {
                        Text("跨次日")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(shift.isRestShift ? "全天休息" : shift.timeRangeText)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)

                if !shift.keywords.isEmpty {
                    Text(shift.keywords.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Menu {
                Button {
                    editingShift = shift
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleting = shift
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}
