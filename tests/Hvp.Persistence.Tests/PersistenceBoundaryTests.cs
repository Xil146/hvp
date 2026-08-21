using Hvp.Persistence;

namespace Hvp.Persistence.Tests;

public sealed class PersistenceBoundaryTests
{
    [Fact]
    public void Storage_scope_is_local_application_data()
    {
        Assert.Equal("Local application data", PersistenceBoundary.StorageScope);
    }
}
