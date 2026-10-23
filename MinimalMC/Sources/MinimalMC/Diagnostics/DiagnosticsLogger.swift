import Foundation
import Combine

public struct PacketLogEntry: Identifiable {
    public let id = UUID()
    public let packetID: Int32
    public let size: Int
    public let timestamp: Date
    public let direction: String
    public let state: String
}

public class DiagnosticsLogger: ObservableObject {
    public static let shared = DiagnosticsLogger()

    @Published public var logs: [PacketLogEntry] = []

    private init() {}

    public func log(id: Int32, size: Int, direction: String, state: String) {
        let entry = PacketLogEntry(
            packetID: id,
            size: size,
            timestamp: Date(),
            direction: direction,
            state: state
        )
        DispatchQueue.main.async {
            self.logs.insert(entry, at: 0)
            if self.logs.count > 1000 {
                self.logs.removeLast()
            }
        }
    }
}
