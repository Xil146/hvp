namespace Hvp.Core.Playback;

public sealed record PlaybackSnapshot(PlaybackState State, string? Message = null)
{
    public static PlaybackSnapshot Idle { get; } = new(PlaybackState.Idle);
}
