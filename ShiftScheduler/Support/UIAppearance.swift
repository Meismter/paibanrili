import UIKit

/// 全局外观配置（批次修复）：透明导航栏 + 透明 TabBar。
/// 根因：NavigationStack / TabView 的默认系统背景（不透明）会盖住
/// RootTabView ZStack 底层的 WallpaperLayer，导致壁纸设置后不可见。
/// 此配置让导航栏与标签栏透明，配合各 List/Form 的 `.scrollContentBackground(.hidden)`，
/// 使壁纸层完整透出。在 App init 中调用一次。
enum UIAppearance {

    static func apply() {
        // 导航栏：全透明背景，去掉分隔线
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = .clear
        navAppearance.shadowImage = UIImage()
        navAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // TabBar：全透明背景，去掉顶部分隔线
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundImage = UIImage()
        tabAppearance.shadowImage = UIImage()
        tabAppearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
