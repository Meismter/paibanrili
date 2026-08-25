import SwiftUI

/// 根视图：三 Tab 骨架 —— 排班 / 班次 / 设置（PRD 线框）。
/// 壁纸置底方案：WallpaperLayer 作为整个 App 根视图最底层（覆盖全屏含 TabBar 区域，
/// ignoresSafeArea 保持），TabView 悬浮其上；配合 UIAppearance 的透明导航栏/标签栏
/// 与各 List/Form 的 .scrollContentBackground(.hidden) + .listRowBackground(.clear)，
/// 让壁纸从根底层完整透出，彻底规避宿主 hosting view 不透明背景盖住壁纸的问题。
struct RootTabView: View {

    @State private var selectedTab: WallpaperTab = .schedule

    var body: some View {
        ZStack {
            // 根最底层：当前选中 Tab 的壁纸（覆盖全屏，含 TabBar 区域）
            WallpaperLayer(tab: selectedTab)
                .zIndex(0)

            // 上层：TabView 本身透明，三个 Tab 内容正常展示
            TabView(selection: $selectedTab) {
                tab(.schedule, "排班", "calendar") { MonthCalendarView() }
                tab(.shifts, "班次", "square.grid.2x2") { ShiftListView() }
                tab(.settings, "设置", "gearshape") { SettingsView() }
            }
            .zIndex(1)
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
