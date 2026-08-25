import Foundation
import SwiftData

/// 排班记录模型：成员 × 归属日期 × 班次（R01/R02 核心数据）。
///
/// 约定（共享约定 #2/#3）：
/// - attributedDate = 班次开始时刻所在自然日，存储统一取该日 12:00 本地时间；
/// - id 同时是日历去重标识来源（EKEvent.notes 首行 "[SS:<id>]"）；
/// - shiftID 为可空关联（nil 表示未指派班次的占位记录，一般不产生）。
@Model
final class ScheduleEntry {

    /// 唯一标识；同时作为日历事件去重标识（"[SS:<uuidString>]"）
    @Attribute(.unique) private(set) var id: UUID

    /// 所属成员（Member.id）
    var memberID: UUID

    /// 指派班次（ShiftDefinition.id），可空
    var shiftID: UUID?

    /// 归属日期（该自然日 12:00 本地），决定月历落格与 Widget 查询
    var attributedDate: Date

    /// 用户备注
    var note: String?

    /// 已写入系统日历的 EKEvent identifier；nil 表示尚未同步
    var eventIdentifier: String?

    /// 创建时间
    var createdAt: Date

    /// 便利初始化器（类图 init(memberID:shift:attributedDate:)）
    /// - Parameters:
    ///   - memberID: 成员 ID
    ///   - shift: 班次定义对象（取其 id 关联）
    ///   - attributedDate: 任意表示归属日的时刻，内部归一化为该日 12:00
    convenience init(memberID: UUID,
                     shift: ShiftDefinition?,
                     attributedDate: Date,
                     note: String? = nil,
                     id: UUID = UUID(),
                     createdAt: Date = .now) {
        self.init(memberID: memberID,
                  shiftID: shift?.id,
                  attributedDate: attributedDate,
                  note: note,
                  id: id,
                  createdAt: createdAt)
    }

    /// 便利初始化器（批量导入/快速排班场景直接给 shiftID）
    init(memberID: UUID,
         shiftID: UUID?,
         attributedDate: Date,
         note: String? = nil,
         id: UUID = UUID(),
         createdAt: Date = .now) {
        self.id = id
        self.memberID = memberID
        self.shiftID = shiftID
        self.attributedDate = DateUtils.noon(of: attributedDate)
        self.note = note
        self.eventIdentifier = nil
        self.createdAt = createdAt
    }
}
