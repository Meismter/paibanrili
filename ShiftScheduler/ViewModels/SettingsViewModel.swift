import Foundation
import EventKit
import Observation

/// 设置视图模型：日历授权状态、目标日历列表、周起始日偏好（AppStorage 由视图层持有）。
@MainActor
@Observable
final class SettingsViewModel {

    private(set) var isAuthorized: Bool = false
    private(set) var calendars: [EKCalendar] = []
    private(set) var lastError: String?

    /// 目标日历 AppStorage 键（存 EKCalendar.calendarIdentifier）
    static let targetCalendarIDKey = "settings.targetCalendarID"
    /// 周起始日键（与 CalendarViewModel 共用）
    static let firstWeekdayKey = CalendarViewModel.firstWeekdayKey

    private let service = EventKitService()

    var authStatusText: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return "已授权（完整访问）"
        case .writeOnly:
            return "已授权（仅写入）"
        case .denied:
            return "已拒绝，请到系统设置开启"
        case .notDetermined:
            return "尚未授权"
        case .restricted:
            return "受系统限制"
        @unknown default:
            return "未知状态"
        }
    }

    // MARK: - 动作

    func refresh() {
        isAuthorized = service.isAuthorized
        calendars = isAuthorized ? service.writableCalendars() : []
    }

    /// 请求日历授权并刷新状态
    func requestAccess() async {
        let granted = await service.requestAccess()
        if granted {
            refresh()
        } else {
            lastError = "授权未通过，无法进行日历同步"
        }
    }

    /// 按存储的 identifier 找回目标日历；无效时回退第一个可写日历
    func resolveTargetCalendar(preferredIdentifier: String?) -> EKCalendar? {
        if let identifier = preferredIdentifier,
           let calendar = calendars.first(where: { $0.calendarIdentifier == identifier }) {
            return calendar
        }
        return calendars.first
    }
}
