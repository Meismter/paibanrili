import SwiftUI

/// 根视图：三 Tab 骨架 —— 排班 / 班次 / 设置（PRD 线框）。
/// 批次 A：每个 Tab 的内容下层铺对应 Tab 的壁纸层（WallpaperLayer，zIndex 最底），
/// 内容层（玻璃浮层）在上层；切换 Tab 时壁纸随 Tab 独立加载。
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
        ZStack {
            WallpaperLayer(tab: tab)
                .zIndex(0)
            content()
                .zIndex(1)
        }
        .tag(tab)
        .tabItem {
            Label(title, systemImage: icon)
        }
    }
}
