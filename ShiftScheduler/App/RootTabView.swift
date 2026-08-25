import SwiftUI

/// 根视图：三 Tab 骨架 —— 排班 / 班次 / 设置（PRD 线框）。
/// T04 正式版：三个 Tab 均指向正式视图实现，占位 struct 已全部移除。
struct RootTabView: View {

    var body: some View {
        TabView {
            MonthCalendarView()
                .tabItem {
                    Label("排班", systemImage: "calendar")
                }
            ShiftListView()
                .tabItem {
                    Label("班次", systemImage: "square.grid.2x2")
                }
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}
