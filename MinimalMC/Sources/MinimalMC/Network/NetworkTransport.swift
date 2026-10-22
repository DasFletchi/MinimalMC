import Foundation
import Network

public class NetworkTransport {
    private var connection: NWConnection?
    private var isConnected = false
    private let queue = DispatchQueue(label: "com.jules.MinimalMC.network")
    private var encryption: PacketEncryption?
    private var compressionThreshold: Int?

    public var onReceive: ((Packet) -> Void)?
    public var onDisconnect: ((Error?) -> Void)?

    private var receiveBuffer = Data()

    public init() {}

    public func connect(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let parameters = NWParameters.tcp

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.receive()
            case .failed(let error):
                self?.isConnected = false
                self?.onDisconnect?(error)
            case .cancelled:
                self?.isConnected = false
                self?.onDisconnect?(nil)
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        encryption = nil
        compressionThreshold = nil
        receiveBuffer.removeAll()
    }

    public func send(packet: Packet) {
        queue.async {
            var framedData = PacketFraming.encode(packet, compressionThreshold: self.compressionThreshold)

            if let encryption = self.encryption {
                framedData = encryption.encrypt(framedData)
            }

            self.connection?.send(content: framedData, completion: .contentProcessed({ error in
                if let error = error {
                    print("Send error: \(error)")
                }
            }))
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.queue.async {
                    self.processReceivedData(data)
                }
            }

            if isComplete || error != nil {
                self.isConnected = false
                self.onDisconnect?(error)
            } else if self.isConnected {
                self.receive()
            }
        }
    }

    private func processReceivedData(_ data: Data) {
        var decryptedData = data
        if let encryption = encryption {
            decryptedData = encryption.decrypt(data)
        }

        receiveBuffer.append(decryptedData)

        while true {
            var snapshot = receiveBuffer
            do {
                if let packet = try PacketFraming.decode(from: &snapshot, compressionThreshold: compressionThreshold) {
                    receiveBuffer = snapshot

                    DispatchQueue.main.async {
                        self.onReceive?(packet)
                    }
                } else {
                    break // Need more data
                }
            } catch {
                print("Decode error: \(error)")
                disconnect()
                break
            }
        }
    }

    public func enableEncryption(sharedSecret: Data) {
        queue.async {
            self.encryption = PacketEncryption(sharedSecret: sharedSecret)
        }
    }

    public func setCompressionThreshold(_ threshold: Int) {
        queue.async {
            self.compressionThreshold = threshold
        }
    }
}
