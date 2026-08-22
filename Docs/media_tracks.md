# Audio and subtitle design

Status: Proposed

## Unified track model

Both embedded and external tracks are represented with a stable per-open ID, type, language, title, codec/format, default flag, forced flag, hearing-impaired/commentary hints when available, and origin. Native IDs remain internal to the playback adapter.

The context-menu video and audio selectors list every observed track of their type and check the active track. The subtitle selector lists Off plus every observed subtitle track and checks the active choice. Neither selector invents labels or selection when libmpv cannot report them. The checked choice is refreshed from libmpv after a selection command completes.

## External subtitle discovery

Search only the opened video's directory. For a video stem `Movie`, accept case-insensitive supported extensions when the subtitle basename is:

- exactly `Movie`;
- `Movie.<language>` or `Movie.<ISO language>`;
- `Movie.forced`;
- `Movie.<language>.forced`;
- another explicitly documented suffix that remains anchored to `Movie`.

Minimum formats are `.srt`, `.ass`, `.ssa`, `.vtt`, and `.sub`. A VobSub `.sub` is loaded only with its matching `.idx`; text-based `.sub` is delegated to libmpv detection. Ignore hidden temporary files, directories, overly broad prefix matches such as `Movie 2.srt`, and anything outside the media directory.

Discovery returns a deterministic order and deduplicates paths before explicit `sub-add` commands. Embedded and external tracks then appear in one selector.

## Selection policy

User selection during the current file always wins. Otherwise rank candidates by:

1. remembered per-file track when it still exists;
2. forced track matching the selected audio/user language when foreign dialogue requires it;
3. configured subtitle language order;
4. container default flag;
5. no subtitles when no candidate satisfies policy.

Avoid filename-only claims about hearing-impaired/commentary content. Show the available title/flags and allow immediate override.

Audio ranking is:

1. remembered per-file selection;
2. configured language order;
3. container default;
4. first playable track.

## Track switching

- Cycle commands use the normalized ordered list and include Subtitle Off.
- Selection updates only after libmpv confirms the active track.
- Preserve playback position and play/pause state.
- A failed/unsupported track reports a non-blocking error and retains or selects a playable previous/default track.

## Audio output and passthrough

PCM decoding is the safe default. Passthrough is opt-in because receiver capability detection is imperfect and a wrong choice can produce silence. The settings design may offer an `Off` default and an advanced codec allowlist/profile for AC3, E-AC3, DTS/DTS-HD, and TrueHD/Atmos where the Windows device chain supports them.

If passthrough initialization fails, HVP falls back to decoded PCM and reports the fallback. It must never emit encoded data to an unconfirmed output path.

## Acceptance criteria

- All embedded tracks and all valid matching external subtitles appear once in deterministic selectors.
- Required naming examples from `brief.md` are covered by unit tests, including case differences and `.sub`/`.idx` pairing.
- Language, forced, remembered, and default ranking has table-driven tests.
- Track switches are fast, preserve position, and recover safely from an unsupported stream.
- Passthrough behavior is explicit, testable on supported receivers, and safely falls back.
