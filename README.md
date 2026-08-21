# HVP

HVP is a planned lightweight Windows video player for large local movie files, with automatic HDR/SDR handling, hardware decoding, subtitles, audio-track selection, and a deliberately minimal interface.

The project is currently in the design and repository-foundation stage. There is no runnable build yet.

## Start here

- Product requirements: [`brief.md`](brief.md)
- Implementation roadmap and proposed folder structure: [`implementation_plan.md`](implementation_plan.md)
- Design catalog: [`Docs/master_design.md`](Docs/master_design.md)
- Contribution workflow: [`CONTRIBUTING.md`](CONTRIBUTING.md)

## Planned user experience

The primary Windows x64 release will be one offline installer. It installs one HVP application with the .NET runtime, media engine, codecs, and supporting DLLs included; users will not source dependencies or need a network connection to install or run it.

## Technology direction

- C# and .NET 10 LTS
- WPF shell with a Win32 video host
- libmpv, FFmpeg, `gpu-next`, and libplacebo
- D3D11 hardware decode/render path with safe fallback

See the implementation plan for the licensing, native-binary, and installed-payload constraints behind the offline release.

## License

HVP source code is licensed under the [MIT License](LICENSE). Bundled third-party components retain their own licenses and will be listed in `THIRD_PARTY_NOTICES.md` before binary releases.
