import Foundation
import EventKit
import SwiftData

// 注：DraftEntry / ParseResult 等解析草稿类型统一定义在 Parsing/ParsedModels.swift（T03）。

// MARK: - 同步报告

/// 一次日历同步的结果汇总
struct SyncReport: Sendable {
    var created: Int = 0
    var updated: Int = 0
    var failed: Int = 0
    var errors: [String] = []

    var isSuccess: Bool { failed == 0 }
}

/// EventKit 日历同步服务（R05 写入 / R11 读取转草稿）。
///
/// 去重与冲突策略（共享约定 #3）：
/// - 每个事件 notes 首行为稳定标识 "[SS:<ScheduleEntry.id>]"；
/// - 同步前按标识批量查询既有事件；
/// - 冲突以 App 数据为准：删除旧事件 → 按当前数据重建 → 回写新 identifier。
@MainActor
final class EventKitService {

    private let store = EKEventStore()

    // MARK: - 授权

    /// 请求日历完整读写授权（iOS 17 API）。已授权时直接返回 true。
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            NSLog("[EventKitService] 日历授权请求失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 当前是否已获授权（不触发弹窗）
    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// 可写日历列表（供设置页选择目标日历）
    func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    // MARK: - 标识查询

    /// 按 notes 标识批量查询既有事件的 identifier（类图 fetchExistingIdentifiers）。
    /// 查询窗口取当前时刻前后各两年，覆盖常规排班范围。
    func fetchExistingIdentifiers(for entryIDs: [UUID]) -> [UUID: String] {
        guard !entryIDs.isEmpty else { return [:] }
        let calendar = Calendar.current
        let now = Date.now
        let start = calendar.date(byAdding: .year, value: -2, to: now) ?? now
        let end = calendar.date(byAdding: .year, value: 2, to: now) ?? now

        let predicate = store.predicateForEvents(withStart: start,
                                                 withEnd: end,
                                                 matching: NSPredicate(
                                                     format: "notes CONTAINS %@",
                                                     SharedConstants.eventNotesPrefix))
        let events = store.events(matching: predicate)

        var result: [UUID: String] = [:]
        for event in events {
            guard let notes = event.notes else { continue }
            for entryID in entryIDs where notes.contains(SharedConstants.eventTag(for: entryID)) {
                result[entryID] = event.eventIdentifier
            }
        }
        return result
    }

    // MARK: - 写入日历（R05）

    /// 将排班条目同步到指定日历（类图 syncToCalendar）。
    /// 已有同标识事件 → 删旧建新（冲突以 App 为准）；无 → 新建。
    /// 完成后将新 eventIdentifier 回写到各 ScheduleEntry（由调用方负责 context.save()）。
    /// - Parameters:
    ///   - entries: 待同步的排班记录
    ///   - targetCalendar: 用户在设置中选择的目标日历
    ///   - context: 用于解析 shiftID → ShiftDefinition 的模型上下文
    func syncToCalendar(_ entries: [ScheduleEntry],
                        in targetCalendar: EKCalendar,
                        context: ModelContext) async -> SyncReport {
        var report = SyncReport()
        guard !entries.isEmpty else { return report }

        let identifiers = fetchExistingIdentifiers(for: entries.map(\.id))
        let shiftIndex = shiftLookup(context: context)

        for entry in entries {
            do {
                // 删旧（存在即更新语义）
                if let oldIdentifier = identifiers[entry.id],
                   let oldEvent = store.event(withIdentifier: oldIdentifier) {
                    store.remove(oldEvent, span: .thisEvent)
                }

                let event = try buildEvent(for: entry, in: targetCalendar, using: shiftIndex)
                try store.save(event, span: .thisEvent)

                if identifiers[entry.id] != nil {
                    report.updated += 1
                } else {
                    report.created += 1
                }

                // 回写 identifier
                entry.eventIdentifier = event.eventIdentifier
            } catch {
                store.reset()
                report.failed += 1
                report.errors.append("条目 \(entry.id.uuidString.prefix(8)) 同步失败: \(error.localizedDescription)")
            }
        }
        return report
    }

    // MARK: - 从日历读取转草稿（R11）

    /// 读取日期范围内的系统事件并转换为草稿（类图 readDrafts）。
    /// 带 "[SS:" 标识的本应用事件被排除（它们属于 App 数据，不应回流成草稿）。
    /// 未匹配成员统一归入"我自己"（裁决 #1，matchedMemberID 由 ViewModel 层补齐）。
    func readDrafts(from start: Date,
                    to end: Date,
                    in calendar: EKCalendar? = nil) async -> [DraftEntry] {
        guard start < end else { return [] }
        let predicate = store.predicateForEvents(withStart: start, withEnd: end)
        let events = store.events(matching: predicate)

        return events
            .filter { !SharedConstants.isAppTagged(notes: $0.notes) }
            .filter { calendar == nil || $0.calendar == calendar }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                // 标题 "班次名 · HH:mm-HH:mm" → 取分隔符前的班次名作为识别标签
                let title = event.title ?? ""
                let label = title.components(separatedBy: SharedConstants.eventTitleSeparator).first ?? title
                return DraftEntry(
                    attributedDate: DateUtils.noon(of: event.startDate),
                    memberName: SharedConstants.selfMemberName,
                    shiftLabel: label,
                    confidence: 0.75,
                    rawLine: [title, event.notes ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                )
            }
    }

    // MARK: - Private

    /// 构建 shiftID → ShiftDefinition 索引
    private func shiftLookup(context: ModelContext) -> [UUID: ShiftDefinition] {
        let descriptor = FetchDescriptor<ShiftDefinition>()
        let all = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    /// 按共享约定构建 EKEvent：
    /// 标题 "班次名 · HH:mm-HH:mm"；notes 首行 "[SS:<entryUUID>]"；
    /// 跨午夜班次经 endDate 自动落到次日；休息班（时长 0）转为全天事件。
    private func buildEvent(for entry: ScheduleEntry,
                            in targetCalendar: EKCalendar,
                            using shiftIndex: [UUID: ShiftDefinition]) throws -> EKEvent {
        let shift = entry.shiftID.flatMap { shiftIndex[$0] }

        let event = EKEvent(eventStore: store)
        event.calendar = targetCalendar

        if let shift {
            event.title = SharedConstants.eventTitle(shiftName: shift.name,
                                                     startMinutes: shift.startMinutes,
                                                     endMinutes: shift.endMinutes)
            let start = shift.startDate(on: entry.attributedDate)
            let duration = TimeInterval(max(shift.durationMinutes, 0) * 60)
            if duration <= 0 {
                // 休息班：无有效时段，转为归属日全天事件
                event.isAllDay = true
                event.startDate = entry.attributedDate.startOfDay
                event.endDate = entry.attributedDate.startOfDay
            } else {
                event.startDate = start
                event.endDate = start.addingTimeInterval(duration)
            }
        } else {
            // 无班次信息：退化为归属日全天占位事件
            event.title = "排班"
            event.isAllDay = true
            event.startDate = entry.attributedDate.startOfDay
            event.endDate = entry.attributedDate.startOfDay
        }

        var notes = SharedConstants.eventTag(for: entry.id)
        if let note = entry.note, !note.isEmpty {
            notes += "\n\(note)"
        }
        event.notes = notes
        return event
    }
}
