import Foundation
import Combine

public class SessionManager: ObservableObject {
    public static let shared = SessionManager()

    @Published public var status: SessionStatus = .idle
    @Published public var timeRemaining: TimeInterval = 0
    @Published public var totalDuration: TimeInterval = 0

    private var session: MinecraftSession?
    private var timer: Timer?
    private var targetEndDate: Date?

    public var onSessionEnded: (() -> Void)?

    private init() {}

    public func startSession(duration: TimeInterval, host: String, port: UInt16, username: String) {
        self.totalDuration = duration
        self.timeRemaining = duration
        self.targetEndDate = Date().addingTimeInterval(duration)

        session = MinecraftSession(serverHost: host, serverPort: port, username: username)

        session?.onStatusChanged = { [weak self] newStatus in
            DispatchQueue.main.async {
                self?.status = newStatus
                if case .disconnected = newStatus {
                    self?.stopTimer()
                    self?.onSessionEnded?()
                } else if case .failed = newStatus {
                    self?.stopTimer()
                    self?.onSessionEnded?()
                }
            }
        }

        session?.start()
        startTimer()
        BGTaskManager.shared.scheduleTask()
    }

    public func stopSession() {
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let endDate = self.targetEndDate else { return }
            DispatchQueue.main.async {
                let remaining = endDate.timeIntervalSinceNow
                if remaining > 0 {
                    self.timeRemaining = remaining
                } else {
                    self.timeRemaining = 0
                    self.stopSession()
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
