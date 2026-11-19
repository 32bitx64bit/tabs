# Tabs! for C-Cord

A native, 100% theme-compliant browser-style tab bar extension for [C-Cord](https://github.com/C-Cord/C-Cord-Client).

## Features

- **Native Retained Rendering**: Uses C-Cord's `ui.panel` Flexbox engine — zero per-frame IPC overhead, native hover badge-to-close swaps, and automatic workspace reflow.
- **100% Theme Compliant (Zero Hardcoded Colors)**: Uses C-Cord semantic theme tokens (`bg_primary`, `bg_secondary`, `bg_tertiary`, `border_subtle`, `divider`, `brand`, `danger`, `text_header`, `text_normal`, `text_muted`, etc.) resolved live per frame — automatically adapts to **Matte Graphite (Dark)**, **Warm Stone (Light)**, **Obsidian (AMOLED)**, custom `.theme` files, and third-party **QuickCSS** themes.
- **Full Target Support**: Channels, DMs, Group DMs, Forums, Threads (including uncached/inline threads), Servers, Friends, and Message Requests.
- **Live Badges**: Instant unread dots and mention count pills on background tabs, plus automatic read-state reconciliation.
- **Pinned Tabs**: Left-anchored tabs displaying a pin icon and full title, protected from accidental close and (with Pin Lock) from being overwritten by sidebar navigation.
- **Per-Tab History & Reopen Closed**: Per-tab Back/Forward history stack and LIFO recently-closed tab stack (up to 20 tabs).
- **Flexible Placement**: Defaults to `"top"` (above the chat header with seamless active-tab chrome) and live-switches between **Top**, **Below Header (`subheader`)**, and **Bottom** at runtime.

## Controls

| Action | Gesture |
| :--- | :--- |
| Switch tab | **Left-click** tab |
| Close tab | **Middle-click** tab or click **`×`** |
| Pin / Unpin tab | **Double-click** tab (or **Shift+Click**) |
| Tab actions (Pin, Move, History, Duplicate, Close Others/Right) | **Right-click** tab |
| Open channel / server / nav in new tab | **Middle-click** or **`Ctrl`/`Super`+Click** anywhere in C-Cord, or right-click → **Open in New Tab** |
| New tab (+ Quick Switcher) | Click **`+`** or **double-click** empty bar space (**Shift+Click `+`** to duplicate without Quick Switcher) |
| Reopen last closed tab | **Right-click `+`** |
| Scroll tab strip | **Mouse wheel** anywhere on bar (**Shift+Wheel** cycles active tab) |
| Settings & bar placement | Click **`⚙`** or **right-click** empty bar space |

### Slash Commands

- `/tabs new` — Open a new tab and trigger Quick Switcher
- `/tabs close` / `/tabs reopen` — Close active tab / reopen last closed tab
- `/tabs pin` / `/tabs dup` — Pin/unpin or duplicate active tab
- `/tabs next` / `/tabs prev` — Cycle active tab
- `/tabs left` / `/tabs right` — Reorder active tab
- `/tabs back` / `/tabs fwd` — Navigate active tab's Back/Forward history
- `/tabs slot <top|subheader|bottom>` — Move the tab bar live
- `/tabs compact` / `/tabs dedupe` / `/tabs settings` / `/tabs reset`

## Permissions (Class 2 Only — No System Access)

| Permission | Purpose |
| :--- | :--- |
| `ui.panel` | Render the tab bar and on-demand contextual action shelf |
| `navigation.write` | Switch channels, DMs, threads, guilds, views, and open Quick Switcher |
| `store.read` | Read channel names, kinds, muted flags, and unread/mention counts |
| `events.channels` | Track channel updates, deletions, mute changes, and guild load |
| `events.messages` | Refresh background tab unread/mention counters immediately (`channel_id` only; message text is never inspected) |

## Installation & Publishing

- **Install locally**: Copy this folder into C-Cord's `extensions/` directory (or pack as `.cce`/`.zip` and drag-and-drop onto C-Cord).
- **Release & publish to `plugins.c-cord.org`**: Run **Actions → Publish C-Cord Plugin → Run workflow** to pack `io.github.32bitx64bit.tabs-<version>.cce`, create GitHub Release `v<version>`, and optionally announce it to the C-Cord plugin catalog via GitHub OIDC.
- **Run unit tests (Lua 5.5)**:
  ```bash
  lua5.5 tests/run_tests.lua
  ```
