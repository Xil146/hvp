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

    [Fact]
    public async Task Libmpv_engine_reports_a_helpful_error_when_private_dll_is_missing()
    {
        await using LibmpvPlaybackEngine engine = new();

        FileNotFoundException exception = await Assert.ThrowsAsync<FileNotFoundException>(
            () => engine.InitializeAsync((nint)123));

        Assert.Contains("private libmpv", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Libmpv_engine_dispose_is_idempotent_before_initialization()
    {
        LibmpvPlaybackEngine engine = new();

        await engine.DisposeAsync();
        await engine.DisposeAsync();
    }
}
