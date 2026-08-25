import SwiftUI

/// 根视图：自定义玻璃底部 TabBar（排班 / 班次 / 设置）。
/// 治本方案：不再使用系统 TabView —— 其宿主容器（UITabBarController 根 view）
/// 自带不透明系统背景，UIAppearance 只能透明化导航栏/标签栏条本身，管不到
/// 控制器根 view，会把 ZStack 最底层的壁纸整层盖住。
/// 改为自定义 TabBar 后层级完全可控：
/// ZStack { WallpaperLayer（最底层全屏壁纸）；内容层 + safeAreaInset 挂玻璃 TabBar }。
/// 三个 tab 内容常驻 ZStack（未选中 opacity(0) 不响应），保证切换不丢状态。
struct RootTabView: View {

    @State private var selectedTab: WallpaperTab = .schedule

    var body: some View {
        ZStack {
            // 最底层：当前选中 Tab 的壁纸（覆盖全屏含 TabBar 区域）
            WallpaperLayer(tab: selectedTab)

            // 中层：三个 tab 内容常驻（保持状态），底部 inset 挂自定义 TabBar
            contentLayer
                .safeAreaInset(edge: .bottom, spacing: 0) { customTabBar }
        }
        .onChange(of: selectedTab) { _, tab in
            // 内容常驻后切回 tab 不再触发 onAppear；通知排班页刷新成员/当月数据
            if tab == .schedule {
                NotificationCenter.default.post(name: .scheduleTabSelected, object: nil)
            }
        }
    }

    // 三个 tab 内容全部常驻 ZStack：选中的正常显示，未选中 opacity(0) + 不响应
    private var contentLayer: some View {
        ZStack {
            tabContent(.schedule) { MonthCalendarView() }
            tabContent(.shifts) { ShiftListView() }
            tabContent(.settings) { SettingsView() }
        }
    }

    private func tabContent<Content: View>(_ tab: WallpaperTab,
                                           @ViewBuilder content: () -> Content) -> some View {
        let isSelected = selectedTab == tab
        content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }

    /// 自定义玻璃底部 TabBar（悬浮胶囊，覆盖在内容之上；键盘弹起自动避让）
    private var customTabBar: some View {
        HStack {
            ForEach(WallpaperTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 22)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: WallpaperTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 20))
                Text(tab.displayName)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 自定义 TabBar 选中排班 Tab 的信号（排班页据此刷新成员/当月数据，
/// 替代原 TabView 切换触发的 onAppear）
extension Notification.Name {
    static let scheduleTabSelected = Notification.Name("ShiftScheduler.scheduleTabSelected")
}
