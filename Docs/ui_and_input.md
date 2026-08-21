# UI and input design

Status: Proposed

## Goal

Keep the movie dominant and the controls predictable. The user should be able to open a file and begin playback without configuring the app.

## Window layout

The main window has two non-overlapping regions:

1. A black native video surface hosted through `HwndHost`.
2. A compact WPF control bar below it containing transport, seek, audio/subtitle selectors, volume, fullscreen, open-file, and stream status.

WPF controls must not be drawn over the native surface because `HwndHost` has airspace, clipping, opacity, and input limitations. Any future overlay requires a separately reviewed top-level-window design.

## States

- `Empty`: centered Open File action plus drag/drop affordance.
- `Opening`: retained shell with progress indicator; controls that require media are disabled.
- `Playing` / `Paused`: control bar available; auto-hide may be evaluated only after keyboard/focus behavior is proven.
- `Ended`: replay and open-file remain available.
- `Error`: concise message, recovery action, and diagnostics link; no crash dialog for expected media errors.

## Controls and behavior

- Play/pause toggles the current state.
- Seek shows elapsed and duration; dragging previews the target time and commits at an intentionally bounded rate.
- Volume uses 0-100 UI units, exposes mute, and persists globally.
- Audio and subtitle selectors show language, title, codec/type, default/forced status, and external/embedded origin when available.
- Subtitle selector always includes Off.
- Status uses examples such as `HDR10 • 2160p • HEVC 10-bit` and exposes detailed diagnostics without claiming facts that are unknown.
- Open File uses a local file dialog and supports drag/drop of one file. Multiple-file playlist semantics are out of scope.

## Keyboard

| Key | Action |
| --- | --- |
| Space | Play/pause |
| Left / Right | Seek backward/forward by the configured short interval |
| F | Toggle fullscreen |
| Escape | Exit fullscreen; otherwise no destructive action |
| S | Cycle subtitle track, including Off |
| A | Cycle audio track |
| Ctrl+O | Open file |
| Up / Down | Adjust volume |
| M | Toggle mute |

Keyboard handling belongs at the WPF window boundary so focus in the native child HWND does not swallow global playback shortcuts. Do not override text-entry or dialog keyboard behavior.

## Fullscreen and monitors

- Save and restore the normal window bounds/state.
- Use the monitor containing the window at the moment fullscreen begins.
- Re-query display/HDR facts after monitor, DPI, display mode, or session changes.
- Keep the pointer and controls visible long enough for discoverability; do not trap focus.

## Accessibility and visual rules

- Every icon has an accessible name and tooltip.
- All actions are reachable by keyboard with visible focus.
- Do not encode SDR/HDR or error state by color alone.
- Support Windows scaling and high contrast; test 100%, 150%, and 200% DPI.
- Minimum hit targets and text contrast should follow current Windows accessibility guidance.
- Animation is subtle and respects reduced-motion settings where applicable.

## Acceptance criteria

- A user can open, control, switch tracks, inspect status, enter/leave fullscreen, and recover from an open error without a mouse.
- Controls never disappear behind or flicker against the native surface.
- Resizing and monitor movement do not stretch aspect ratio or leave a stale video window.
- The interface remains minimal at 1280x720 and scales correctly on 4K high-DPI displays.
