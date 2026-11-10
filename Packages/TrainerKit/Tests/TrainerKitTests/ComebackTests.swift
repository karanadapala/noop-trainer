import XCTest
@testable import TrainerKit

final class ComebackTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ n: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: n, hour: hour))!
    }

    /// Sessions on odd days of the month only.
    private func odd(_ d: Date) -> Bool { cal.component(.day, from: d) % 2 == 1 }

    func testOnlyDaysWithASessionCountAsGapDays() {
        XCTAssertEqual(Comeback.gapDays(lastSeen: day(1), now: day(1, hour: 20), calendar: cal, isSessionDay: odd), 0)
        XCTAssertEqual(Comeback.gapDays(lastSeen: day(1), now: day(6), calendar: cal, isSessionDay: odd), 2, "the 3rd and 5th")
        XCTAssertEqual(Comeback.gapDays(lastSeen: day(1), now: day(6), calendar: cal) { _ in true }, 5)
    }

    func testTheLadderLandsOnCountedDaysAtTheSetTime() {
        let s = Comeback.schedule(lastSeen: day(1, hour: 20), options: GapOptions(), calendar: cal, isSessionDay: odd)
        XCTAssertEqual(s.map(\.step.message), [.allOK, .onHold, .freshStart, .stillHere])
        XCTAssertEqual(s[0].date, day(5, hour: 12), "2nd counted day: the 3rd, then the 5th")
        XCTAssertEqual(s[1].date, day(9, hour: 12))
        var off = GapOptions()
        off.enabled = false
        XCTAssertTrue(Comeback.schedule(lastSeen: day(1), options: off, calendar: cal, isSessionDay: odd).isEmpty)
    }

    func testMessagesStayKindAndSayTheNextStep() {
        XCTAssertEqual(GapMessage.allOK.body(days: 2, next: nil), "Haven't seen you for 2 days. All OK?")
        XCTAssertEqual(GapMessage.freshStart.body(days: 7, next: "Week 2 · Day 2"),
                       "New week, fresh start: Week 2 · Day 2, take two, can start today.")
        let banned = ["streak", "missed", "behind", "lost progress", "back on track", "no excuses", "push through"]
        for m in GapMessage.allCases {
            let text = m.body(days: 3, next: "X").lowercased()
            XCTAssertFalse(banned.contains { text.contains($0) }, m.rawValue)
        }
    }
}
