using Hvp.Core.Playback;

namespace Hvp.Core.Tests;

public sealed class PlaybackSnapshotTests
{
    [Fact]
    public void Core_assembly_has_no_wpf_or_libmpv_reference()
    {
        string[] references = typeof(PlaybackSnapshot).Assembly
            .GetReferencedAssemblies()
            .Select(reference => reference.Name ?? string.Empty)
            .ToArray();

        Assert.DoesNotContain(references, name => name.StartsWith("Presentation", StringComparison.Ordinal));
        Assert.DoesNotContain("WindowsBase", references);
        Assert.DoesNotContain(references, name => name.Contains("mpv", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Idle_snapshot_is_stable_and_message_free()
    {
        PlaybackSnapshot snapshot = PlaybackSnapshot.Idle;

        Assert.Equal(PlaybackState.Idle, snapshot.State);
        Assert.Null(snapshot.Message);
    }

    [Fact]
    public void Snapshot_preserves_audio_track_selection()
    {
        AudioTrack track = new(2, "English", false);
        PlaybackSnapshot snapshot = new(PlaybackState.Playing, AudioTracks: [track], SelectedAudioTrackId: track.Id);

        Assert.Collection(snapshot.AudioTracks!, actual => Assert.Equal(track, actual));
        Assert.Equal(track.Id, snapshot.SelectedAudioTrackId);
    }

    [Fact]
    public void Snapshot_preserves_video_track_selection()
    {
        VideoTrack track = new(1, "Director's angle", false);
        PlaybackSnapshot snapshot = new(PlaybackState.Playing, VideoTracks: [track], SelectedVideoTrackId: track.Id);

        Assert.Collection(snapshot.VideoTracks!, actual => Assert.Equal(track, actual));
        Assert.Equal(track.Id, snapshot.SelectedVideoTrackId);
    }
}
