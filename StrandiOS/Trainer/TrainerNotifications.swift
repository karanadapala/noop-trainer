import Foundation
import TrainerKit
import UserNotifications

/// Trainer's local notifications: the gap ladder (D226), "When suits?" reminders (D231) and the morning
/// time budget (D229). Everything is on the phone; nothing leaves it. Ids and categories start with
/// `trainer.`, and NotificationPresenter hands their taps back here.
@MainActor
enum TrainerNotifications {
    static let gapCategory = "trainer.gap"
    static let morningCategory = "trainer.morning"
    static let reminderCategory = "trainer.reminder"

    enum Action: String {
        case ill = "trainer.ill", busy = "trainer.busy", tomorrow = "trainer.tomorrow", startNow = "trainer.start"
        case slot0 = "trainer.slot0", slot1 = "trainer.slot1", slot2 = "trainer.slot2"
    }

    /// Asks once, when a Trainer reminder is on and iOS hasn't been asked yet.
    static func requestIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Adds Trainer's categories to whatever the app already has.
    static func registerCategories(slots: [Int]) {
        let center = UNUserNotificationCenter.current()
        func act(_ a: Action, _ title: String, foreground: Bool = false) -> UNNotificationAction {
            UNNotificationAction(identifier: a.rawValue, title: title, options: foreground ? [.foreground] : [])
        }
        let slotActions = [Action.slot0, .slot1, .slot2].enumerated().compactMap { i, a in
            slots.indices.contains(i) ? act(a, MorningOptions.label(slots[i])) : nil
        }
        let mine: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: gapCategory + ".allOK",
                                   actions: [act(.ill, "Ill"), act(.busy, "Busy"), act(.tomorrow, "Back tomorrow")],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: gapCategory + ".onHold",
                                   actions: [act(.startNow, "Start now", foreground: true), act(.tomorrow, "Tomorrow"), act(.ill, "I'm ill")],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: morningCategory, actions: slotActions + [act(.ill, "I'm unwell")],
                                   intentIdentifiers: []),
        ]
        center.getNotificationCategories { existing in
            let others = existing.filter { !$0.identifier.hasPrefix("trainer.") }
            center.setNotificationCategories(others.union(mine))
        }
    }

    static func schedule(id: String, at date: Date, body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    static func cancel(prefix: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    /// "When suits?" (D231): one reminder `leadMinutes` before the chosen time today.
    static func remind(atMinuteOfDay m: Int, lead: Int, body: String, now: Date = Date()) {
        let cal = Calendar.current
        guard let at = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: now)?
            .addingTimeInterval(TimeInterval(-lead * 60)), at > now else { return }
        schedule(id: "trainer.reminder.\(m)", at: at, body: body, category: reminderCategory)
    }

    /// A tap on one of Trainer's notifications or its buttons.
    static func handle(category: String, actionID: String) {
        guard category.hasPrefix("trainer.") else { return }
        let action = Action(rawValue: actionID)
        if category.hasPrefix(gapCategory) {
            ComebackStore.shared.handle(action)
        } else if category == morningCategory {
            MorningBudget.shared.handle(action)
        }
    }
}
