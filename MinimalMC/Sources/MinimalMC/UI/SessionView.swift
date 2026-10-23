import SwiftUI

struct SessionActiveView: View {
    @ObservedObject var sessionManager = SessionManager.shared

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: sessionManager.totalDuration > 0 ? CGFloat(sessionManager.timeRemaining / sessionManager.totalDuration) : 0)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: sessionManager.timeRemaining)

                VStack {
                    Text(sessionManager.formattedTimeRemaining)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))

                    Text("Time Remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 200, height: 200)
            .padding(.top, 16)

            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                sessionManager.stopSession()
            }) {
                Text("Stop Session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .padding(.horizontal)

            NavigationLink(destination: DiagnosticsView()) {
                Text("View Diagnostics")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
    }
}

struct StatusView: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorForStatus(status))
                .frame(width: 8, height: 8)

            Text(textForStatus(status))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(colorForStatus(status))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(colorForStatus(status).opacity(0.15))
        )
    }

    private func colorForStatus(_ status: SessionStatus) -> Color {
        switch status {
        case .idle, .stopped: return .gray
        case .connecting, .authenticating, .loggingIn, .configuring: return .orange
        case .online, .backgroundTaskRunning: return .green
        case .reconnecting: return .yellow
        case .expired, .disconnected, .failed: return .red
        }
    }

    private func textForStatus(_ status: SessionStatus) -> String {
        switch status {
        case .idle: return "Idle"
        case .starting: return "Starting..."
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .loggingIn: return "Logging In..."
        case .configuring: return "Configuring..."
        case .online: return "Online"
        case .backgroundTaskRunning: return "Running in Background"
        case .reconnecting: return "Reconnecting..."
        case .expired: return "Session Expired"
        case .stopped: return "Session Stopped"
        case .disconnected(let reason): return "Disconnected: \(reason)"
        case .failed(let error): return "Failed: \(error)"
        }
    }
}
