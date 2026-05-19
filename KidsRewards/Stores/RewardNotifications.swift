import Foundation
import UserNotifications

struct RewardNotificationPlan: Equatable {
    let identifier: String
    let title: String
    let body: String
    let delay: TimeInterval
}

enum RewardNotifications {
    static let allowanceIdentifier = "kidsrewards.allowance"
    static let interestIdentifier = "kidsrewards.interest"
    static let approvalsIdentifier = "kidsrewards.approvals"

    static let minimumDelay: TimeInterval = 60

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func buildPlan(
        settings: RewardSettings,
        pendingApprovalCount: Int,
        now: Date = Date()
    ) -> [RewardNotificationPlan] {
        guard settings.notificationsEnabled else { return [] }

        var plans: [RewardNotificationPlan] = []

        if pendingApprovalCount > 0 {
            let suffix = pendingApprovalCount == 1 ? "" : "s"
            plans.append(
                RewardNotificationPlan(
                    identifier: approvalsIdentifier,
                    title: "Approval needed",
                    body: "\(pendingApprovalCount) request\(suffix) waiting in KidsRewards.",
                    delay: 2
                )
            )
        }

        if let allowance = recurringPlan(
            identifier: allowanceIdentifier,
            title: "Allowance ready",
            body: "Open KidsRewards to apply the scheduled allowance.",
            recurrence: settings.allowanceRecurrence,
            lastApplied: settings.lastAllowanceAppliedAt,
            now: now
        ) {
            plans.append(allowance)
        }

        if let interest = recurringPlan(
            identifier: interestIdentifier,
            title: "Vault interest ready",
            body: "Open KidsRewards to apply scheduled vault interest.",
            recurrence: settings.interestRecurrence,
            lastApplied: settings.lastInterestAppliedAt,
            now: now
        ) {
            plans.append(interest)
        }

        return plans
    }

    static func recurringDelay(
        recurrence: RewardTask.Recurrence,
        lastApplied: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimeInterval? {
        RecurrenceSchedule.delayUntilNextOccurrence(
            recurrence: recurrence,
            lastApplied: lastApplied,
            now: now,
            calendar: calendar
        ).map { max($0, minimumDelay) }
    }

    @MainActor
    static func reschedule(using store: RewardStore) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            allowanceIdentifier,
            interestIdentifier,
            approvalsIdentifier
        ])

        let plans = buildPlan(
            settings: store.state.settings,
            pendingApprovalCount: store.pendingApprovalCount
        )

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: plan.delay,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private static func recurringPlan(
        identifier: String,
        title: String,
        body: String,
        recurrence: RewardTask.Recurrence,
        lastApplied: Date?,
        now: Date
    ) -> RewardNotificationPlan? {
        guard let delay = recurringDelay(recurrence: recurrence, lastApplied: lastApplied, now: now) else {
            return nil
        }
        return RewardNotificationPlan(
            identifier: identifier,
            title: title,
            body: body,
            delay: delay
        )
    }
}
