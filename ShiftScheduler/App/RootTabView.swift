import SwiftUI

/// 根 Tab 标识（供系统 TabView 的 selection/tag 绑定使用）
enum WallpaperTab: String, CaseIterable, Identifiable, Hashable {
    case schedule = "schedule"
    case shifts = "shifts"
    case settings = "settings"

    var id: String { rawValue }
}

/// 根视图：三 Tab 骨架 —— 排班 / 班次 / 设置（PRD 线框）。
/// 使用系统 TabView；WallpaperTab 枚举仅用于 selection 绑定。
struct RootTabView: View {

    @State private var selectedTab: WallpaperTab = .schedule

    var body: some View {
        TabView(selection: $selectedTab) {
            tab(.schedule, "排班", "calendar") { MonthCalendarView() }
            tab(.shifts, "班次", "square.grid.2x2") { ShiftListView() }
            tab(.settings, "设置", "gearshape") { SettingsView() }
        }
    }

    private func tab<Content: View>(_ tab: WallpaperTab,
                                    _ title: String,
                                    _ icon: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        content()
            .tag(tab)
            .tabItem {
                Label(title, systemImage: icon)
            }
    }
}
