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
            var packetData = Data()
            VarInt.write(packet.packetID, to: &packetData)
            packetData.append(packet.data)

            if let threshold = self.compressionThreshold {
                packetData = PacketCompression.compress(packetData, threshold: threshold)
            }

            var framedData = Data()
            VarInt.write(Int32(packetData.count), to: &framedData)
            framedData.append(packetData)

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
                if let packet = try PacketFraming.decode(from: &snapshot) {
                    receiveBuffer = snapshot

                    var packetData = packet.data
                    if compressionThreshold != nil {
                        packetData = try PacketCompression.decompress(from: &packetData)
                    }

                    let packetID = try VarInt.read(from: &packetData)
                    let decodedPacket = Packet(packetID: packetID, data: packetData)

                    DispatchQueue.main.async {
                        self.onReceive?(decodedPacket)
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
