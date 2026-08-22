# HVP

HVP is an early Windows local-video-player preview for large movie files. The
current milestone plays one local file through a pinned private `libmpv` DLL,
with basic transport controls and drag-and-drop.

`0.1.0-preview.1` is a development preview. It is not a stable public release:
the clean-machine and broader real-file validation evidence tracked by issue #6
is still outstanding.

## Start here

- Product requirements: [`brief.md`](brief.md)
- Implementation roadmap and proposed folder structure: [`implementation_plan.md`](implementation_plan.md)
- Design catalog: [`Docs/master_design.md`](Docs/master_design.md)
- Contribution workflow: [`CONTRIBUTING.md`](CONTRIBUTING.md)

## Run the preview

On Windows with the .NET 10 SDK, from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\eng\native\Get-LibmpvBundle.ps1
dotnet restore .\Hvp.slnx --locked-mode
dotnet publish .\src\Hvp.App\Hvp.App.csproj -c Release -r win-x64 --self-contained true --no-restore
& .\src\Hvp.App\bin\Release\net10.0-windows10.0.19041.0\win-x64\publish\HVP-win-x64.exe
```

Drag one local `.mp4`, `.mkv`, `.mov`, `.avi`, `.webm`, or `.m4v` file onto the
window. The publish target stages the pinned DLL and current notice files.

## Planned user experience

The first release artifact is one offline self-contained Windows x64 folder.
An installer is deferred until playback is proven.

## Technology direction

- C# and .NET 10 LTS
- WPF shell with a Win32 video host
- libmpv, FFmpeg, `gpu-next`, and libplacebo
- D3D11 hardware decode/render path with safe fallback

See the implementation plan for the licensing, native-binary, and installed-payload constraints behind the offline release.

## License

HVP source code is licensed under the [MIT License](LICENSE). The development
preview's pinned native bundle and current notice record are described in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
