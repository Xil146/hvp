using Hvp.Core.Playback;

namespace Hvp.Core.Tests;

public sealed class LocalMediaDropValidatorTests : IDisposable
{
    private readonly string temporaryDirectory = Path.Combine(Path.GetTempPath(), "Hvp.Core.Tests", Guid.NewGuid().ToString("N"));

    [Fact]
    public void Accepts_exactly_one_existing_supported_file_and_returns_full_path()
    {
        string file = CreateFile("film åäö.mp4");

        bool accepted = LocalMediaDropValidator.TryGetSingleLocalVideoFile([file], out string? fullPath, out string message);

        Assert.True(accepted);
        Assert.Equal(Path.GetFullPath(file), fullPath);
        Assert.Empty(message);
    }

    [Fact]
    public void Rejects_multiple_files()
    {
        string first = CreateFile("first.mp4");
        string second = CreateFile("second.mkv");

        bool accepted = LocalMediaDropValidator.TryGetSingleLocalVideoFile([first, second], out string? fullPath, out string message);

        Assert.False(accepted);
        Assert.Null(fullPath);
        Assert.Contains("exactly one", message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Rejects_folders()
    {
        Directory.CreateDirectory(temporaryDirectory);

        bool accepted = LocalMediaDropValidator.TryGetSingleLocalVideoFile([temporaryDirectory], out string? fullPath, out string message);

        Assert.False(accepted);
        Assert.Null(fullPath);
        Assert.Contains("Folders", message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Rejects_network_paths_without_probing_them()
    {
        bool accepted = LocalMediaDropValidator.TryGetSingleLocalVideoFile([@"\\server\share\movie.mp4"], out string? fullPath, out string message);

        Assert.False(accepted);
        Assert.Null(fullPath);
        Assert.Contains("Only local", message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Rejects_non_video_files()
    {
        string file = CreateFile("notes.txt");

        bool accepted = LocalMediaDropValidator.TryGetSingleLocalVideoFile([file], out string? fullPath, out string message);

        Assert.False(accepted);
        Assert.Null(fullPath);
        Assert.Contains("not supported", message, StringComparison.OrdinalIgnoreCase);
    }

    public void Dispose()
    {
        if (Directory.Exists(temporaryDirectory))
        {
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    private string CreateFile(string name)
    {
        Directory.CreateDirectory(temporaryDirectory);
        string path = Path.Combine(temporaryDirectory, name);
        File.WriteAllBytes(path, []);
        return path;
    }
}
