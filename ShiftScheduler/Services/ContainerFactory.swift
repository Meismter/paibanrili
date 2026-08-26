import Foundation
import SwiftData

/// ModelContainer 工厂 —— 单点构建共享存储（共享约定 #5）。
/// 主 App 与 Widget 必须指向同一 containerURL；Widget 侧只读。
/// 兼容性：无 App Group 权限时（如 Debug 未签名环境）自动降级到本地 Application Support 目录。
enum ContainerFactory {

    /// 共享存储文件名（SQLite 主文件，由 SwiftData 管理）
    private static let storeFileName = "shift_scheduler.store"

    // MARK: - 存储 URL

    /// 计算存储 URL：优先 App Group 容器；无权限时降级 Application Support。
    static func storeURL() -> URL {
        let fileManager = FileManager.default

        // 1) 首选：App Group 容器（主 App 与 Widget 共享）
        if let groupURL = SharedConstants.sharedContainerURL() {
            return groupURL.appendingPathComponent(storeFileName)
        }

        // 2) 降级：Application Support（仅主 App 可见，Widget 将读不到数据）
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent(storeFileName)
    }

    /// 构建 ModelConfiguration
    static func makeConfiguration() -> ModelConfiguration {
        ModelConfiguration(url: storeURL())
    }

    // MARK: - 容器构建

    /// 单点构建 ModelContainer（类图接口 sharedContainer()）。
    /// 失败降级链：共享 URL → 默认位置 → 内存容器（保证 App 永不因存储崩溃）。
    static func sharedContainer() -> ModelContainer {
        let schema = Schema([Member.self, ShiftDefinition.self, ScheduleEntry.self, DayNote.self])

        // 1) 指向 App Group 共享 URL
        do {
            let configuration = makeConfiguration()
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            NSLog("[ContainerFactory] 共享存储构建失败，尝试默认位置: \(error.localizedDescription)")
        }

        // 2) 降级：默认位置（SwiftData 自行管理路径）
        do {
            return try ModelContainer(for: schema, configurations: [])
        } catch {
            NSLog("[ContainerFactory] 默认存储构建失败，降级内存容器: \(error.localizedDescription)")
        }

        // 3) 最终兜底：内存容器（数据不持久化，但应用可用）
        do {
            let inMemory = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("[ContainerFactory] 内存容器亦无法创建，无法启动: \(error)")
        }
    }

    // MARK: - 默认数据播种

    /// 空库播种："我自己"成员 + 内置四班次（早/中/夜/休）。
    /// 幂等：已存在对应数据时跳过。应在 App 启动时调用一次。
    @MainActor
    static func seedDefaultDataIfNeeded(context: ModelContext) {
        seedSelfMemberIfNeeded(context: context)
        seedDefaultShiftsIfNeeded(context: context)
        do {
            try context.save()
        } catch {
            NSLog("[ContainerFactory] 播种数据保存失败: \(error.localizedDescription)")
        }
    }

    /// 确保"我自己"成员存在
    private static func seedSelfMemberIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Member>(predicate: #Predicate { $0.isSelf })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        context.insert(Member.selfMember())
    }

    /// 确保内置班次存在（按名称逐个检查，避免与用户自建同名班次冲突时重复）
    private static func seedDefaultShiftsIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ShiftDefinition>()
        guard let existing = try? context.fetch(descriptor) else { return }
        let existingNames = Set(existing.map(\.name))
        for definition in ShiftDefinition.defaultLibrary() where !existingNames.contains(definition.name) {
            context.insert(definition)
        }
    }
}
