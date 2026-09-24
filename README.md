# Boosteroid Rich Presence for Discord — macOS

A native menu-bar app that replaces Discord's generic **Playing Boosteroid** activity with the game currently being streamed.

[Download the latest macOS release](https://github.com/idiotsandwich93/Boosteroid-Rich-Presence/releases/latest)

## Requirements

- macOS 13 or newer
- Boosteroid's native macOS app
- Discord Desktop

## How it works

- Reads Boosteroid's local `bstr_client.log` to identify the active session.
- Falls back to Boosteroid's filtered Discord game title when its history API omits or delays an active session (observed with GTA V Enhanced).
- Uses the session's exact game name and original start time.
- Launches Boosteroid in **Presence Mode** through a local Discord activity filter.
- Filters Boosteroid's generic app identity.
- Gives every session a native-status handoff so the game or launcher can provide game modes and player counts without being overwritten by the app's basic card.
- Keeps Xbox, Epic, Steam, and other storefront suffixes as internal detection hints; they are never displayed in Discord.
- Matches the title against a bundled catalog of more than 24,000 Discord game profiles.
- Publishes a basic matched-game card through Discord's local desktop RPC socket when no supported native provider is selected.
- Clears the activity when the Boosteroid stream ends.

No Boosteroid login, Discord login, browser automation, screen recording, Accessibility permission, Steam cookie, or store credential is required. Discord Desktop must be running. Native status still depends on the individual game or launcher publishing Discord activity; some providers may require their corresponding account connection to already be configured in Discord.

## Use

1. Download and unzip `Boosteroid-Presence-macOS.zip` from the Releases page.
2. Move **Boosteroid Presence.app** to Applications.
3. Right-click the app, choose **Open**, then confirm **Open**. The first release is ad-hoc signed rather than Apple-notarized.
4. The app runs from the game-controller icon in the menu bar.
5. Quit Boosteroid if it is already running.
6. From the game-controller menu, choose **Open Boosteroid in Presence Mode**.
7. Keep Discord Desktop open, then start a game in Boosteroid.

**Prefer Native In-Game Status** is enabled by default for every game. Boosteroid Presence keeps suppressing Boosteroid's generic card but does not publish its own competing activity. If a game has no native status provider, turn this preference off to use the basic detected-game card instead.

Boosteroid must be opened from Boosteroid Presence each time. Opening Boosteroid normally bypasses the activity filter and gives its built-in **Playing Boosteroid** activity direct access to Discord again.

The menu shows the current detection and Presence Mode status and includes shortcuts to open Boosteroid safely, refresh Discord presence, open logs, and launch at login.

## Build

Run `swift test`, then `scripts/build_app.sh` on macOS 13 or newer. The app and distributable ZIP are written to `outputs/`.

## Privacy

Boosteroid Presence reads Boosteroid's local activity log and communicates with Discord Desktop through its local RPC socket. It does not request or store Boosteroid, Discord, Steam, Epic, Xbox, or Rockstar credentials.

## License

[MIT](LICENSE)
