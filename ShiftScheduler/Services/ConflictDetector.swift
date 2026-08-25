import Foundation

/// 冲突记录：同一成员同一天存在多条排班（R14 预留接口，架构假设 #6）。
struct Conflict: Identifiable, Sendable {
    let id: UUID
    /// 冲突成员
    let memberID: UUID
    /// 冲突归属日（正午表示）
    let day: Date
    /// 涉及的全部条目 id
    let entryIDs: [UUID]
    /// 人读原因描述
    let reason: String

    init(id: UUID = UUID(), memberID: UUID, day: Date, entryIDs: [UUID], reason: String) {
        self.id = id
        self.memberID = memberID
        self.day = day
        self.entryIDs = entryIDs
        self.reason = reason
    }
}

/// 冲突检测器：按"成员 × 自然日"分桶，桶内条目数 > 1 即冲突。
/// 纯函数实现、不落库；快速排班预览与导入确认页均可复用。
enum ConflictDetector {

    /// 检测给定条目集合中的冲突。
    /// - Parameters:
    ///   - entries: 待检测的排班条目
    ///   - calendar: 自然日判定用日历，默认 `.current`
    /// - Returns: 按归属日升序的冲突列表
    static func detect(entries: [ScheduleEntry], calendar: Calendar = .current) -> [Conflict] {
        var buckets: [String: (day: Date, entries: [ScheduleEntry])] = [:]

        for entry in entries {
            let dayKey = calendar.startOfDay(for: entry.attributedDate)
            let key = "\(entry.memberID.uuidString)#\(dayKey.timeIntervalSince1970)"
            if var bucket = buckets[key] {
                bucket.entries.append(entry)
                buckets[key] = bucket
            } else {
                buckets[key] = (day: entry.attributedDate, entries: [entry])
            }
        }

        return buckets.values
            .filter { $0.entries.count > 1 }
            .map { bucket in
                Conflict(memberID: bucket.entries[0].memberID,
                         day: bucket.day,
                         entryIDs: bucket.entries.map(\.id),
                         reason: "同一天存在 \(bucket.entries.count) 条排班记录")
            }
            .sorted { $0.day < $1.day }
    }

    /// 便捷接口：判断计划中是否存在任何冲突（供"覆盖已有排班?"弹窗前置检查）
    static func hasConflict(entries: [ScheduleEntry], calendar: Calendar = .current) -> Bool {
        !detect(entries: entries, calendar: calendar).isEmpty
    }
}
