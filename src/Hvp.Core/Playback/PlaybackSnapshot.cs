namespace Hvp.Core.Playback;

public sealed record PlaybackSnapshot(
    PlaybackState State,
    string? Message = null,
    StreamDescriptor? Stream = null,
    IReadOnlyList<SubtitleTrack>? SubtitleTracks = null,
    int? SelectedSubtitleTrackId = null,
    IReadOnlyList<AudioTrack>? AudioTracks = null,
    int? SelectedAudioTrackId = null,
    IReadOnlyList<VideoTrack>? VideoTracks = null,
    int? SelectedVideoTrackId = null)
{
    public static PlaybackSnapshot Idle { get; } = new(PlaybackState.Idle);
}
