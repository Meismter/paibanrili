import Foundation

// MARK: - 跨 target 共享格式化扩展
//
// 说明：这些成员原先在主 target 的 Support/Extensions.swift，
// 因 Widget 扩展视图也需要使用，统一下沉到 SharedKit（双 target 均编译，唯一定义）。

/// 分钟数 → "HH:mm"（共享约定 #4：时间展示唯一入口）
public extension Int {
    var timeString: String {
        let clamped = Swift.max(0, Swift.min(1439, self))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// 距午夜分钟数的合法区间收敛（0...1439），越界值钳制到边界。
    var clampedToMinutesOfDay: Int {
        Swift.max(0, Swift.min(1439, self))
    }
}

/// 中文日期标题（小组件与月历共用）
public extension Date {
    /// 如 "2026年3月"
    var chineseMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: self)
    }

    /// 如 "3月5日"
    var chineseDayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: self)
    }
}
