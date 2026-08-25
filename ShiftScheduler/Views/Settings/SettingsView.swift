import SwiftUI
import SwiftData

/// 设置页（正式版）：日历同步入口、周起始日偏好、小组件添加引导。
struct SettingsView: View {

    // 周起始日：1=周日 ... 7=周六；默认周一（与 CalendarViewModel 共用键）
    @AppStorage(CalendarViewModel.firstWeekdayKey) private var firstWeekday = 2
    // 外观偏好：system/light/dark（与 RootTabView 共用键）
    @AppStorage(AppearanceSetting.key) private var appearance = AppearanceSetting.system

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag(AppearanceSetting.system)
                        Text("浅色").tag(AppearanceSetting.light)
                        Text("深色").tag(AppearanceSetting.dark)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("外观")
                }

                Section {
                    NavigationLink {
                        MemberManagementView()
                    } label: {
                        Label("成员管理", systemImage: "person.2")
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("成员")
                }

                Section {
                    NavigationLink {
                        CalendarSyncView()
                    } label: {
                        Label("日历同步", systemImage: "calendar.badge.checkmark")
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("同步")
                }

                Section {
                    Picker("每周开始于", selection: $firstWeekday) {
                        Text("周日").tag(1)
                        Text("周一").tag(2)
                        Text("周六").tag(7)
                    }
                    .listRowBackground(Color.clear)
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
                    .listRowBackground(Color.clear)
                } header: {
                    Text("小组件")
                }

                Section {
                    LabeledContent("版本",
                                   value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.6")
                        .listRowBackground(Color.clear)
                    LabeledContent("数据存储", value: "完全本地，不上传任何数据")
                        .listRowBackground(Color.clear)
                } header: {
                    Text("关于")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle("设置")
        }
    }
}
