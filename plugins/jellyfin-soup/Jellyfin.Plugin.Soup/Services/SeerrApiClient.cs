using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
using Jellyfin.Plugin.Soup.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.Soup.Services;

/// <summary>
/// A Seerr user matched to a Jellyfin user.
/// </summary>
/// <param name="Id">Seerr user id.</param>
/// <param name="DisplayName">Name Seerr shows for the user.</param>
/// <param name="Avatar">Avatar URL (may be relative to Seerr).</param>
/// <param name="Permissions">Seerr permission bitmask.</param>
public sealed record SeerrUser(int Id, string DisplayName, string? Avatar, long Permissions)
{
    /// <summary>Seerr <c>Permission.ADMIN</c>.</summary>
    public const long Admin = 2;

    /// <summary>Seerr <c>Permission.MANAGE_REQUESTS</c>.</summary>
    public const long ManageRequests = 16;

    /// <summary>
    /// Whether the user holds <paramref name="flag"/>, or is an admin (who holds everything).
    /// </summary>
    /// <param name="flag">Permission bit.</param>
    /// <returns>True when granted.</returns>
    public bool Has(long flag) => (Permissions & Admin) == Admin || (Permissions & flag) == flag;
}

/// <summary>
/// What Seerr answered: its status code and raw JSON body, passed through to the client.
/// </summary>
/// <param name="StatusCode">Upstream HTTP status.</param>
/// <param name="Body">Upstream body (JSON, or empty).</param>
public sealed record SeerrResponse(HttpStatusCode StatusCode, string Body)
{
    /// <summary>Gets a value indicating whether the status is 2xx.</summary>
    public bool IsSuccess => (int)StatusCode is >= 200 and < 300;

    /// <summary>
    /// Parse the body as JSON, or null when it isn't.
    /// </summary>
    /// <returns>Root element or null.</returns>
    public JsonElement? Json()
    {
        if (string.IsNullOrWhiteSpace(Body))
        {
            return null;
        }

        try
        {
            using var doc = JsonDocument.Parse(Body);
            return doc.RootElement.Clone();
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <summary>
/// Outbound HTTP client for a Seerr (Jellyseerr/Overseerr) server using the plugin's API key.
/// </summary>
public sealed class SeerrApiClient
{
    /// <summary>
    /// Named <see cref="IHttpClientFactory"/> client.
    /// </summary>
    public const string HttpClientName = "Seerr";

    private static readonly TimeSpan UserCacheTtl = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan MissingUserCacheTtl = TimeSpan.FromMinutes(1);

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<SeerrApiClient> _logger;
    private readonly ConcurrentDictionary<Guid, (SeerrUser? User, DateTime ExpiresAt)> _users = new();

    /// <summary>
    /// Initializes a new instance of the <see cref="SeerrApiClient"/> class.
    /// </summary>
    /// <param name="httpClientFactory">HTTP client factory.</param>
    /// <param name="logger">Logger.</param>
    public SeerrApiClient(IHttpClientFactory httpClientFactory, ILogger<SeerrApiClient> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    /// <summary>
    /// Gets a value indicating whether a Seerr URL and API key are configured.
    /// </summary>
    public static bool IsConfigured
    {
        get
        {
            var config = Plugin.Instance?.Configuration;
            return config is not null
                && !string.IsNullOrWhiteSpace(config.SeerrBaseUrl)
                && !string.IsNullOrWhiteSpace(config.SeerrApiKey);
        }
    }

    /// <summary>
    /// <c>{base}/api/v1</c> for a configured base URL, whether or not it already ends in <c>/api/v1</c>.
    /// </summary>
    /// <param name="baseUrl">Configured base URL.</param>
    /// <returns>API root without a trailing slash.</returns>
    public static string ApiRoot(string baseUrl)
    {
        var trimmed = baseUrl.Trim().TrimEnd('/');
        return trimmed.EndsWith("/api/v1", StringComparison.OrdinalIgnoreCase) ? trimmed : trimmed + "/api/v1";
    }

    /// <summary>
    /// Forget cached user matches (after the admin changes settings).
    /// </summary>
    public void ClearUserCache() => _users.Clear();

    /// <summary>
    /// Send a request to Seerr with the configured API key.
    /// </summary>
    /// <param name="method">HTTP method.</param>
    /// <param name="pathAndQuery">Path under <c>/api/v1</c>, with query string, no leading slash.</param>
    /// <param name="jsonBody">Optional JSON body.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <param name="overrideBaseUrl">Use this base URL instead of the saved one (settings test).</param>
    /// <param name="overrideApiKey">Use this API key instead of the saved one (settings test).</param>
    /// <returns>Upstream status and body.</returns>
    /// <exception cref="InvalidOperationException">Seerr isn't configured.</exception>
    /// <exception cref="HttpRequestException">Seerr couldn't be reached.</exception>
    public async Task<SeerrResponse> SendAsync(
        HttpMethod method,
        string pathAndQuery,
        string? jsonBody,
        CancellationToken cancellationToken,
        string? overrideBaseUrl = null,
        string? overrideApiKey = null)
    {
        var config = Plugin.Instance?.Configuration ?? throw new InvalidOperationException("Soup plugin is not loaded");
        var baseUrl = string.IsNullOrWhiteSpace(overrideBaseUrl) ? config.SeerrBaseUrl : overrideBaseUrl;
        var apiKey = string.IsNullOrWhiteSpace(overrideApiKey) ? config.SeerrApiKey : overrideApiKey;
        if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("Seerr is not configured");
        }

        var client = _httpClientFactory.CreateClient(HttpClientName);
        using var request = new HttpRequestMessage(method, $"{ApiRoot(baseUrl)}/{pathAndQuery.TrimStart('/')}");
        request.Headers.TryAddWithoutValidation("X-Api-Key", apiKey.Trim());
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        if (jsonBody is not null)
        {
            request.Content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
        }

        using var response = await client.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            _logger.LogDebug("Seerr {Method} {Path} → {Status}", method, pathAndQuery, (int)response.StatusCode);
        }

        return new SeerrResponse(response.StatusCode, body);
    }

    /// <summary>
    /// GET <c>/status</c> (public): Seerr's version, or null when it can't be reached.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <param name="overrideBaseUrl">Base URL to probe instead of the saved one.</param>
    /// <param name="overrideApiKey">API key to use instead of the saved one.</param>
    /// <returns>Version string.</returns>
    public async Task<string?> GetVersionAsync(
        CancellationToken cancellationToken,
        string? overrideBaseUrl = null,
        string? overrideApiKey = null)
    {
        var response = await SendAsync(HttpMethod.Get, "status", null, cancellationToken, overrideBaseUrl, overrideApiKey)
            .ConfigureAwait(false);
        var json = response.IsSuccess ? response.Json() : null;
        return json is { ValueKind: JsonValueKind.Object } root
            && root.TryGetProperty("version", out var version)
            && version.ValueKind == JsonValueKind.String
            ? version.GetString()
            : null;
    }

    /// <summary>
    /// The Seerr user linked to a Jellyfin user, by Jellyfin user id first and username second.
    /// Cached for a few minutes.
    /// </summary>
    /// <param name="jellyfinUserId">Jellyfin user id.</param>
    /// <param name="jellyfinUsername">Jellyfin username, for Seerr versions that only keep that.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Matched user, or null when Seerr has no account for them.</returns>
    public async Task<SeerrUser?> ResolveUserAsync(
        Guid jellyfinUserId,
        string? jellyfinUsername,
        CancellationToken cancellationToken)
    {
        if (_users.TryGetValue(jellyfinUserId, out var cached) && cached.ExpiresAt > DateTime.UtcNow)
        {
            return cached.User;
        }

        var user = await LookupUserAsync(jellyfinUserId, jellyfinUsername, cancellationToken).ConfigureAwait(false);
        _users[jellyfinUserId] = (user, DateTime.UtcNow + (user is null ? MissingUserCacheTtl : UserCacheTtl));
        return user;
    }

    private async Task<SeerrUser?> LookupUserAsync(Guid jellyfinUserId, string? jellyfinUsername, CancellationToken cancellationToken)
    {
        var idN = jellyfinUserId.ToString("N");

        // Seerr 2.x: direct lookup by Jellyfin user id.
        var direct = await SendAsync(HttpMethod.Get, $"user/jellyfin/{idN}", null, cancellationToken).ConfigureAwait(false);
        if (direct.IsSuccess && direct.Json() is { ValueKind: JsonValueKind.Object } found)
        {
            return ParseUser(found);
        }

        // Older servers: scan the user list and match on the stored Jellyfin id or username.
        var list = await SendAsync(HttpMethod.Get, "user?take=1000&skip=0", null, cancellationToken).ConfigureAwait(false);
        if (!list.IsSuccess || list.Json() is not { ValueKind: JsonValueKind.Object } page
            || !page.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Array)
        {
            _logger.LogWarning("Seerr user list unavailable ({Status}); cannot link Jellyfin user {UserId}", (int)list.StatusCode, idN);
            return null;
        }

        SeerrUser? byName = null;
        foreach (var candidate in results.EnumerateArray())
        {
            var storedId = GetString(candidate, "jellyfinUserId")?.Replace("-", string.Empty, StringComparison.Ordinal);
            if (storedId is not null && storedId.Equals(idN, StringComparison.OrdinalIgnoreCase))
            {
                return ParseUser(candidate);
            }

            var storedName = GetString(candidate, "jellyfinUsername");
            if (byName is null && jellyfinUsername is not null && storedName is not null
                && storedName.Equals(jellyfinUsername, StringComparison.OrdinalIgnoreCase))
            {
                byName = ParseUser(candidate);
            }
        }

        return byName;
    }

    private static SeerrUser? ParseUser(JsonElement element)
    {
        if (!element.TryGetProperty("id", out var idElement) || idElement.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        var name = GetString(element, "displayName")
            ?? GetString(element, "username")
            ?? GetString(element, "jellyfinUsername")
            ?? GetString(element, "plexUsername")
            ?? GetString(element, "email")
            ?? $"User {idElement.GetInt32()}";
        var permissions = element.TryGetProperty("permissions", out var perms) && perms.ValueKind == JsonValueKind.Number
            ? perms.GetInt64()
            : 0;
        return new SeerrUser(idElement.GetInt32(), name, GetString(element, "avatar"), permissions);
    }

    private static string? GetString(JsonElement element, string property)
        => element.ValueKind == JsonValueKind.Object
           && element.TryGetProperty(property, out var value)
           && value.ValueKind == JsonValueKind.String
           && !string.IsNullOrWhiteSpace(value.GetString())
            ? value.GetString()
            : null;
}
