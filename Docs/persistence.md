# Persistence design

Status: Proposed

## Storage

Use `%LOCALAPPDATA%\HVP`:

```text
HVP/
|-- settings.json
|-- history.json
|-- logs/                 # bounded diagnostic logs, paths redacted
`-- corrupt/              # quarantined unreadable files, bounded retention
```

No registry, roaming profile, cloud sync, account, or media sidecar file is required for V1.

## Settings

The versioned settings document may include volume/mute, seek intervals, language priority, subtitle preference, passthrough profile, last window bounds/state, diagnostics level, and future schema version. Defaults live in code and missing fields remain forward-compatible.

## Playback history

Identify a file with a privacy-preserving stable key derived from normalized absolute path, file size, and last-write timestamp. Store position, duration, updated UTC time, completion state, and remembered normalized track hints. Do not store media titles or raw paths unless a later user-facing history feature requires and discloses it.

Recommended V1 policy:

- Begin saving after 60 seconds of playback.
- Save periodically at a low frequency and on pause, stop, end, file change, and app close.
- Resume only when saved position is meaningful and below 95% of duration.
- Mark complete at or above 95%; reopen completed items from the start.
- Bound history by age/count and clean it opportunistically.

## Reliability

- Serialize a complete snapshot to a same-directory temporary file, flush, then atomically replace the destination.
- Enforce one writer per file and coalesce rapid progress updates.
- Validate schema and ranges before applying values.
- On malformed JSON, quarantine the file with a timestamp, restore defaults, and keep playback usable.
- Migrations are monotonic, deterministic, and unit tested from every supported schema.

## Privacy and diagnostics

History remains local. Logs use hashes or filenames only when necessary and omit full paths by default. A diagnostics export lists exactly what it will include and requires explicit user action.

## Acceptance criteria

- Abrupt termination during a write does not destroy the last valid settings/history.
- Corrupt or future-version files do not prevent startup.
- Resume/completion behavior matches boundary tests.
- Renamed, replaced, or changed files do not incorrectly inherit stale playback state.
- No network access or raw-path logging occurs.
