import Foundation
import BackgroundTasks

public class BGTaskManager {
    public static let shared = BGTaskManager()
    private let taskIdentifier = "com.jules.MinimalMC.session"

    private init() {}

    public func register() {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
                self.handleTask(task: task as! BGProcessingTask)
            }
        }
    }

    @available(iOS 13.0, *)
    private func handleTask(task: BGProcessingTask) {
        task.expirationHandler = {
            // Cancel background work
            SessionManager.shared.stopSession()
            task.setTaskCompleted(success: false)
        }

        // Wait for session to complete
        SessionManager.shared.onSessionEnded = {
            task.setTaskCompleted(success: true)
        }
    }

    public func scheduleTask() {
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: taskIdentifier)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                print("Could not schedule app task: \(error)")
            }
        }
    }
}
