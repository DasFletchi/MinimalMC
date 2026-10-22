import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var sessionManager = SessionManager.shared

    var body: some View {
        List {
            Section(header: Text("Session Details")) {
                DiagnosticRow(title: "Status", value: String(describing: sessionManager.status))
                DiagnosticRow(title: "Time Remaining", value: sessionManager.formattedTimeRemaining)
                DiagnosticRow(title: "Total Duration", value: "\(Int(sessionManager.totalDuration))s")
            }

            Section(header: Text("Network (Mock)")) {
                DiagnosticRow(title: "Packets Sent", value: "0") // Connect to real counters in NetworkTransport
                DiagnosticRow(title: "Packets Received", value: "0")
                DiagnosticRow(title: "Last KeepAlive", value: sessionManager.currentPingMs >= 0 ? "\(sessionManager.currentPingMs) ms" : "N/A")
            }
        }
        .navigationTitle("Diagnostics")
    }
}

struct DiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }
}
