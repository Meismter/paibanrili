import SwiftUI
import SwiftData

@main
struct ShiftSchedulerApp: App {

    /// ModelContainer 经 ContainerFactory 单点构建，指向 App Group 共享存储，
    /// 主 App 与 Widget Extension 读写同一文件。
    let container: ModelContainer

    init() {
        // ContainerFactory.sharedContainer() 非 throwing（内部已含
        // App Group → 默认位置 → 纯内存 三级降级，任何情况都返回可用容器），
        // 直接调用即可，无需 do-catch/try。
        container = ContainerFactory.sharedContainer()
        seedDefaultShiftsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }

    /// 首次启动写入内置默认班次：早班/中班/夜班/休息（架构共享知识约定）。
    private func seedDefaultShiftsIfNeeded() {
        let context = container.mainContext
        let existing = (try? context.fetchCount(FetchDescriptor<ShiftDefinition>())) ?? 0
        guard existing == 0 else { return }
        for shift in ShiftDefinition.defaultLibrary() {
            context.insert(shift)
        }
        try? context.save()
    }
}
