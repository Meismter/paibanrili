import SwiftUI

// MARK: - 跨 target 共享颜色转换
//
// 说明：Widget 与主 App 都需要 "#RRGGBB" → Color 的转换（共享约定 #1），
// 定义在 SharedKit 保证两个 target 唯一实现；色板清单仍在主 target Theme.swift。

public extension Color {
    /// 便捷构造：直接用 "#RRGGBB" 创建颜色；非法值降级为灰色
    init(paletteHex hex: String) {
        self = Self.sharedColor(fromHex: hex)
    }

    /// 独立入口：hex 字符串 → Color（SharedKit 内部独立解析，避免依赖主 target）
    static func sharedColor(fromHex hex: String) -> Color {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !value.hasPrefix("#") {
            value = "#" + value
        }
        guard value.count == 7,
              let rgb = Int(value.dropFirst(), radix: 16) else {
            return Color(red: 0.46, green: 0.46, blue: 0.46)
        }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255.0,
                     green: Double((rgb >> 8) & 0xFF) / 255.0,
                     blue: Double(rgb & 0xFF) / 255.0)
    }
}
