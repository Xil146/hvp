namespace Hvp.Core.Playback;

public sealed record PlaybackSnapshot(
    PlaybackState State,
    string? Message = null,
    StreamDescriptor? Stream = null,
    IReadOnlyList<SubtitleTrack>? SubtitleTracks = null,
    int? SelectedSubtitleTrackId = null)
{
    public static PlaybackSnapshot Idle { get; } = new(PlaybackState.Idle);
}
