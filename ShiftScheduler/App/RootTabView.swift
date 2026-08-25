import SwiftUI

/// 根 Tab 标识（供系统 TabView 的 selection/tag 绑定使用）
enum WallpaperTab: String, CaseIterable, Identifiable, Hashable {
    case schedule = "schedule"
    case shifts = "shifts"
    case settings = "settings"

    var id: String { rawValue }
}

/// 手动外观偏好（AppStorage 键与取值，SettingsView 读写与 RootTabView 应用共用）
enum AppearanceSetting {
    static let key = "settings.appearance"
    static let system = "system"
    static let light = "light"
    static let dark = "dark"
}

/// 根视图：三 Tab 骨架 —— 排班 / 班次 / 设置（PRD 线框）。
/// 使用系统 TabView；WallpaperTab 枚举仅用于 selection 绑定。
/// 根据 AppStorage("settings.appearance") 应用 preferredColorScheme，支持手动深色模式。
struct RootTabView: View {

    @State private var selectedTab: WallpaperTab = .schedule
    @AppStorage(AppearanceSetting.key) private var appearance = AppearanceSetting.system

    var body: some View {
        TabView(selection: $selectedTab) {
            tab(.schedule, "排班", "calendar") { MonthCalendarView() }
            tab(.shifts, "班次", "square.grid.2x2") { ShiftListView() }
            tab(.settings, "设置", "gearshape") { SettingsView() }
        }
        .preferredColorScheme(preferredScheme)
    }

    /// 外观偏好 → 色彩方案："light"/"dark" 手动指定，"system"（含未知值）跟随系统
    private var preferredScheme: ColorScheme? {
        switch appearance {
        case AppearanceSetting.light: return .light
        case AppearanceSetting.dark: return .dark
        default: return nil
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
