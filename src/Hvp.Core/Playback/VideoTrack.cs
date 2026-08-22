namespace Hvp.Core.Playback;

/// <summary>A video track that can be selected without leaking native mpv details.</summary>
public sealed record VideoTrack(int Id, string Label, bool IsExternal);
