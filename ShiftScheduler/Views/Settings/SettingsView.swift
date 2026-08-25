import SwiftUI
import SwiftData

/// 设置页（正式版）：日历同步入口、周起始日偏好、小组件添加引导。
struct SettingsView: View {

    // 周起始日：1=周日 ... 7=周六；默认周一（与 CalendarViewModel 共用键）
    @AppStorage(CalendarViewModel.firstWeekdayKey) private var firstWeekday = 2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CalendarSyncView()
                    } label: {
                        Label("日历同步", systemImage: "calendar.badge.checkmark")
                    }
                } header: {
                    Text("同步")
                }

                Section {
                    Picker("每周开始于", selection: $firstWeekday) {
                        Text("周日").tag(1)
                        Text("周一").tag(2)
                        Text("周六").tag(7)
                    }
                } header: {
                    Text("日历偏好")
                } footer: {
                    Text("影响月历网格的星期排列。")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("添加桌面小组件", systemImage: "square.on.square")
                            .font(.subheadline.bold())
                        Text("长按桌面空白处 → 左上角 + → 搜索「排班助手」→ 选择小 / 中 / 大尺寸即可查看今日、未来 7 天与未来 30 天的班次安排。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("小组件")
                }

                Section {
                    LabeledContent("版本", value: "1.0")
                    LabeledContent("数据存储", value: "完全本地，不上传任何数据")
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
        }
    }
}
