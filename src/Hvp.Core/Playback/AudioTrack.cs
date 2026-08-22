namespace Hvp.Core.Playback;

/// <summary>An audio track that can be selected without leaking native mpv details.</summary>
public sealed record AudioTrack(int Id, string Label, bool IsExternal);
