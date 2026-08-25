import XCTest
@testable import ShiftScheduler

/// 跨午夜判定与归属日期验证（共享约定 #2/#4，架构 §1.1）。
final class CrossMidnightTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - crossesMidnight 判定

    func testCrossesMidnightTrue() {
        // 22:00-06:00 → 结束(360) < 开始(1320) → 跨午夜
        XCTAssertTrue(DateUtils.crossesMidnight(startMinutes: 22 * 60, endMinutes: 6 * 60))
    }

    func testCrossesMidnightFalse() {
        XCTAssertFalse(DateUtils.crossesMidnight(startMinutes: 8 * 60, endMinutes: 16 * 60))
    }

    func testEndZeroMeansMidnight24() {
        // 中班 16:00-24:00：结束存 0（< 960）→ 跨午夜
        XCTAssertTrue(DateUtils.crossesMidnight(startMinutes: 16 * 60, endMinutes: 0))
    }

    func testRestShiftIsNotCrossMidnight() {
        // 休班约定 start=end=0：不算跨午夜
        XCTAssertFalse(DateUtils.crossesMidnight(startMinutes: 0, endMinutes: 0))
    }

    // MARK: - interval(on:) 与具体时刻

    func testNightShiftIntervalSpansTwoDays() {
        // 自定义夜班 22:00-06:00，归属日 3月5日：
        // 开始 = 3月5日 22:00；结束 = 3月6日 06:00；时长 480 分钟
        let shift = ShiftDefinition(name: "大夜",
                                    startMinutes: 22 * 60,
                                    endMinutes: 6 * 60,
                                    colorHex: "#3949AB")
        let attributedDay = date(2026, 3, 5)

        let interval = shift.interval(on: attributedDay, calendar: calendar)
        XCTAssertEqual(interval.duration, TimeInterval(480 * 60), accuracy: 1)

        let expectedStart = date(2026, 3, 5, hour: 22)
        let expectedEnd = date(2026, 3, 6, hour: 6)
        XCTAssertEqual(interval.start.timeIntervalSince1970,
                       expectedStart.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(shift.endDate(on: attributedDay, calendar: calendar).timeIntervalSince1970,
                       expectedEnd.timeIntervalSince1970, accuracy: 1)
    }

    func testMiddleShiftEndsAtNextMidnight() {
        // 中班 16:00-24:00：结束时刻为次日 0 点
        let shift = ShiftDefinition.defaultLibrary().first { $0.name == "中班" }!
        let attributedDay = date(2026, 3, 5)

        XCTAssertEqual(shift.durationMinutes, 480)
        XCTAssertEqual(shift.timeRangeText, "16:00-24:00")
        let expectedEnd = date(2026, 3, 6) // 正午构造的次日；比较用 0 点另算
        let actualEnd = shift.endDate(on: attributedDay, calendar: calendar)
        XCTAssertEqual(actualEnd, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date(2026, 3, 5))))
        _ = expectedEnd
    }

    func testRestShiftHasZeroDuration() {
        let rest = ShiftDefinition.defaultLibrary().first { $0.name == "休" }!
        XCTAssertEqual(rest.durationMinutes, 0)
        XCTAssertFalse(rest.crossesMidnight)
        XCTAssertEqual(rest.timeRangeText, "休息")
    }

    // MARK: - 归属日期规则

    func testAttributedDateNormalizedToNoon() {
        // 归属日期 = 班次开始时刻所在自然日的 12:00（ScheduleEntry init 内归一化）
        let member = Member.selfMember()
        let shift = ShiftDefinition(name: "晚班", startMinutes: 20 * 60, endMinutes: 23 * 60)
        // 传入当天凌晨时刻表示"这一天"，应被归一化为该日正午
        let rawDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 0))!
        let entry = ScheduleEntry(memberID: member.id, shift: shift, attributedDate: rawDay)

        let expectedNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0,
                                         of: calendar.startOfDay(for: rawDay))!
        XCTAssertEqual(entry.attributedDate, expectedNoon)
    }

    func testLateNightShiftStillBelongsToStartDate() {
        // 22:00 开班的班次，即使跨到次日，归属日仍是开始当日
        let shift = ShiftDefinition(name: "夜", startMinutes: 22 * 60, endMinutes: 6 * 60)
        let startDate = shift.startDate(on: date(2026, 3, 5), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: startDate), 5)
        let endDate = shift.endDate(on: date(2026, 3, 5), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: endDate), 6)
    }
}
