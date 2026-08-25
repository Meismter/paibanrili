import SwiftUI
import PhotosUI
import Observation

/// 壁纸作用的 Tab（每 Tab 独立配置，键名 wallpaper.<tab>.xxx）
enum WallpaperTab: String, CaseIterable, Identifiable, Hashable {
    case schedule = "schedule"
    case shifts = "shifts"
    case settings = "settings"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .schedule: return "排班"
        case .shifts: return "班次"
        case .settings: return "设置"
        }
    }

    var iconName: String {
        switch self {
        case .schedule: return "calendar"
        case .shifts: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }
}

/// 内置渐变壁纸
struct BuiltinWallpaper: Identifiable {
    let id: Int
    let name: String
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
}

/// 壁纸管理（批次 A）：每 Tab 独立配置，UserDefaults 持久化。
/// 存储约定：
/// - `wallpaper.<tab>.id`：0 = 默认（无壁纸）；1...8 = 内置壁纸序号；-1 = 相册图片
/// - `wallpaper.<tab>.opacity`：0.2...1.0
/// - `wallpaper.<tab>.scale`：0.5...2.0
/// - 相册图片存 Documents/Wallpapers/<tab>.jpg
@MainActor
@Observable
final class WallpaperManager {

    static let shared = WallpaperManager()

    // MARK: - 内置壁纸库（8 张渐变）

    static let builtins: [BuiltinWallpaper] = [
        BuiltinWallpaper(id: 1, name: "晨曦",
                         colors: [Color(red: 0.95, green: 0.76, blue: 0.55),
                                  Color(red: 0.99, green: 0.92, blue: 0.83)],
                         startPoint: .topLeading, endPoint: .bottomTrailing),
        BuiltinWallpaper(id: 2, name: "海蓝",
                         colors: [Color(red: 0.29, green: 0.55, blue: 0.84),
                                  Color(red: 0.62, green: 0.79, blue: 0.95)],
                         startPoint: .top, endPoint: .bottom),
        BuiltinWallpaper(id: 3, name: "青绿",
                         colors: [Color(red: 0.20, green: 0.72, blue: 0.64),
                                  Color(red: 0.66, green: 0.90, blue: 0.80)],
                         startPoint: .topLeading, endPoint: .bottomTrailing),
        BuiltinWallpaper(id: 4, name: "暮紫",
                         colors: [Color(red: 0.49, green: 0.32, blue: 0.76),
                                  Color(red: 0.77, green: 0.56, blue: 0.90)],
                         startPoint: .topTrailing, endPoint: .bottomLeading),
        BuiltinWallpaper(id: 5, name: "暖橙",
                         colors: [Color(red: 0.96, green: 0.60, blue: 0.32),
                                  Color(red: 0.99, green: 0.81, blue: 0.56)],
                         startPoint: .topLeading, endPoint: .bottomTrailing),
        BuiltinWallpaper(id: 6, name: "粉樱",
                         colors: [Color(red: 0.94, green: 0.55, blue: 0.68),
                                  Color(red: 0.99, green: 0.83, blue: 0.88)],
                         startPoint: .bottomLeading, endPoint: .topTrailing),
        BuiltinWallpaper(id: 7, name: "夜空",
                         colors: [Color(red: 0.12, green: 0.15, blue: 0.32),
                                  Color(red: 0.33, green: 0.37, blue: 0.61)],
                         startPoint: .top, endPoint: .bottom),
        BuiltinWallpaper(id: 8, name: "薄荷",
                         colors: [Color(red: 0.55, green: 0.87, blue: 0.72),
                                  Color(red: 0.85, green: 0.97, blue: 0.89)],
                         startPoint: .topLeading, endPoint: .bottomTrailing)
    ]

    // MARK: - 存储键

    private func idKey(_ tab: WallpaperTab) -> String { "wallpaper.\(tab.rawValue).id" }
    private func opacityKey(_ tab: WallpaperTab) -> String { "wallpaper.\(tab.rawValue).opacity" }
    private func scaleKey(_ tab: WallpaperTab) -> String { "wallpaper.\(tab.rawValue).scale" }

    // MARK: - 可观察状态（读取时被 body 追踪，写入后即时触发刷新）

    private(set) var ids: [WallpaperTab: Int] = [:]
    private(set) var opacities: [WallpaperTab: Double] = [:]
    private(set) var scales: [WallpaperTab: Double] = [:]
    private var photoCache: [WallpaperTab: UIImage] = [:]
    /// 强制刷新信号：任何配置写入后 +1，供 UI 建立依赖与过渡动画
    private(set) var revision = 0
    /// 内存态是否已从 UserDefaults 恢复（惰性一次，首次访问时）
    private var hasLoaded = false

    // MARK: - 持久化恢复

    /// 首次访问任何配置前，从 UserDefaults 恢复内存态（App 重启后设置不丢失）。
    /// 纯 getter 读 UserDefaults 无副作用；在全部 getter/setter 入口调用。
    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let defaults = UserDefaults.standard
        for tab in WallpaperTab.allCases {
            if defaults.object(forKey: idKey(tab)) != nil {
                ids[tab] = defaults.integer(forKey: idKey(tab))
            }
            if defaults.object(forKey: opacityKey(tab)) != nil {
                opacities[tab] = defaults.double(forKey: opacityKey(tab))
            }
            if defaults.object(forKey: scaleKey(tab)) != nil {
                scales[tab] = defaults.double(forKey: scaleKey(tab))
            }
        }
    }

    // MARK: - 读取

    /// 选择 id：0=默认，1...=内置，-1=相册图片
    func selectionID(for tab: WallpaperTab) -> Int {
        ensureLoaded()
        return ids[tab] ?? 0
    }

    func opacity(for tab: WallpaperTab) -> Double {
        ensureLoaded()
        return opacities[tab] ?? 1.0
    }

    func scale(for tab: WallpaperTab) -> Double {
        ensureLoaded()
        return scales[tab] ?? 1.0
    }

    /// 相册图片（懒加载磁盘缓存）
    func photoImage(for tab: WallpaperTab) -> UIImage? {
        ensureLoaded()
        if let image = photoCache[tab] { return image }
        let url = photoURL(for: tab)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                NSLog("[Wallpaper] 相册图解码失败: \(tab.rawValue)")
                return nil
            }
            photoCache[tab] = image
            return image
        } catch {
            NSLog("[Wallpaper] 相册图读取失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 写入

    func setSelectionID(_ id: Int, for tab: WallpaperTab) {
        ensureLoaded()
        ids[tab] = id
        revision += 1
        UserDefaults.standard.set(id, forKey: idKey(tab))
    }

    func setOpacity(_ value: Double, for tab: WallpaperTab) {
        ensureLoaded()
        opacities[tab] = value
        revision += 1
        UserDefaults.standard.set(value, forKey: opacityKey(tab))
    }

    func setScale(_ value: Double, for tab: WallpaperTab) {
        ensureLoaded()
        scales[tab] = value
        revision += 1
        UserDefaults.standard.set(value, forKey: scaleKey(tab))
    }

    /// 保存相册图片到 Documents/Wallpapers/<tab>.jpg 并把选择切到相册
    func setPhoto(_ image: UIImage, for tab: WallpaperTab) {
        ensureLoaded()
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            NSLog("[Wallpaper] 相册图 JPEG 编码失败: \(tab.rawValue)")
            return
        }
        do {
            let url = photoURL(for: tab)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            photoCache[tab] = image
            revision += 1
            setSelectionID(-1, for: tab)
        } catch {
            NSLog("[Wallpaper] 保存失败: \(error.localizedDescription)")
        }
    }

    /// 恢复默认：无壁纸 + 全透明 + 1.0 缩放，并清掉相册图片
    func reset(for tab: WallpaperTab) {
        ensureLoaded()
        setSelectionID(0, for: tab)
        setOpacity(1.0, for: tab)
        setScale(1.0, for: tab)
        photoCache[tab] = nil
        try? FileManager.default.removeItem(at: photoURL(for: tab))
    }

    // MARK: - 磁盘

    private func photoURL(for tab: WallpaperTab) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Wallpapers/\(tab.rawValue).jpg")
    }
}

/// 壁纸渲染层：GeometryReader 铺满 + 缩放 + 透明度，置于每 Tab 内容下层。
struct WallpaperLayer: View {

    let tab: WallpaperTab
    @State private var manager = WallpaperManager.shared

    var body: some View {
        // 建立对 revision 的依赖：任何配置写入都会强制本视图刷新并触发过渡动画
        let _ = manager.revision
        GeometryReader { geo in
            ZStack {
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(manager.opacity(for: tab))
                    .animation(.easeInOut(duration: 0.35), value: manager.revision)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch manager.selectionID(for: tab) {
        case -1:
            if let photo = manager.photoImage(for: tab) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(manager.scale(for: tab))
            } else {
                defaultBackground
            }
        case let id where id > 0:
            if let builtin = Self.builtin(withID: id) {
                builtin.gradient.scaleEffect(manager.scale(for: tab))
            } else {
                defaultBackground
            }
        default:
            defaultBackground
        }
    }

    /// 默认（无壁纸）：极浅底色，保证内容可读
    private var defaultBackground: some View {
        LinearGradient(colors: [Color(uiColor: .systemGray6), Color(uiColor: .systemGray5)],
                       startPoint: .top, endPoint: .bottom)
    }

    private static func builtin(withID id: Int) -> BuiltinWallpaper? {
        WallpaperManager.builtins.first { $0.id == id }
    }
}
