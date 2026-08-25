import Foundation
import SwiftData

/// 成员模型（首版单用户，预留多人扩展，PRD R13）。
@Model
final class Member {
    /// 唯一标识。
    @Attribute(.unique) var id: UUID
    /// 姓名（首版默认"我"）。
    var name: String
    /// 是否为"我自己"视角（裁决 #1：首版单用户）。
    var isSelf: Bool
    /// 成员标识色 "#RRGGBB"（可空；空表示使用系统默认色）。
    var colorHex: String?

    init(id: UUID = UUID(), name: String, isSelf: Bool = false, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.isSelf = isSelf
        self.colorHex = colorHex
    }

    /// 首次启动创建的默认"我自己"成员。
    static func makeDefaultSelf() -> Member {
        Member(name: "我", isSelf: true, colorHex: Theme.palette[7]) // 蓝 #1E88E5
    }

    /// 类图约定的调用名（makeDefaultSelf 的别名，唯一定义委托）。
    static func selfMember() -> Member { makeDefaultSelf() }
}
