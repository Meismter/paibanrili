import XCTest
@testable import ShiftScheduler

/// DateRecognizer 单元测试：绝对/相对日期、跨年边界、时间段防误伤。
final class DateRecognizerTests: XCTestCase {

    private var calendar: Calendar!
    private var timeZone: TimeZone!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        timeZone = TimeZone(identifier: "Asia/Shanghai")
        calendar.timeZone = timeZone
    }

    /// 构造指定年月日的本地时刻（正午）
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    // MARK: - 绝对日期

    func testFullChineseDateWithYear() {
        let hits = DateRecognizer.findDates(in: "2026年3月5日 早班",
                                            baseDate: date(2026, 3, 10),
                                            calendar: calendar)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.rawText, "2026年3月5日")
        XCTAssertEqual(hits.first?.date, date(2026, 3, 5))
    }

    func testChineseDateWithoutYearUsesNearestYear() {
        let hits = DateRecognizer.findDates(in: "3月5号 白班",
                                            baseDate: date(2026, 6, 1),
                                            calendar: calendar)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.date, date(2026, 3, 5))
    }

    func testShortDashFormat() {
        let hits = DateRecognizer.findDates(in: "03-05 早班",
                                            baseDate: date(2026, 6, 1),
                                            calendar: calendar)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.date, date(2026, 3, 5))
    }

    func testNumericSlashFormat() {
        let hits = DateRecognizer.findDates(in: "2026/3/5 中班",
                                            baseDate: date(2026, 6, 1),
                                            calendar: calendar)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.date, date(2026, 3, 5))
    }

    // MARK: - 跨年边界

    func testCrossYearForward() {
        // 基准 2026-12-20，文本"1月5日"应推断为 2027 年
        let hits = DateRecognizer.findDates(in: "1月5日 早班",
                                            baseDate: date(2026, 12, 20),
                                            calendar: calendar)
        XCTAssertEqual(hits.first?.date, date(2027, 1, 5))
    }

    func testCrossYearBackward() {
        // 基准 2026-02-01，文本"12月30日"应推断为 2025 年
        let hits = DateRecognizer.findDates(in: "12月30日 休",
                                            baseDate: date(2026, 2, 1),
                                            calendar: calendar)
        XCTAssertEqual(hits.first?.date, date(2025, 12, 30))
    }

    // MARK: - 相对日期

    func testTomorrowAndDayAfterTomorrow() {
        let base = date(2026, 3, 5) // 周四
        XCTAssertEqual(DateRecognizer.findDates(in: "明天 休", baseDate: base, calendar: calendar).first?.date,
                       date(2026, 3, 6))
        XCTAssertEqual(DateRecognizer.findDates(in: "大后天 早", baseDate: base, calendar: calendar).first?.date,
                       date(2026, 3, 8))
    }

    func testNextWeekMonday() {
        // 2026-03-05 是周四；"下周一"应为 2026-03-09 的下一周，即 03-16
        let base = date(2026, 3, 5)
        let hits = DateRecognizer.findDates(in: "下周一 白班", baseDate: base, calendar: calendar)
        XCTAssertEqual(hits.first?.date, date(2026, 3, 16))
    }

    func testPlainWeekdayPicksNearestUpcomingIncludingToday() {
        // 周四说"周四"→ 当天；说"周五"→ 明天
        let base = date(2026, 3, 5)
        XCTAssertEqual(DateRecognizer.findDates(in: "周四 夜班", baseDate: base, calendar: calendar).first?.date,
                       date(2026, 3, 5))
        XCTAssertEqual(DateRecognizer.findDates(in: "周五 夜班", baseDate: base, calendar: calendar).first?.date,
                       date(2026, 3, 6))
    }

    // MARK: - 多日期与防误伤

    func testMultipleDatesSortedByPosition() {
        let hits = DateRecognizer.findDates(in: "3月1日早 3月2日中",
                                            baseDate: date(2026, 3, 10),
                                            calendar: calendar)
        XCTAssertEqual(hits.count, 2)
        XCTAssertLessThan(hits[0].nsRange.location, hits[1].nsRange.location)
        XCTAssertEqual(hits[0].date, date(2026, 3, 1))
        XCTAssertEqual(hits[1].date, date(2026, 3, 2))
    }

    func testTimeRangeDoesNotMisparseAsDate() {
        // "08:00-16:00" 不应被短横线日期模式误伤
        let hits = DateRecognizer.findDates(in: "08:00-16:00 张三",
                                            baseDate: date(2026, 6, 1),
                                            calendar: calendar)
        XCTAssertTrue(hits.isEmpty)
    }
}
