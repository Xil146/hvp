namespace Hvp.Persistence;

/// <summary>
/// Reserves the local versioned-settings and history boundary. File I/O and
/// migrations are intentionally deferred until their policy is implemented.
/// </summary>
public static class PersistenceBoundary
{
    public const string StorageScope = "Local application data";
}
