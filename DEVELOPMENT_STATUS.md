# Development status

## Implemented
- Native SwiftUI iOS client for Minecraft Java 1.20.4 (protocol 765).
- Microsoft device-code sign-in, Xbox Live, XSTS and Minecraft token exchange.
- Fresh Java entitlement and profile validation before every connection/reconnect.
- No unauthenticated/guest/offline identity mode or editable player identity.
- Minecraft session credentials remain in memory; Microsoft credentials use Keychain.
- Sign-out stops the current connection and clears current and legacy credentials.
- GitHub Actions tests, unsigned device archive and IPA release publishing.

## Validation
The macOS suite covers protocol handling, an isolated TCP mock server, staged login errors, missing/wrong/revoked entitlements, malformed profiles, legacy offline settings and cancellation before connection. Test-only account injection is excluded from Release builds. The workflow also compiles the production iOS UI and session manager in a Release archive.

CI results are linked from each commit and release. Mock tests do not prove a successful live Microsoft/Minecraft login or real-server compatibility.

## Open blockers
- The registered application ID is currently rejected by Minecraft Services with HTTP 403 (invalid app registration). Mojang review has not been submitted or approved.
- Complete the EULA/Usage Guidelines acknowledgement and submit the prepared review request after the owner confirms the contact details and submission.
- The GitHub repository is private. Reviewers cannot inspect it without access; the request must disclose that limitation or provide separate review materials.
- Real-device login and server testing remain necessary after approval.
- Accounts without a returned Java entitlement are blocked; subscription entitlement behavior remains unverified.
- iOS background session duration is best effort, not guaranteed.

See [the review draft](docs/MINECRAFT_API_REVIEW.md) for the app description and implementation evidence.
