using System.Collections.Concurrent;

namespace Jellyfin.Plugin.Soup.Services;

/// <summary>
/// In-memory one-time consume of assertion <c>jti</c> values within assertion TTL.
/// </summary>
public sealed class AssertionReplayStore
{
    private readonly ConcurrentDictionary<string, DateTimeOffset> _seen = new(StringComparer.Ordinal);

    /// <summary>
    /// Records <paramref name="jti"/> as consumed. Returns false if it was already used.
    /// </summary>
    /// <param name="jti">JWT ID from the assertion.</param>
    /// <param name="expiresAt">When the assertion expires (UTC); used for purge.</param>
    /// <returns>True if this is the first consume.</returns>
    public bool TryConsume(string jti, DateTimeOffset expiresAt)
    {
        if (string.IsNullOrWhiteSpace(jti))
        {
            return false;
        }

        PurgeExpired();
        return _seen.TryAdd(jti, expiresAt);
    }

    private void PurgeExpired()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var pair in _seen)
        {
            if (pair.Value <= now)
            {
                _seen.TryRemove(pair.Key, out _);
            }
        }
    }
}
