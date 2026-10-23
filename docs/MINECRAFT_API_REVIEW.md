# Minecraft API review draft

Status: prepared for owner review; NOT submitted or approved.

## Form fields
- Request type: New AppID for Approval
- Application name: MinimalMC
- Application (Client) ID: 83734d15-5ed1-4486-aa17-e84511d2250f
- Contact email and directory ID: confirm with the owner before sending; deliberately omitted from this repository document.
- Project reference: https://github.com/DasFletchi/MinimalMC (private; inaccessible to reviewers unless access is arranged)
- Official form: https://aka.ms/mce-reviewappid

## Justification
MinimalMC is an independent native Swift iOS client for Minecraft: Java Edition 1.20.4. It lets a licensed player maintain a timed, headless server connection without 3D rendering. It handles login, keep-alive and basic movement packets and offers optional reconnects. It is intended only for servers whose rules permit automated or AFK clients. It is not affiliated with or endorsed by Mojang or Microsoft.

We request approval for our own application ID to use the Microsoft device-code, Xbox Live, XSTS and Minecraft Services authentication flow. Before every initial connection and reconnect, the application obtains a Minecraft access token, queries the Java license entitlements endpoint and retrieves the account's valid Java profile. A confirmed Java entitlement and valid player profile are required before any server TCP connection or login packet is sent, regardless of the server's online-mode configuration. Empty, unrelated or malformed entitlements, failed service calls and invalid profiles block connection. There is no guest login, arbitrary player-name login, borrowed application ID or fallback that skips authentication or ownership verification. Online-mode server session join authorization remains enabled.

Passwords are entered only on Microsoft's sign-in page. Microsoft access and refresh tokens are stored in the iOS Keychain. Minecraft tokens are scoped to the in-memory connection. Signing out stops the session and deletes stored credentials. Diagnostic errors include the failing step and HTTP status without displaying response bodies or access tokens.

## Other information
The current application ID receives HTTP 403 (invalid app registration) from Minecraft Services. The production authentication and ownership checks are implemented, but an end-to-end successful live login cannot be validated until this application is approved. The automated suite uses synthetic HTTP responses and a loopback TCP mock server; test-only injected identities are excluded from the Release build. Accounts without a returned Java entitlement are denied, and subscription entitlement behavior has not yet been validated. This is an early prototype; background persistence and real-server compatibility are not guaranteed. The source repository is currently private; the repository URL is a project reference, not a publicly accessible review link. Additional review materials or access need to be arranged by the maintainer if required.

## Implementation evidence
- `Auth/MicrosoftAuth.swift`: own client ID, Microsoft/Xbox/Minecraft flow, entitlement and profile validation.
- `State/MinecraftSession.swift`: verification before TCP connection; player identity and join token from the verified account; stop invalidates pending authentication.
- `Session/SessionManager.swift`: all reconnects use the same gate; failed authentication stops the attempt.
- `UI/SettingsView.swift`: no Offline Mode or editable player name; sign-out stops the session.
- `AuthenticationTests.swift`, `AuthenticationGateTests.swift`, `MockServerTests.swift`: fail-closed ownership, no unauthenticated TCP connection, cancellation and verified identity.

## Owner acknowledgement before submission
The form requires the owner to confirm that they have read and understood the Minecraft EULA and all Usage Guidelines. This document does not make that acknowledgement on the owner's behalf. Confirm the contact email and tenant ID and review the final description before submission. A successful build is not Mojang approval.
