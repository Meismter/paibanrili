import Foundation
import SwiftData
import Observation

/// 成员管理视图模型：成员的增删改（CRUD）。
/// 所有写库后统一刷新 Widget 快照（共享约定 #9）。
@MainActor
@Observable
final class MemberManagementViewModel {

    /// 成员列表（按 createdAt 升序）
    private(set) var members: [Member] = []

    /// 最近一次操作提示（如删除"我自己"被拒绝、保存失败等）
    var lastMessage: String?

    // MARK: - 加载

    func load(context: ModelContext) {
        members = (try? context.fetch(
            FetchDescriptor<Member>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? []
    }

    // MARK: - 增

    /// 新增成员并落库；name 为空时降级为"新成员"。
    /// 返回创建成功的成员（便于调用方立即进入编辑），失败返回 nil。
    @discardableResult
    func addMember(name: String,
                   colorHex: String,
                   context: ModelContext) -> Member? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let member = Member(name: trimmed.isEmpty ? "新成员" : trimmed,
                            colorHex: colorHex)
        context.insert(member)
        do {
            try context.save()
            WidgetRefresher.refreshAfterWrite(context: context)
            load(context: context)
            lastMessage = nil
            return member
        } catch {
            lastMessage = "保存失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 改

    /// 修改成员姓名与标识色；name 为空时保留原名。
    func updateMember(member: Member,
                      name: String,
                      colorHex: String,
                      context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        member.name = trimmed.isEmpty ? member.name : trimmed
        member.colorHex = colorHex
        do {
            try context.save()
            WidgetRefresher.refreshAfterWrite(context: context)
            load(context: context)
            lastMessage = nil
        } catch {
            lastMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 删

    /// 删除成员及其全部排班记录（SwiftData 无外键级联，手动按 memberID 批量删除）。
    /// 返回 false 表示被拒绝：不能删除"我自己"成员（isSelf）。
    @discardableResult
    func deleteMember(member: Member,
                      context: ModelContext) -> Bool {
        guard !member.isSelf else {
            lastMessage = "不能删除「我自己」成员"
            return false
        }
        // 先捕获局部值：SwiftData #Predicate 内不可直接引用模型实例属性
        let memberID = member.id
        let predicate = #Predicate<ScheduleEntry> { $0.memberID == memberID }
        let entries = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        entries.forEach { context.delete($0) }
        context.delete(member)
        do {
            try context.save()
            WidgetRefresher.refreshAfterWrite(context: context)
            load(context: context)
            lastMessage = nil
            return true
        } catch {
            lastMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }
}
