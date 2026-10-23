import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var logger = DiagnosticsLogger.shared
    @State private var selectedFilter: String = "All"

    let filters = ["All", "login", "configuration", "play"]

    var filteredLogs: [PacketLogEntry] {
        if selectedFilter == "All" {
            return logger.logs
        }
        return logger.logs.filter { $0.state == selectedFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Packet State", selection: $selectedFilter) {
                ForEach(filters, id: \.self) { filter in
                    Text(filter.capitalized).tag(filter)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            List {
                Section(header: Text("Session Details")) {
                    DiagnosticRow(title: "Status", value: String(describing: sessionManager.status))
                    DiagnosticRow(title: "Time Remaining", value: sessionManager.formattedTimeRemaining)
                    DiagnosticRow(title: "Total Duration", value: "\(Int(sessionManager.totalDuration))s")
                }

                Section(header: Text("Packet Log")) {
                    if filteredLogs.isEmpty {
                        Text("No packets logged yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredLogs) { log in
                            PacketLogRow(log: log)
                        }
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PacketLogRow: View {
    let log: PacketLogEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.direction == "In" ? "↓ In" : "↑ Out")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(log.direction == "In" ? .green : .blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((log.direction == "In" ? Color.green : Color.blue).opacity(0.1))
                        )

                    Text("ID: 0x\(String(format: "%02X", log.packetID))")
                        .font(.system(.subheadline, design: .monospaced))
                }

                Text(log.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Text("\(log.size) B")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
