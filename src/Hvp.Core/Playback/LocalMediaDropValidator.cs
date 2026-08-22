namespace Hvp.Core.Playback;

/// <summary>Validates the deliberately single-file local-media drop policy.</summary>
public static class LocalMediaDropValidator
{
    private static readonly HashSet<string> SupportedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".avi", ".m4v", ".mkv", ".mov", ".mp4", ".webm",
    };

    /// <summary>
    /// Accepts exactly one existing local video file and returns its full path.
    /// </summary>
    public static bool TryGetSingleLocalVideoFile(
        IReadOnlyCollection<string>? paths,
        out string? fullPath,
        out string message)
    {
        fullPath = null;
        if (paths is null || paths.Count == 0)
        {
            message = "Drop one local video file to open it.";
            return false;
        }

        if (paths.Count != 1)
        {
            message = "Drop exactly one video file; playlists are not supported.";
            return false;
        }

        string candidate = paths.First();
        if (string.IsNullOrWhiteSpace(candidate))
        {
            message = "The dropped item does not have a usable local path.";
            return false;
        }

        if (candidate.StartsWith("\\\\", StringComparison.Ordinal) || !Path.IsPathFullyQualified(candidate))
        {
            message = "Only local files can be opened. Copy the video to this computer first.";
            return false;
        }

        try
        {
            fullPath = Path.GetFullPath(candidate);
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException or PathTooLongException)
        {
            message = "The dropped item does not have a usable local path.";
            return false;
        }

        if (Directory.Exists(fullPath))
        {
            fullPath = null;
            message = "Folders cannot be opened. Drop one local video file instead.";
            return false;
        }

        if (!File.Exists(fullPath))
        {
            fullPath = null;
            message = "The dropped file is no longer available locally.";
            return false;
        }

        if (!SupportedExtensions.Contains(Path.GetExtension(fullPath)))
        {
            fullPath = null;
            message = "That file type is not supported. Drop a local video file instead.";
            return false;
        }

        message = string.Empty;
        return true;
    }
}
