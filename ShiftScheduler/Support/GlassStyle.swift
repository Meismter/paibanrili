import SwiftUI

extension View {
    /// 玻璃浮层：iOS 26 用系统 Liquid Glass（.glassEffect），旧系统降级 ultraThinMaterial。
    /// 编译：Xcode 26 SDK 中 `#available(iOS 26.0, *)` 合法；运行时按系统版本自动走分支。
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.background(.ultraThinMaterial, in: shape)
                .glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
