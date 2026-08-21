Lightweight HDR Video Player — Brief
Goal

Build a lightweight Windows video player focused on large local movie files, especially .mkv, with strong automatic HDR handling and minimal configuration.

The core principle is:

Open a video and have everything important work automatically.

Core Requirements
Support .mkv and common video containers.
Support:
H.264 / AVC
H.265 / HEVC
8-bit and 10-bit video
Use hardware decoding where available via NVIDIA, AMD, or Intel GPUs.
Handle very large 4K HDR files efficiently with low CPU usage.
HDR / SDR Handling

Automatically inspect the video stream and determine whether the content is:

SDR
HDR10
HLG
HDR10+
Dolby Vision where detectable

Playback should adapt automatically:

HDR content + HDR-capable Windows display → native HDR output where supported.
HDR content + SDR output → high-quality automatic tone mapping.
SDR content on an HDR-enabled Windows desktop → preserve correct SDR brightness and colors.
SDR content + SDR display → standard SDR playback.

Prefer libmpv with gpu-next / libplacebo for rendering, HDR processing, tone mapping, scaling, dithering and color management.

Display a small status indicator such as:

HDR10 • 2160p • HEVC 10-bit

or

SDR • 1080p • H.264

Subtitles

Automatically detect:

Subtitle tracks embedded inside MKV files.
External subtitle files located next to the video.

Supported external formats should include at minimum:

.srt
.ass
.ssa
.vtt
.sub

Automatically associate matching filenames such as:

Movie.mkv
Movie.srt
Movie.en.srt
Movie.eng.srt
Movie.sv.srt
Movie.forced.srt

Embedded and external subtitles should appear together in a single subtitle selector.

Forced subtitle tracks should be detected and selected automatically where appropriate.

Audio

Automatically detect all embedded audio tracks.

Support common formats including:

AAC
AC3
E-AC3
DTS
TrueHD
FLAC
PCM

Allow fast audio-track switching.

Audio passthrough for formats such as TrueHD/Atmos and DTS-HD should be supported where the Windows/audio setup allows it.

UI

Keep the interface deliberately minimal.

Primary controls:

Play / Pause
Seek
Volume
Fullscreen
Subtitle selection
Audio-track selection
Open file

Keyboard shortcuts:

Space — Play/Pause
Left / Right — Seek
F — Fullscreen
S — Subtitle track
A — Audio track
Esc — Exit fullscreen
Convenience
Remember playback position per file.
Resume automatically when reopening a partially watched file.
Automatically select sensible default audio/subtitle tracks based on language metadata.
Avoid unnecessary library, streaming, account, network, media-server or playlist features.
Suggested Technical Stack
Windows
C# / .NET
WPF or WinUI 3 for the UI
libmpv as the playback engine
FFmpeg/libavformat underneath for demuxing and codec support
gpu-next / libplacebo for rendering and HDR processing
D3D11 hardware decoding/output on Windows
V1 Definition

V1 should successfully achieve:

Open a large MKV → detect SDR/HDR automatically → hardware decode → display correctly → detect subtitles and audio tracks → play smoothly with minimal UI.