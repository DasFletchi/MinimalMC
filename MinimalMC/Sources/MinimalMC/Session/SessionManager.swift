import Foundation
import Combine
import UserNotifications

public class SessionManager: ObservableObject {
    public static let shared = SessionManager()

    @Published public var status: SessionStatus = .idle
    @Published public var timeRemaining: TimeInterval = 0
    @Published public var totalDuration: TimeInterval = 0
    @Published public var currentPingMs: Int = -1

    private var currentHost: String = ""
    private var currentPort: UInt16 = 0
    private var currentUsername: String = ""
    private var reconnectAttempt = 0
    private var isIntentionalDisconnect = false

    private var session: MinecraftSession?
    private var timer: Timer?
    private var targetEndDate: Date?

    public var onSessionEnded: (() -> Void)?

    private init() {}

    public func startSession(duration: TimeInterval, host: String, port: UInt16, username: String) {
        self.currentHost = host
        self.currentPort = port
        self.currentUsername = username
        self.isIntentionalDisconnect = false
        self.reconnectAttempt = 0

        self.totalDuration = duration
        if duration == 0 {
            self.timeRemaining = 0
            self.targetEndDate = nil
        } else {
            self.timeRemaining = duration
            self.targetEndDate = Date().addingTimeInterval(duration)
        }

        connect()
        startTimer()
        BGTaskManager.shared.scheduleTask()
    }

    private func connect() {
        session = MinecraftSession(serverHost: currentHost, serverPort: currentPort, username: currentUsername)

        session?.onPingUpdated = { [weak self] ping in
            DispatchQueue.main.async {
                self?.currentPingMs = ping
            }
        }

        session?.onStatusChanged = { [weak self] newStatus in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if case .disconnected = newStatus {
                    // Handled by onDisconnect, skip setting status directly to prevent UI flicker during reconnect
                } else if case .failed = newStatus {
                    // Handled by onDisconnect, skip setting status directly
                } else {
                    self.status = newStatus
                    if newStatus == .online {
                        self.reconnectAttempt = 0
                    }
                }
            }
        }

        session?.onDisconnect = { [weak self] reason in
            DispatchQueue.main.async {
                self?.handleDisconnect(reason: reason)
            }
        }

        session?.start()
    }

    private func handleDisconnect(reason: String) {
        let isBadCreds = reason.lowercased().contains("invalid credentials") || reason.lowercased().contains("banned")
        let autoReconnect = UserDefaults.standard.bool(forKey: "autoReconnect")

        if !isIntentionalDisconnect && !isBadCreds && autoReconnect {
            reconnect()
        } else {
            stopTimer()
            self.status = .disconnected(reason)
            onSessionEnded?()
        }
    }

    private func reconnect() {
        reconnectAttempt += 1
        if reconnectAttempt <= 3 {
            status = .reconnecting
            let delays = [2.0, 5.0, 10.0]
            let delay = delays[reconnectAttempt - 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.isIntentionalDisconnect else { return }
                self.session?.stop()
                self.connect()
            }
        } else {
            stopTimer()
            self.status = .disconnected("Failed to reconnect after 3 attempts")
            onSessionEnded?()
        }
    }

    public func stopSession() {
        isIntentionalDisconnect = true
        session?.stop()
        session = nil
        stopTimer()

        DispatchQueue.main.async {
            self.status = .stopped
            self.timeRemaining = 0
        }

        onSessionEnded?()
    }

    private func startTimer() {
        timer?.invalidate()
        if totalDuration == 0 { return } // Unlimited session

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let endDate = self.targetEndDate else { return }
            DispatchQueue.main.async {
                let remaining = endDate.timeIntervalSinceNow
                if remaining > 0 {
                    self.timeRemaining = remaining
                } else {
                    self.timeRemaining = 0
                    self.stopTimer()
                    self.isIntentionalDisconnect = true
                    self.session?.stop()
                    self.session = nil
                    self.status = .expired

                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        if granted {
                            let content = UNMutableNotificationContent()
                            content.title = "Session Expired"
                            content.body = "Your Minecraft session limit has been reached."
                            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                            UNUserNotificationCenter.current().add(request)
                        }
                    }

                    self.onSessionEnded?()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    public var formattedTimeRemaining: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = Int(timeRemaining) / 60 % 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02i:%02i:%02i", hours, minutes, seconds)
    }
}
