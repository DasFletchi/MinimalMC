# MinimalMC

MinimalMC is a native, minimalist iOS Minecraft client MVP designed to maintain a connection to a Java server without rendering graphics or processing full chunks.

## Project Overview
This client is designed for background persistence using standard iOS APIs. It does not spawn heavy JVMs or Node.js runtimes. Everything is built natively in Swift using `NWConnection` for TCP transport and a custom Minecraft Protocol State Machine.

## Supported Versions
- **Minecraft Java Version:** 1.20.4
- **Protocol Number:** 765

## Features
- ✅ Native SwiftUI interface
- ✅ Swift Concurrency based Protocol State Machine
- ✅ Zlib Compression & CFB8-AES Encryption
- ✅ Handshake, Login, Configuration, and Play state handling
- ✅ Keep-Alive & Basic Movement/Teleport Confirm processing
- ✅ Best-effort background execution (BGProcessingTask and silent audio)
- ✅ Configurable Session Timers (30m, 2h, unlimited, custom)
- ✅ Keychain token storage interface

## Unsupported Features
- ❌ 3D World Rendering (No chunks or blocks)
- ❌ Entities & Inventory Management
- ❌ Chat & Command interface (MVP scope)
- Microsoft sign-in uses MinimalMC's built-in public application ID. Users only need a Microsoft account with a Minecraft Java license. Device-code → Xbox Live → XSTS → Minecraft exchange is implemented; full account authentication still needs device testing.

## System Requirements
- **OS:** iOS 15.0+
- **Xcode:** 15.0+

## Build Instructions
Since this project uses a Ruby script to generate the `.xcodeproj` file:
1. Ensure Ruby and the `xcodeproj` gem are installed.
2. Run `ruby generate_project.rb` in the project root.
3. Open `MinimalMC.xcodeproj` in Xcode.
4. For direct device installation, enable signing and select your Team. CI builds are unsigned.
5. Build and Run.

## Start Instructions
1. Launch the app.
2. Go to settings (gear icon) and configure your test server IP and Port.
3. Use offline mode for an offline-mode test server. For online-mode servers, tap **Sign in with Microsoft**, open the Microsoft sign-in page, enter the displayed code, and return to Settings until the app confirms your player name. No application ID or Azure registration is needed for end users.
4. Tap on a session duration on the main screen to begin.

## Architecture
- `NetworkTransport`: Wraps `NWConnection` for async TCP stream handling.
- `MinecraftSession`: Swift Actor managing protocol state machine and incoming packets.
- `SessionManager`: ObservableObject tracking time remaining and UI status.
- `BGTaskManager`: Manages `BGProcessingTask` to keep the connection alive when possible.

## Background execution limits
The app requests BGProcessingTask time and loops silent audio while a session is active. iOS may suspend or terminate the process; this does not guarantee hours of connectivity under screen lock. Silent audio is not a guarantee of App Store acceptance. Test background behavior on a real device.

## Download an IPA
GitHub Actions runs the native macOS protocol test suite and creates an unsigned arm64 device archive. Successful pushes to `main` publish a GitHub prerelease containing `MinimalMC-unsigned.ipa`; version tags (`v*`) create versioned releases. Pull requests upload IPA artifacts without publishing releases.

Sign the IPA with AltStore, SideStore, or your own signing setup before installing. No signing certificate is stored in the repository. Build/test logs are uploaded even when a build fails. The generated Xcode scheme also supports running the tests locally in an iOS simulator.

## UI Design Principles
- **Minimalist & Native:** Uses standard SwiftUI components to ensure it feels like a native iOS utility app.
- **Clarity over Flashiness:** Avoids excessive gradients, shadows, or "AI-powered" buzzwords.
- **Diagnostic Separation:** The main screen only shows what is necessary (Time remaining, Status, Stop button). Detailed packet info is relegated to the Diagnostics View.

## Testing
The workflow runs native macOS tests for codec, malformed-input, framing, compression, streaming-encryption, login-layout and TCP mock-server integration tests before archiving. The mock server sends Set Compression and Login Success in succession to exercise the decoding state change. The Swift package exposes the networking/protocol core for macOS tests; UIKit screens and background/session managers belong to the iOS app target.

These checks do not prove real-server compatibility, successful Microsoft account authorization, background longevity, or avoidance of server AFK rules.
