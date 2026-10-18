import Foundation
import Observation
@preconcurrency import UserNotifications

@MainActor protocol MeetingNotificationDelivery: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }
    func status() async -> UNAuthorizationStatus
    func authorize() async throws -> Bool
    func pendingIDs() async -> [String]
    func deliveredIDs() async -> [String]
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
    func add(_ request: MeetingReminderRequest) async throws
}

final class SystemMeetingNotifications: MeetingNotificationDelivery {
    private let center = UNUserNotificationCenter.current()
    var delegate: (any UNUserNotificationCenterDelegate)? {
        get { center.delegate }
        set { center.delegate = newValue }
    }
    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func authorize() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func deliveredIDs() async -> [String] { await center.deliveredNotifications().map { $0.request.identifier } }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
    func add(_ request: MeetingReminderRequest) async throws {
        try await center.add(Self.notification(for: request))
    }
    static func notification(for request: MeetingReminderRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["meetingPlanID": request.id.uuidString]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: "notchnote.meeting." + request.id.uuidString, content: content, trigger: trigger)
    }
}

@Observable final class MeetingReminders: NSObject, UNUserNotificationCenterDelegate {
    private let store: NoteStore
    private let delivery: any MeetingNotificationDelivery
    private var syncTask: Task<Void, Never>?
    private var generation = 0
    private var syncing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var statusText = "提醒通过 macOS 通知发送。"
    var onOpen: ((UUID) -> Void)?
    private let prefix = "notchnote.meeting."

    init(store: NoteStore, delivery: (any MeetingNotificationDelivery)? = nil) {
        self.store = store
        self.delivery = delivery ?? SystemMeetingNotifications()
        super.init()
        self.delivery.delegate = self
        store.onSave = { [weak self] in self?.scheduleSync() }
        scheduleSync()
    }

    func enableAndSync() async {
        do {
            if await delivery.status() == .notDetermined { _ = try await delivery.authorize() }
            await synchronizeNow()
        } catch { statusText = "无法启用通知：\(error.localizedDescription)" }
    }

    func scheduleSync() {
        generation += 1
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.synchronizeNow()
        }
    }

    func synchronizeNow() async {
        generation += 1
        syncTask?.cancel()
        syncTask = nil
        if syncing {
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        syncing = true
        while true {
            let ticket = generation
            await sync(ticket: ticket)
            if ticket == generation { break }
        }
        syncing = false
        let completed = waiters
        waiters = []
        completed.forEach { $0.resume() }
    }

    private func sync(ticket: Int) async {
        let status = await delivery.status()
        let pending = await delivery.pendingIDs()
        guard ticket == generation else { return }
        let requests = MeetingReminderRequest.pending(plans: store.meetingPlans, sections: store.sections, now: .now)
        let wanted = Set(requests.map { prefix + $0.id.uuidString })
        let obsolete = pending.filter { $0.hasPrefix(prefix) && !wanted.contains($0) }
        delivery.removePending(obsolete)
        let delivered = await delivery.deliveredIDs()
        guard ticket == generation else { return }
        let activeIDs = Set(store.meetingPlans.filter { plan in
            guard let ref = store.reference(forLine: plan.lineIndex, in: plan.sectionID),
                  let line = store.resolve(ref) else { return false }
            return !line.isDone && plan.reminderMinutes != nil
        }.map { prefix + $0.id.uuidString })
        delivery.removeDelivered(delivered.filter {
            $0.hasPrefix(prefix) && (!activeIDs.contains($0) || wanted.contains($0))
        })
        guard status == .authorized || status == .provisional else {
            statusText = status == .denied
                ? "通知未允许。请在系统设置 → 通知 → NotchNote 中开启。"
                : "首次启用提醒时，macOS 会请求通知权限。"
            return
        }
        var failures = 0
        for request in requests {
            guard ticket == generation else { return }
            do { try await delivery.add(request)
            } catch { failures += 1 }
            if ticket != generation { return }
        }
        guard ticket == generation else { return }
        statusText = failures == 0 ? "通知已允许，已安排 \(requests.count) 条未来提醒。" : "有 \(failures) 条提醒未能安排，请稍后重试。"
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["meetingPlanID"] as? String,
              let id = UUID(uuidString: value) else { return }
        await MainActor.run { onOpen?(id) }
    }
}
