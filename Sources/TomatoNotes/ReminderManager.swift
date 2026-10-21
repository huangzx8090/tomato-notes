import AppKit
import UserNotifications

@MainActor
final class ReminderManager: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func refreshStatus() {
        center.getNotificationSettings { [weak self] settings in
            let message: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: message = "通知已允许；呈现方式受系统通知与专注模式影响"
            case .denied: message = "通知已关闭，计时仍可使用。可前往系统设置重新开启"
            case .notDetermined: message = "首次开始或测试提醒时申请通知权限"
            @unknown default: message = "通知授权状态未知"
            }
            DispatchQueue.main.async { self?.onStatus?(message) }
        }
    }

    func requestIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    DispatchQueue.main.async { self.refreshStatus() }
                }
            } else {
                DispatchQueue.main.async { self.refreshStatus() }
            }
        }
    }

    func send(title: String, body: String, sound: Bool, notification: Bool) {
        if sound { NSSound(named: "Tink")?.play() }
        guard notification else { return }
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
                    if allowed { self.enqueue(title: title, body: body) }
                    DispatchQueue.main.async { self.refreshStatus() }
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                self.enqueue(title: title, body: body)
            } else {
                DispatchQueue.main.async { self.refreshStatus() }
            }
        }
    }

    nonisolated private func enqueue(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let error else { return }
            let message = "通知未能发送：\(error.localizedDescription)；计时记录已保留"
            DispatchQueue.main.async { self?.onStatus?(message) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.onOpen?() }
        completionHandler()
    }
}
