using Hvp.Core.Playback;
using Hvp.Playback;

namespace Hvp.Playback.Tests;

public sealed class PlaybackEngineBoundaryTests
{
    [Fact]
    public void Playback_assembly_has_no_wpf_reference()
    {
        string[] references = typeof(PlaybackEngineBoundary).Assembly
            .GetReferencedAssemblies()
            .Select(reference => reference.Name ?? string.Empty)
            .ToArray();

        Assert.DoesNotContain(references, name => name.StartsWith("Presentation", StringComparison.Ordinal));
        Assert.DoesNotContain("WindowsBase", references);
    }

    [Fact]
    public async Task Boundary_is_idle_and_disposes_without_native_loading()
    {
        await using PlaybackEngineBoundary engine = new();

        Assert.Equal(PlaybackState.Idle, engine.Snapshot.State);
    }
}
