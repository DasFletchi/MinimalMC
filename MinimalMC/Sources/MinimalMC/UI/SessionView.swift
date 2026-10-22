import SwiftUI

struct SessionActiveView: View {
    @ObservedObject var sessionManager = SessionManager.shared

    var body: some View {
        VStack(spacing: 24) {
            if sessionManager.totalDuration == 0 {
                VStack {
                    Text("Unlimited")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))

                    Text("Session Duration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                VStack {
                    Text(sessionManager.formattedTimeRemaining)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))

                    Text("Time Remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()

                ProgressView(value: sessionManager.totalDuration - sessionManager.timeRemaining, total: sessionManager.totalDuration)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal)
            }

            Button("Stop Session") {
                sessionManager.stopSession()
            }
            .buttonStyle(DestructiveButtonStyle())

            NavigationLink(destination: DiagnosticsView()) {
                Text("View Diagnostics")
            }
            .padding(.top, 16)
        }
    }
}

struct StatusView: View {
    let status: SessionStatus

    var body: some View {
        HStack {
            Circle()
                .fill(colorForStatus(status))
                .frame(width: 12, height: 12)

            Text(textForStatus(status))
                .font(.headline)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
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

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
