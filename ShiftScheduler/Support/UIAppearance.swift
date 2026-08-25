import UIKit

/// 全局外观配置：透明导航栏 + 透明 TabBar，配合各 List/Form 的
/// `.scrollContentBackground(.hidden)`，让内容呈现玻璃通透效果。在 App init 中调用一次。
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
        UINavigationBar.appearance().isTranslucent = true

        // TabBar：全透明背景，去掉顶部分隔线
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundImage = UIImage()
        tabAppearance.shadowImage = UIImage()
        tabAppearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().isTranslucent = true
        // 保险：显式将 TabBar 背景色置透明
        UITabBar.appearance().barTintColor = .clear
    }
}
