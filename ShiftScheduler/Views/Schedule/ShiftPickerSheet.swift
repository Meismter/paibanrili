import SwiftUI
import SwiftData

/// 班次指派 Bottom Sheet（R02）：列出全部班次（色点+名称+时间段），
/// 点击即指派写库；含"清除"按钮。
struct ShiftPickerSheet: View {

    let day: Date
    let member: Member

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShiftDefinition.sortOrder) private var shifts: [ShiftDefinition]

    /// 指派/清除完成后的回调（父视图刷新网格）
    var onDone: () -> Void = {}

    /// 该日既有排班（用于勾选标记）；nil 表示当日无排班
    var existingEntry: ScheduleEntry? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("\(day.chineseDayTitle) · \(member.name)") {
                    ForEach(shifts) { shift in
                        Button {
                            assign(shift)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(paletteHex: shift.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(shift.name)
                                Spacer()
                                Text(shift.timeRangeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if existingEntry?.shiftID == shift.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        clear()
                    } label: {
                        Label("清除该日排班", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("选择班次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 动作

    private func assign(_ shift: ShiftDefinition) {
        do {
            try CalendarViewModel.upsertEntry(member: member,
                                              day: day,
                                              shift: shift,
                                              context: modelContext)
            onDone()
            dismiss()
        } catch {
            // 写库失败静默关闭前先提示：用简单 alert 代价高，这里打印并保持面板
            NSLog("[ShiftPickerSheet] 指派失败: \(error.localizedDescription)")
        }
    }

    private func clear() {
        do {
            try CalendarViewModel.upsertEntry(member: member,
                                              day: day,
                                              shift: nil,
                                              context: modelContext)
            onDone()
            dismiss()
        } catch {
            NSLog("[ShiftPickerSheet] 清除失败: \(error.localizedDescription)")
        }
    }
}
