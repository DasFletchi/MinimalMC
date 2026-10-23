import Foundation
import BackgroundTasks
import AVFoundation
import UIKit

public class BGTaskManager {
    public static let shared = BGTaskManager()
    private let taskIdentifier = "com.jules.MinimalMC.session"

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var audioPlayer: AVAudioPlayer?

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

    public func startBackgroundSession() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            guard let self = self else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1) else { return }
        let frameCount = AVAudioFrameCount(format.sampleRate * 10.0)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        for channel in 0..<Int(format.channelCount) {
            guard let channelData = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frameCount) {
                channelData[frame] = 0.0
            }
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("silence.wav")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.play()
        } catch {
            print("Failed to setup audio player: \(error)")
        }
    }

    public func stopBackgroundSession() {
        audioPlayer?.stop()
        audioPlayer = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }

        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
