import SwiftUI

/// 小尺寸（systemSmall）：今日当前/下一个班次，大号色块 + 名称 + 时间段。
struct SmallWidgetView: View {

    let date: Date
    let schedules: [DaySchedule]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let slot = currentOrNextSlot {
                VStack(alignment: .leading, spacing: 4) {
                    Circle()
                        .fill(Color(paletteHex: slot.colorHex))
                        .frame(width: 14, height: 14)
                    Text(slot.shiftName)
                        .font(.title3.bold())
                        .lineLimit(1)
                    Text(timeRange(of: slot))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("今天休息 🌙")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Private

    private var headerText: String {
        "今天 · " + date.chineseDayTitle
    }

    /// 当前进行中的班次；无则取今日下一个未开始的班次
    private var currentOrNextSlot: ShiftSlot? {
        guard let today = schedules.first else { return nil }
        let calendar = Calendar.current
        let nowMinutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return today.slots.first { slot in
            !slot.isRest && isOngoing(slot, at: nowMinutes)
        } ?? today.slots.first { $0.startMinutes > nowMinutes && !$0.isRest }
    }

    /// 是否正在进行：普通班次 start <= now < end；
    /// 跨午夜班次（start > end，如 22:00-06:00 存 end=360）折算为 now >= start || now < end。
    private func isOngoing(_ slot: ShiftSlot, at nowMinutes: Int) -> Bool {
        if slot.startMinutes == slot.endMinutes { return false } // 全天休息特例
        if slot.startMinutes < slot.endMinutes {
            return slot.startMinutes <= nowMinutes && nowMinutes < slot.endMinutes
        }
        return nowMinutes >= slot.startMinutes || nowMinutes < slot.endMinutes
    }

    private func timeRange(of slot: ShiftSlot) -> String {
        let end = slot.endMinutes == 0 ? "24:00" : slot.endMinutes.timeString
        return "\(slot.startMinutes.timeString)-\(end)"
    }
}
