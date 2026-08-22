using System.Globalization;
using System.Text.RegularExpressions;

namespace Hvp.Core.Playback;

/// <summary>Converts observed, renderer-neutral video properties into conservative source facts.</summary>
public static partial class StreamDescriptorFactory
{
    public static StreamDescriptor Create(
        string? width,
        string? height,
        string? codec,
        string? pixelFormat,
        string? gamma,
        string? primaries) => new(
            ParseInteger(width),
            ParseInteger(height),
            string.IsNullOrWhiteSpace(codec) ? null : codec,
            DetermineBitDepth(pixelFormat),
            ClassifyDynamicRange(gamma, primaries));

    private static int? ParseInteger(string? value) =>
        int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out int result) ? result : null;

    private static int? DetermineBitDepth(string? pixelFormat)
    {
        if (string.IsNullOrWhiteSpace(pixelFormat))
        {
            return null;
        }

        string normalized = pixelFormat.ToLowerInvariant();
        if (normalized.Contains("p010", StringComparison.Ordinal))
        {
            return 10;
        }

        Match match = BitDepthSuffix().Match(normalized);
        if (match.Success && int.TryParse(match.Groups["depth"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out int depth))
        {
            return depth;
        }

        return normalized is "yuv420p" or "yuv422p" or "yuv444p" or "nv12" or "bgra" or "rgba" ? 8 : null;
    }

    private static string ClassifyDynamicRange(string? gamma, string? primaries)
    {
        string transfer = gamma?.Trim().ToLowerInvariant() ?? string.Empty;
        string colorPrimaries = primaries?.Trim().ToLowerInvariant() ?? string.Empty;
        if (transfer == "pq")
        {
            return colorPrimaries == "bt.2020" ? "HDR (PQ)" : "Unknown HDR";
        }

        if (transfer is "hlg" or "arib-std-b67")
        {
            return "HLG";
        }

        return transfer is "bt.1886" or "srgb" or "linear" or "gamma22" or "gamma24" or "gamma28" or "iec61966-2-1"
            ? "SDR"
            : "Unknown";
    }

    [GeneratedRegex("(?:p|gbrp|gray)(?<depth>8|9|10|12|14|16)(?:le|be)?$")]
    private static partial Regex BitDepthSuffix();
}
