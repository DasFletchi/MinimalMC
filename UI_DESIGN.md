# UI Design Document

## Design Principles
- **Native iOS Feel:** The app should feel like a built-in utility, utilizing standard iOS paradigms rather than trying to look like a game menu.
- **Focus:** The primary action is starting a session. Once a session is running, the focus shifts entirely to the time remaining and the status.
- **Honesty:** Status indicators are direct (Idle, Connecting, Running in Background, Failed). We do not claim features we cannot guarantee.

## Color Palette
- **Primary:** System Blue (for primary actions like Start)
- **Destructive:** System Red (for stopping a session or showing errors)
- **Status Colors:**
  - Gray (Idle)
  - Orange (Connecting/Authenticating)
  - Green (Online/Background)
  - Yellow (Reconnecting)
  - Red (Failed/Disconnected)
- **Backgrounds:** System Background (Adapts seamlessly to Light/Dark mode).

## Typography
- Uses default system fonts (San Francisco).
- Time remaining uses `.monospaced` design for tabular figures (prevents jittering as seconds tick down).
- Large dynamic type is supported throughout.

## Spacing and Components
- Consistent 16pt / 24pt padding based on standard HIG guidelines.
- Standard `NavigationView` and `Form` components for settings.
- Custom buttons use `ButtonStyle` modifiers to provide tactile feedback (opacity change on press).

## State Management Views
1. **Idle/Setup State:** Clean overview with duration selections.
2. **Active Session State:** Replaces the duration selection with a massive countdown timer and a Stop button.
3. **Diagnostics:** Pushed off to a secondary view to avoid cluttering the main screen.

## Dismissed Design Patterns
- **Glassmorphism/Heavy Blur:** Dismissed as it distracts from the utility nature of the app.
- **Custom Game-like Fonts:** Dismissed to maintain accessibility and native iOS aesthetic.
- **Dashboard approach:** We avoid putting metrics (Ping, Packet rates, etc.) on the main screen to keep cognitive load low. These exist only in the Diagnostics view.
