import WidgetKit
import SwiftUI

/// @main WidgetBundle：注册排班小组件（small / medium / large 三 family）。
@main
struct ShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftSchedulerWidget()
    }
}

/// 排班小组件：StaticConfiguration 单一配置，三种尺寸按 widgetFamily 分发渲染。
struct ShiftSchedulerWidget: Widget {

    private let kind = "ShiftSchedulerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleTimelineProvider()) { entry in
            FamilyKeyedView(entry: entry)
        }
        .configurationDisplayName("排班助手")
        .description("查看今天、未来 7 天与未来 30 天的班次安排。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// 按 family 分发的根视图（iOS 17 containerBackground 必需）
private struct FamilyKeyedView: View {

    @Environment(\.widgetFamily) private var widgetFamily
    let entry: WidgetEntry

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemMedium:
                MediumWidgetView(date: entry.date, schedules: entry.schedules)
            case .systemLarge:
                LargeWidgetView(date: entry.date, schedules: entry.schedules)
            default:
                SmallWidgetView(date: entry.date, schedules: entry.schedules)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
