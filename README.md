# MinimalMC

MinimalMC is a fully local, minimalist iOS Minecraft client MVP designed to maintain a connection to a Java server without rendering graphics or processing full chunks.

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
- ✅ Basic Background execution (`BGContinuedProcessingTask`)
- ✅ Configurable Session Timers (30m, 2h, 4h, Custom)
- ✅ Keychain token storage interface

## Unsupported Features
- ❌ 3D World Rendering (No chunks or blocks)
- ❌ Entities & Inventory Management
- ❌ Chat & Command interface (MVP scope)
- ❌ Real Microsoft Auth (Requires valid API credentials & XSTS flow; MVP provides mock interface)

## System Requirements
- **OS:** iOS 15.0+
- **Xcode:** 13.0+

## Build Instructions
Since this project uses a Ruby script to generate the `.xcodeproj` file:
1. Ensure Ruby and the `xcodeproj` gem are installed.
2. Run `ruby generate_project.rb` in the project root.
3. Open `MinimalMC.xcodeproj` in Xcode.
4. Select your Team in Signing & Capabilities.
5. Build and Run.

## Start Instructions
1. Launch the app.
2. Go to settings (gear icon) and configure your test server IP and Port.
3. Select "Sign in with Microsoft" (currently mocks auth).
4. Tap on a session duration on the main screen to begin.

## Architecture
- `NetworkTransport`: Wraps `NWConnection` for async TCP stream handling.
- `MinecraftSession`: Swift Actor managing protocol state machine and incoming packets.
- `SessionManager`: ObservableObject tracking time remaining and UI status.
- `BGTaskManager`: Manages `BGContinuedProcessingTask` to keep the connection alive when possible.

## BGContinuedProcessingTask Explanation
iOS strictly manages background execution. `BGContinuedProcessingTask` allows the app to request additional background time for long-running tasks. However, **this does NOT guarantee 2 or 4 hours of execution while the screen is locked.**
The operating system may terminate the task based on battery state, thermal limits, or memory pressure. If the system rejects or expires the task, the app will gracefully disconnect and save its state.

## UI Design Principles
- **Minimalist & Native:** Uses standard SwiftUI components to ensure it feels like a native iOS utility app.
- **Clarity over Flashiness:** Avoids excessive gradients, shadows, or "AI-powered" buzzwords.
- **Diagnostic Separation:** The main screen only shows what is necessary (Time remaining, Status, Stop button). Detailed packet info is relegated to the Diagnostics View.

## Testing Status
Unit tests have been written for:
- VarInt / VarLong / UTF8 String Encoding
- Packet Framing
- Compression & Encryption routines
- Protocol State Packet Definitions
- Session Timer Logic

*Note: Due to lack of a Swift/Xcode toolchain in the provided Linux container environment, all test execution results are explicitly marked as "not executed". The `swift test` command is not available, and therefore the unit tests could not be run.*
