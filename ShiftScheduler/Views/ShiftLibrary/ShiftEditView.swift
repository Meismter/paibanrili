import SwiftUI
import SwiftData

/// 班次编辑页（R03）：名称、起止时间（时/分轮选）、12 色色板、关键词别名。
/// 跨午夜规则：结束时间 <= 开始时间即跨次日；提供 "24:00" 结束选项（存 0）。
struct ShiftEditView: View {

    /// 编辑已有班次；nil 表示新建
    let existing: ShiftDefinition?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = ShiftLibraryViewModel()
    @State private var name = ""
    @State private var startMinutes = 8 * 60
    @State private var endMinutes = 16 * 60
    @State private var colorHex = "#FDD835"
    /// 关键词以顿号/逗号分隔的文本形式编辑
    @State private var keywordsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：早班 / 夜班", text: $name)
                }

                timeSection
                colorSection
                keywordSection

                if let error = viewModel.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(existing == nil ? "新建班次" : "编辑班次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .bold()
                }
            }
        }
        .onAppear(perform: populateIfNeeded)
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    // MARK: - 分区

    private var timeSection: some View {
        Section {
            Picker("开始", selection: $startMinutes) {
                ForEach(TimeOption.all, id: \.minutes) { option in
                    Text(option.label).tag(option.minutes)
                }
            }

            Picker("结束", selection: $endMinutes) {
                ForEach(TimeOption.allIncludingMidnight, id: \.minutes) { option in
                    Text(option.label).tag(option.minutes)
                }
            }

            LabeledContent("预览") {
                Text(previewText)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("时间段")
        } footer: {
            Text("结束时间不晚于开始时间即视为跨次日；选择 24:00 表示结束于当天午夜（存储为 0）。")
        }
    }

    private var colorSection: some View {
        Section("颜色") {
            ColorPaletteView(selectedHex: $colorHex)
        }
    }

    private var keywordSection: some View {
        Section {
            TextField("早, 早班, 白班, D", text: $keywordsText)
                .autocorrectionDisabled()
        } header: {
            Text("识别关键词别名")
        } footer: {
            Text("用于智能识别导入内容，多个用逗号分隔。")
        }
    }

    // MARK: - 逻辑

    private var hasUnsavedChanges: Bool {
        existing != nil || !name.isEmpty
    }

    private var previewText: String {
        let probe = ShiftDefinition(name: name.isEmpty ? "班次" : name,
                                    startMinutes: startMinutes,
                                    endMinutes: endMinutes,
                                    colorHex: colorHex)
        return "\(probe.crossesMidnight ? "(跨次日) " : "")\(probe.timeRangeText)"
    }

    private func populateIfNeeded() {
        guard let shift = existing else { return }
        name = shift.name
        startMinutes = shift.startMinutes
        endMinutes = shift.endMinutes == 0 && shift.crossesMidnight ? TimeOption.midnight.minutes : shift.endMinutes
        colorHex = shift.colorHex
        keywordsText = shift.keywords.joined(separator: "，")
    }

    private func save() {
        let keywords = keywordsText
            .split(whereSeparator: { "，,;； ".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if viewModel.save(name: name,
                          startMinutes: TimeOption.storageMinutes(startMinutes),
                          endMinutes: TimeOption.storageMinutes(endMinutes),
                          colorHex: colorHex,
                          keywords: keywords,
                          existing: existing,
                          context: modelContext) {
            dismiss()
        }
    }
}

// MARK: - 时间选项

/// 时分轮选选项：每 30 分钟一档 + 全部整点，兼顾精度与滚动长度。
struct TimeOption: Identifiable, Hashable {
    let minutes: Int
    let label: String

    var id: Int { minutes }

    static let midnight = TimeOption(minutes: 1440, label: "24:00") // 仅作结束选项展示，保存前映射回 0

    /// 通用选项（0:00 ~ 23:30 每 30 分钟）
    static let all: [TimeOption] = (0..<48).map { slot in
        let minutes = slot * 30
        return TimeOption(minutes: minutes,
                          label: DateUtils.timeString(minutes: minutes))
    }

    /// 含 "24:00" 的结束侧选项（1440 → 存储时映射为 0）
    static var allIncludingMidnight: [TimeOption] {
        all + [midnight]
    }

    /// 把 UI 选择值映射为存储值（24:00 → 0）
    static func storageMinutes(_ uiMinutes: Int) -> Int {
        uiMinutes >= 1440 ? 0 : uiMinutes.clampedToMinutesOfDay
    }

    /// 把已存储值还原为 UI 选择值（跨午夜的 0 结束 → 24:00）
    static func displayMinutes(_ stored: Int, crossesMidnight: Bool) -> Int {
        (crossesMidnight && stored == 0) ? 1440 : stored.clampedToMinutesOfDay
    }
}
