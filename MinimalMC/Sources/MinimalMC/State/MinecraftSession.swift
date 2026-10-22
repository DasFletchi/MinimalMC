import Foundation
import CryptoKit
import Security

public enum SessionStatus: Equatable {
    case idle
    case starting
    case connecting
    case authenticating
    case loggingIn
    case configuring
    case online
    case backgroundTaskRunning
    case reconnecting
    case expired
    case stopped
    case disconnected(String)
    case failed(String)
}

public actor MinecraftSession {
    public let transport = NetworkTransport()
    public var status: SessionStatus = .idle
    private var currentState: ProtocolState = .handshake

    // For 1.20.4
    private let protocolVersion: Int32 = 765

    private let serverHost: String
    private let serverPort: UInt16
    private let username: String
    private let uuid: UUID?

    public var onStatusChanged: ((SessionStatus) -> Void)?
    public var onDisconnect: ((String) -> Void)?

    public init(serverHost: String, serverPort: UInt16, username: String, uuid: UUID? = nil) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.username = username
        self.uuid = uuid
    }

    public func start() {
        updateStatus(.connecting)

        transport.onReceive = { [weak self] packet in
            Task {
                await self?.handlePacket(packet)
            }
        }

        transport.onDisconnect = { [weak self] error in
            Task {
                await self?.handleDisconnect(error)
            }
        }

        transport.connect(host: serverHost, port: serverPort)

        // After connect, initiate handshake
        Task {
            do {
                let handshake = try HandshakePacket.create(protocolVersion: protocolVersion, serverAddress: serverHost, serverPort: serverPort, nextState: .login)
                transport.send(packet: handshake)

                currentState = .login
                updateStatus(.loggingIn)

                let loginStart = try LoginStartPacket.create(username: username, uuid: uuid)
                transport.send(packet: loginStart)
            } catch {
                updateStatus(.failed("Failed to send handshake: \(error.localizedDescription)"))
                transport.disconnect()
            }
        }
    }

    public func stop() {
        updateStatus(.stopped)
        transport.disconnect()
    }

    private func handleDisconnect(_ error: Error?) {
        if let error = error {
            updateStatus(.failed(error.localizedDescription))
            onDisconnect?(error.localizedDescription)
        } else {
            updateStatus(.disconnected("Disconnected by server"))
            onDisconnect?("Disconnected by server")
        }
    }

    private func handlePacket(_ packet: Packet) {
        do {
            var data = packet.data

            switch currentState {
            case .login:
                switch packet.packetID {
                case 0x00: // Disconnect
                    // In 1.20.4, disconnect reasons are NBT formatted Text Components, not VarInt Strings.
                    // For minimal MVP, we safely skip parsing the full NBT to avoid crashes and display a generic message.
                    let reason = "Disconnected by server during login"
                    updateStatus(.disconnected(reason))
                    transport.disconnect()
                case 0x01: // Encryption Request
                    let serverId = try DataTypes.readString(from: &data)
                    let pubKeyLen = try VarInt.read(from: &data)
                    let publicKeyData = data.prefix(Int(pubKeyLen))
                    data.removeFirst(Int(pubKeyLen))
                    let tokenLen = try VarInt.read(from: &data)
                    let verifyTokenData = data.prefix(Int(tokenLen))

                    // Generate shared secret
                    let sharedSecret = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

                    // RSA Encryption using Security framework
                    let keyDict: [CFString: Any] = [
                        kSecAttrKeyType: kSecAttrKeyTypeRSA,
                        kSecAttrKeyClass: kSecAttrKeyClassPublic
                    ]

                    var error: Unmanaged<CFError>?
                    guard let secKey = SecKeyCreateWithData(publicKeyData as CFData, keyDict as CFDictionary, &error) else {
                        updateStatus(.failed("Failed to parse RSA public key"))
                        transport.disconnect()
                        return
                    }

                    guard let encryptedSecret = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, sharedSecret as CFData, &error),
                          let encryptedVerifyToken = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, verifyTokenData as CFData, &error) else {
                        updateStatus(.failed("Failed to encrypt secret/token"))
                        transport.disconnect()
                        return
                    }

                    // Call MS auth mock
                    // In a real app we need the accessToken from MicrosoftAuth
                    // and we generate the server hash using SHA-1
                    let serverHash = "mocked-hash"

                    MicrosoftAuth.shared.joinServer(accessToken: "mocked-token", selectedProfile: "mocked-uuid", serverHash: serverHash) { success in
                        Task {
                            // Send Encryption Response
                            let response = try EncryptionResponsePacket.create(sharedSecret: encryptedSecret as Data, verifyToken: encryptedVerifyToken as Data)
                            self.transport.send(packet: response)
                            self.transport.enableEncryption(sharedSecret: sharedSecret)
                        }
                    }

                case 0x02: // Login Success
                    // After 1.20.2, goes to Configuration state
                    currentState = .configuration
                    updateStatus(.configuring)
                    let ack = Packet(packetID: 0x03, data: Data()) // Login Acknowledged
                    transport.send(packet: ack)
                case 0x03: // Set Compression
                    let threshold = try VarInt.read(from: &data)
                    transport.setCompressionThreshold(Int(threshold))
                default:
                    break
                }
            case .configuration:
                switch packet.packetID {
                case 0x00: // Clientbound Plugin Message
                    if let channel = try? DataTypes.readString(from: &data), channel == "minecraft:brand" {
                        var responseData = Data()
                        try? DataTypes.writeString("minecraft:brand", to: &responseData)
                        try? DataTypes.writeString("MinimalMC", to: &responseData)
                        let responsePacket = Packet(packetID: 0x00, data: responseData)
                        transport.send(packet: responsePacket)
                    }
                case 0x01: // Disconnect
                    let reason = "Disconnected by server during configuration"
                    updateStatus(.disconnected(reason))
                    transport.disconnect()
                case 0x02: // Finish Configuration
                    let ack = Packet(packetID: 0x02, data: Data()) // Acknowledge Finish Configuration
                    transport.send(packet: ack)
                    currentState = .play
                    updateStatus(.online)
                case 0x03: // Keep Alive
                    var responseData = Data()
                    responseData.append(data)
                    let keepAliveResponse = Packet(packetID: 0x03, data: responseData)
                    transport.send(packet: keepAliveResponse)
                case 0x04: // Ping
                    var responseData = Data()
                    responseData.append(data)
                    let pongResponse = Packet(packetID: 0x04, data: responseData)
                    transport.send(packet: pongResponse)
                case 0x05: // Registry Data
                    break
                case 0x07: // Update Tags
                    break
                default:
                    break
                }
            case .play:
                switch packet.packetID {
                case 0x24: // Keep Alive (1.20.4)
                    let keepAliveID = try DataTypes.readLong(from: &data)
                    let response = KeepAlivePacket.create(keepAliveID: keepAliveID)
                    transport.send(packet: response)
                case 0x3E: // Synchronize Player Position (1.20.4)
                    // Skip x, y, z, yaw, pitch, flags to get teleport ID
                    let _ = try DataTypes.readLong(from: &data) // x
                    let _ = try DataTypes.readLong(from: &data) // y
                    let _ = try DataTypes.readLong(from: &data) // z
                    let _ = data.removeFirst(4) // yaw
                    let _ = data.removeFirst(4) // pitch
                    let _ = data.removeFirst(1) // flags
                    let teleportID = try VarInt.read(from: &data)

                    let confirm = TeleportConfirmPacket.create(teleportID: teleportID)
                    transport.send(packet: confirm)
                case 0x1B: // Disconnect (1.20.4)
                    let reason = "Disconnected by server during play"
                    updateStatus(.disconnected(reason))
                    transport.disconnect()
                default:
                    // Ignore unhandled packets
                    break
                }
            default:
                break
            }
        } catch {
            print("Packet handling error: \(error)")
        }
    }

    private func updateStatus(_ newStatus: SessionStatus) {
        self.status = newStatus
        DispatchQueue.main.async {
            self.onStatusChanged?(newStatus)
        }
    }
}
