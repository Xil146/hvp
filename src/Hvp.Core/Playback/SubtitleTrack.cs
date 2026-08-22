namespace Hvp.Core.Playback;

/// <summary>A subtitle track that can be displayed and selected without leaking native mpv details.</summary>
public sealed record SubtitleTrack(int Id, string Label, bool IsExternal);
