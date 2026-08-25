import Foundation
import SwiftData
import Observation

/// 班次库视图模型（R03）：班次 CRUD + 色板约束 + 关键词别名编辑。
@MainActor
@Observable
final class ShiftLibraryViewModel {

    private(set) var lastError: String?
    private(set) var lastMessage: String?

    // MARK: - 查询

    func loadShifts(context: ModelContext) -> [ShiftDefinition] {
        (try? context.fetch(
            FetchDescriptor<ShiftDefinition>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        )) ?? []
    }

    // MARK: - 创建 / 更新

    /// 保存班次（existing 为 nil 即新建）。
    /// 颜色必须来自 Theme.palette（共享约定 #1）；分钟数自动收敛 0...1439；
    /// endMinutes <= startMinutes 即跨午夜；0-0 为全天休息。
    @discardableResult
    func save(name: String,
              startMinutes: Int,
              endMinutes: Int,
              colorHex: String,
              keywords: [String],
              existing: ShiftDefinition?,
              context: ModelContext) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastError = "班次名称不能为空"
            return false
        }
        guard Theme.isValidHex(colorHex) else {
            lastError = "颜色不合法，请从色板选择"
            return false
        }
        do {
            if let existing {
                existing.name = trimmedName
                existing.startMinutes = startMinutes.clampedToMinutesOfDay
                existing.endMinutes = endMinutes.clampedToMinutesOfDay
                existing.colorHex = colorHex
                existing.keywords = keywords
                try context.save()
                lastMessage = "已更新「\(trimmedName)」"
            } else {
                let sortOrder = nextSortOrder(context: context)
                context.insert(ShiftDefinition(name: trimmedName,
                                               startMinutes: startMinutes,
                                               endMinutes: endMinutes,
                                               colorHex: colorHex,
                                               keywords: keywords,
                                               sortOrder: sortOrder))
                try context.save()
                lastMessage = "已创建「\(trimmedName)」"
            }
            lastError = nil
            return true
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 删除班次：级联清除引用它的排班记录，保持数据一致。
    @discardableResult
    func delete(_ shift: ShiftDefinition, context: ModelContext) -> Bool {
        do {
            let shiftID = shift.id
            let predicate = #Predicate<ScheduleEntry> { $0.shiftID == shiftID }
            let dependents = try context.fetch(FetchDescriptor(predicate: predicate))
            dependents.forEach { context.delete($0) }
            context.delete(shift)
            try context.save()
            WidgetRefresher.refreshAfterWrite(context: context)
            lastMessage = "已删除「\(shift.name)」及其 \(dependents.count) 条排班记录"
            lastError = nil
            return true
        } catch {
            lastError = "删除失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 私有

    private func nextSortOrder(context: ModelContext) -> Int {
        let all = loadShifts(context: context)
        return (all.map(\.sortOrder).max() ?? -1) + 1
    }
}
