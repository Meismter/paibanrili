import SwiftUI

/// 颜色主题 —— 预设 12 色色板与 hex<->Color 转换（架构 §8 共享约定 #1）。
/// 存储约定：一律存 hex 字符串 "#RRGGBB"（大写、带 #）；
/// 新增颜色只能从 `Theme.palette` 中选择，保证 UI 统一。
struct PaletteColor: Identifiable, Hashable, Sendable {
    /// 色板中文名，如 "黄色"
    let name: String
    /// "#RRGGBB" 大写带 #
    let hex: String

    var id: String { hex }
}

enum Theme {

    // MARK: - 预设色板（12 色）

    static let palette: [PaletteColor] = [
        PaletteColor(name: "黄色", hex: "#FDD835"),
        PaletteColor(name: "橙色", hex: "#FB8C00"),
        PaletteColor(name: "红色", hex: "#E53935"),
        PaletteColor(name: "粉色", hex: "#EC407A"),
        PaletteColor(name: "紫色", hex: "#8E24AA"),
        PaletteColor(name: "深蓝", hex: "#3949AB"),
        PaletteColor(name: "蓝色", hex: "#1E88E5"),
        PaletteColor(name: "浅蓝", hex: "#039BE5"),
        PaletteColor(name: "青色", hex: "#00ACC1"),
        PaletteColor(name: "绿色", hex: "#43A047"),
        PaletteColor(name: "棕色", hex: "#6D4C41"),
        PaletteColor(name: "灰色", hex: "#757575")
    ]

    // MARK: - Hex 归一化与校验

    /// 将任意输入归一化为标准 "#RRGGBB"（大写带#）；非法输入返回 nil。
    static func normalizedHex(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !value.hasPrefix("#") {
            value = "#" + value
        }
        guard value.count == 7 else { return nil }
        let body = value.dropFirst()
        guard body.allSatisfy({ $0.isHexDigit }) else { return nil }
        return value
    }

    /// 校验是否为合法的存储格式
    static func isValidHex(_ raw: String) -> Bool {
        normalizedHex(raw) != nil
    }

    // MARK: - Hex <-> Color

    /// hex 字符串 → SwiftUI Color；非法值降级为灰色（委托 SharedKit 唯一实现）。
    static func color(fromHex hex: String) -> Color {
        Color.sharedColor(fromHex: hex)
    }
}

// 注：Color(paletteHex:) 转换已下沉到 SharedKit/SharedColor.swift（双 target 唯一定义），
// Theme.color(fromHex:) 委托同一实现。
