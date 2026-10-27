using System.Text.Json;
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.Soup.Api.Models;

/// <summary>
/// Body for <c>POST /SoupSeerr/Request</c>: what to ask Seerr for, on behalf of the signed-in user.
/// </summary>
public sealed class SeerrRequestBody
{
    /// <summary>
    /// Gets or sets <c>movie</c> or <c>tv</c>.
    /// </summary>
    public string MediaType { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the TMDB id.
    /// </summary>
    public int MediaId { get; set; }

    /// <summary>
    /// Gets or sets the TVDB id, when the client knows it (helps Sonarr lookups).
    /// </summary>
    public int? TvdbId { get; set; }

    /// <summary>
    /// Gets or sets the seasons to request for a show: an array of season numbers, or the string <c>all</c>.
    /// </summary>
    public JsonElement? Seasons { get; set; }

    /// <summary>
    /// Gets or sets a value indicating whether to request the 4K version.
    /// </summary>
    public bool Is4k { get; set; }
}

/// <summary>
/// Body for <c>POST /SoupSeerr/Test</c>: credentials to try before saving (blank falls back to the saved ones).
/// </summary>
public sealed class SeerrTestBody
{
    /// <summary>
    /// Gets or sets the base URL to probe.
    /// </summary>
    public string? BaseUrl { get; set; }

    /// <summary>
    /// Gets or sets the API key to probe with.
    /// </summary>
    public string? ApiKey { get; set; }
}

/// <summary>
/// The Seerr user as returned to clients: no email, no token.
/// </summary>
public sealed class SeerrUserInfo
{
    /// <summary>
    /// Gets or sets the Seerr user id.
    /// </summary>
    [JsonPropertyName("id")]
    public int Id { get; set; }

    /// <summary>
    /// Gets or sets the display name.
    /// </summary>
    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the avatar URL.
    /// </summary>
    [JsonPropertyName("avatar")]
    public string? Avatar { get; set; }

    /// <summary>
    /// Gets or sets the Seerr permission bitmask.
    /// </summary>
    [JsonPropertyName("permissions")]
    public long Permissions { get; set; }
}
