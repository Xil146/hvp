namespace Hvp.IntegrationTests;

public sealed class ScaffoldSmokeTests
{
    [Fact]
    public void Application_shell_type_is_available_without_starting_wpf()
    {
        Assert.Equal("Hvp.App.App", typeof(global::Hvp.App.App).FullName);
    }

    [Fact]
    public void Video_context_menu_coordinates_preserve_the_native_screen_location()
    {
        Hvp.Platform.Windows.VideoHostContextMenuEventArgs coordinates = new(1920, 1080);

        Assert.Equal(1920, coordinates.ScreenX);
        Assert.Equal(1080, coordinates.ScreenY);
    }

    [Fact]
    public void Native_video_drop_preserves_all_paths_for_application_validation()
    {
        string[] paths = [@"C:\media\one.mkv", @"C:\media\two.mp4"];

        Hvp.Platform.Windows.VideoHostFilesDroppedEventArgs dropped = new(paths);

        Assert.Equal(paths, dropped.Paths);
    }
}
