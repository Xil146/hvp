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
}
