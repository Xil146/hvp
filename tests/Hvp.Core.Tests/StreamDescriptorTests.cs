using Hvp.Core.Playback;

namespace Hvp.Core.Tests;

public sealed class StreamDescriptorTests
{
    [Fact]
    public void Compact_text_labels_dynamic_range_as_source_information()
    {
        StreamDescriptor descriptor = new(3840, 2160, "hevc", 10, "HDR (PQ)");

        string text = descriptor.ToCompactText();

        Assert.Equal("3840\u00D72160 \u2022 HDR (PQ) source \u2022 hevc \u2022 10-bit", text);
        Assert.DoesNotContain("\u00C3", text, StringComparison.Ordinal);
        Assert.DoesNotContain("\u00E2", text, StringComparison.Ordinal);
    }

    [Fact]
    public void Compact_text_degrades_when_stream_facts_are_unavailable()
    {
        string text = StreamDescriptor.Unknown.ToCompactText();

        Assert.Contains("Resolution unknown", text, StringComparison.Ordinal);
        Assert.Contains("Codec unknown", text, StringComparison.Ordinal);
        Assert.Contains("Bit depth unknown", text, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("yuv420p10le", "pq", "bt.2020", 10, "HDR (PQ)")]
    [InlineData("p010le", "pq", null, 10, "Unknown HDR")]
    [InlineData("nv12", "bt.1886", "bt.709", 8, "SDR")]
    [InlineData("yuv420p", "unspecified", "bt.709", 8, "Unknown")]
    public void Factory_derives_supported_source_facts_conservatively(string pixelFormat, string gamma, string? primaries, int depth, string dynamicRange)
    {
        StreamDescriptor descriptor = StreamDescriptorFactory.Create("3840", "2160", "hevc", pixelFormat, gamma, primaries);

        Assert.Equal(depth, descriptor.BitDepth);
        Assert.Equal(dynamicRange, descriptor.DynamicRange);
    }
}
