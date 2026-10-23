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
    public nonisolated let transport = NetworkTransport()
    public var status: SessionStatus = .idle
    private var currentState: ProtocolState = .handshake

    // For 1.20.4
    private let protocolVersion: Int32 = 765

    private let serverHost: String
    private let serverPort: UInt16

    private let username: String
    private let uuid: UUID?

    // Position Tracking
    private var currentX: Double = 0
    private var currentY: Double = 0
    private var currentZ: Double = 0
    private var currentYaw: Float = 0
    private var currentPitch: Float = 0

    // Anti-AFK
    private var antiAfkTask: Task<Void, Never>?


    public var onStatusChanged: ((SessionStatus) -> Void)?
    public var onDisconnect: ((String) -> Void)?

    public init(serverHost: String, serverPort: UInt16, username: String, uuid: UUID? = nil) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.username = username
        self.uuid = uuid
    }

    public func setCallbacks(onStatusChanged: ((SessionStatus) -> Void)? = nil, onDisconnect: ((String) -> Void)? = nil) {
        self.onStatusChanged = onStatusChanged
        self.onDisconnect = onDisconnect
    }

    public func start() {
        updateStatus(.connecting)

        transport.onReceive = { [weak self] packet in
            await self?.handlePacket(packet)
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
                self.sendPacket(handshake)

                currentState = .login
                updateStatus(.loggingIn)

                let loginStart = try LoginStartPacket.create(username: username, uuid: uuid)
                self.sendPacket(loginStart)
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
        DiagnosticsLogger.shared.log(id: packet.packetID, size: packet.data.count + 1, direction: "In", state: "\(currentState)")
        do {
            var data = packet.data

            switch currentState {
            case .login:
                switch packet.packetID {
                case 0x00: // Disconnect
                    // In 1.20.4, disconnect reasons are NBT formatted Text Components, not VarInt Strings.
                    // We attempt to read the string (JSON), and fallback to generic error.
                    let reason = (try? DataTypes.readString(from: &data)) ?? "Disconnected by server during login"
                    updateStatus(.disconnected(reason))
                    transport.disconnect()
                case 0x01: // Encryption Request
                    let serverId = try DataTypes.readString(from: &data)
                    let pubKeyLen = try VarInt.read(from: &data)
                    guard pubKeyLen > 0, pubKeyLen <= data.count else { throw ProtocolError.insufficientData }
                    let publicKeyData = data.prefix(Int(pubKeyLen))
                    data.removeFirst(Int(pubKeyLen))
                    let tokenLen = try VarInt.read(from: &data)
                    guard tokenLen > 0, tokenLen <= data.count else { throw ProtocolError.insufficientData }
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

                    let serverHash = MojangServerHash.generate(serverId: serverId, sharedSecret: sharedSecret, publicKey: publicKeyData)
                    guard let profileId = self.uuid?.uuidString, let accessToken = KeychainManager.shared.loadToken(for: "minecraft_access_token") else {
                        updateStatus(.failed("Sign in with Microsoft before joining an online-mode server"))
                        transport.disconnect()
                        return
                    }

                    MojangJoin.joinServer(accessToken: accessToken, selectedProfile: profileId, serverHash: serverHash) { success in
                        Task {
                            guard success else {
                                await self.authenticationFailed()
                                return
                            }
                            // Send Encryption Response
                            let response = try EncryptionResponsePacket.create(sharedSecret: encryptedSecret as Data, verifyToken: encryptedVerifyToken as Data)
                            self.sendPacket(response)
                            self.transport.enableEncryption(sharedSecret: sharedSecret)
                        }
                    }

                case 0x02: // Login Success
                    // After 1.20.2, goes to Configuration state
                    currentState = .configuration
                    updateStatus(.configuring)
                    let ack = Packet(packetID: 0x03, data: Data()) // Login Acknowledged
                    self.sendPacket(ack)
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
                    self.sendPacket(ack)
                    currentState = .play
                    updateStatus(.online)
                case 0x03: // Keep Alive
                    var responseData = Data()
                    responseData.append(data)
                    let keepAliveResponse = Packet(packetID: 0x03, data: responseData)
                    self.sendPacket(keepAliveResponse)
                case 0x04: // Ping
                    var responseData = Data()
                    responseData.append(data)
                    let pongResponse = Packet(packetID: 0x04, data: responseData)
                    self.sendPacket(pongResponse)
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
                    self.sendPacket(response)
                case 0x3E: // Synchronize Player Position (1.20.4)
                    let x = try DataTypes.readDouble(from: &data)
                    let y = try DataTypes.readDouble(from: &data)
                    let z = try DataTypes.readDouble(from: &data)
                    let yaw = try DataTypes.readFloat(from: &data)
                    let pitch = try DataTypes.readFloat(from: &data)
                    guard !data.isEmpty else { throw ProtocolError.insufficientData }
                    let flags = data.removeFirst()
                    let teleportID = try VarInt.read(from: &data)

                    if (flags & 0x01) != 0 { currentX += x } else { currentX = x }
                    if (flags & 0x02) != 0 { currentY += y } else { currentY = y }
                    if (flags & 0x04) != 0 { currentZ += z } else { currentZ = z }
                    if (flags & 0x08) != 0 { currentYaw += yaw } else { currentYaw = yaw }
                    if (flags & 0x10) != 0 { currentPitch += pitch } else { currentPitch = pitch }

                    let confirm = TeleportConfirmPacket.create(teleportID: teleportID)
                    self.sendPacket(confirm)

                    let posRot = PlayerPositionAndRotationPacket.create(x: currentX, y: currentY, z: currentZ, yaw: currentYaw, pitch: currentPitch, onGround: true)
                    self.sendPacket(posRot)
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

    private func authenticationFailed() {
        updateStatus(.failed("Minecraft session authentication failed"))
        transport.disconnect()
    }

    private func sendPacket(_ packet: Packet) {
        DiagnosticsLogger.shared.log(id: packet.packetID, size: packet.data.count + 1, direction: "Out", state: "\(currentState)")
        transport.send(packet: packet)
    }

    private func updateStatus(_ newStatus: SessionStatus) {
        self.status = newStatus
        let callback = onStatusChanged
        DispatchQueue.main.async { callback?(newStatus) }

        if newStatus == .online {
            startAntiAfkLoop()
        } else {
            antiAfkTask?.cancel()
            antiAfkTask = nil
        }
    }

    private func startAntiAfkLoop() {
        antiAfkTask?.cancel()
        antiAfkTask = Task { [weak self] in
            while !Task.isCancelled {
                // Configurable timer (e.g. 45 seconds)
                try? await Task.sleep(nanoseconds: 45 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                if let self = self {
                    let packet = await self.createAntiAfkPacket()
                    await self.transport.send(packet: packet)
                } else {
                    break
                }
            }
        }
    }

    private func createAntiAfkPacket() -> Packet {
        // Send Set Player Position update with onGround = true to avoid kicks
        return PlayerPositionPacket.create(x: currentX, y: currentY, z: currentZ, onGround: true)
    }
}
