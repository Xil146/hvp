namespace Hvp.IntegrationTests;

public sealed class ScaffoldSmokeTests
{
    [Fact]
    public void Application_shell_type_is_available_without_starting_wpf()
    {
        Assert.Equal("Hvp.App.App", typeof(global::Hvp.App.App).FullName);
    }
}
