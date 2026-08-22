namespace Hvp.Core.Playback;

/// <summary>Observed source facts. Output HDR state is intentionally not inferred from these values.</summary>
public sealed record StreamDescriptor(
    int? Width,
    int? Height,
    string? Codec,
    int? BitDepth,
    string DynamicRange)
{
    public static StreamDescriptor Unknown { get; } = new(null, null, null, null, "Unknown");

    public string ToCompactText()
    {
        string resolution = Width is > 0 && Height is > 0 ? $"{Width}\u00D7{Height}" : "Resolution unknown";
        string codec = string.IsNullOrWhiteSpace(Codec) ? "Codec unknown" : Codec;
        string depth = BitDepth is > 0 ? $"{BitDepth}-bit" : "Bit depth unknown";
        return $"{resolution} \u2022 {DynamicRange} source \u2022 {codec} \u2022 {depth}";
    }
}
