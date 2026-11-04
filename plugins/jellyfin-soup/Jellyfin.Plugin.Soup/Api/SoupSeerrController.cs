using System.Net;
using System.Text.Json;
using Jellyfin.Plugin.Soup.Api.Models;
using Jellyfin.Plugin.Soup.Services;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.Soup.Api;

/// <summary>
/// Seerr (Jellyseerr/Overseerr) for signed-in Jellyfin users: browse TMDB through Seerr and
/// request titles as the Seerr account linked to the caller's Jellyfin account. The API key
/// never leaves this host.
/// </summary>
[ApiController]
[Route("SoupSeerr")]
[Authorize]
public sealed class SoupSeerrController : ControllerBase
{
    private const string JsonContentType = "application/json";

    /// <summary>
    /// Top-level Seerr paths that clients may GET through <c>Browse</c>: TMDB catalogue reads only.
    /// </summary>
    private static readonly HashSet<string> BrowsePrefixes = new(StringComparer.OrdinalIgnoreCase)
    {
        "search",
        "discover",
        "movie",
        "tv",
        "person",
        "collection",
        "genres",
        "regions",
        "languages",
        "studio",
        "network",
        "keyword",
    };

    private static readonly HashSet<string> StrippedQueryKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "api_key",
        "apikey",
        "x-emby-token",
    };

    private readonly SeerrApiClient _seerr;
    private readonly IAuthorizationContext _authorizationContext;
    private readonly ILogger<SoupSeerrController> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="SoupSeerrController"/> class.
    /// </summary>
    /// <param name="seerr">Seerr client.</param>
    /// <param name="authorizationContext">Resolves the calling Jellyfin user.</param>
    /// <param name="logger">Logger.</param>
    public SoupSeerrController(
        SeerrApiClient seerr,
        IAuthorizationContext authorizationContext,
        ILogger<SoupSeerrController> logger)
    {
        _seerr = seerr;
        _authorizationContext = authorizationContext;
        _logger = logger;
    }

    /// <summary>
    /// Whether Seerr is set up, whether it answers, and the Seerr user linked to the caller.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Status object.</returns>
    [HttpGet("Status")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Status(CancellationToken cancellationToken)
    {
        if (!SeerrApiClient.IsConfigured)
        {
            return Ok(new { configured = false, reachable = false, version = (string?)null, user = (SeerrUserInfo?)null, error = (string?)null });
        }

        string? version;
        try
        {
            version = await _seerr.GetVersionAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            _logger.LogWarning(ex, "Seerr status probe failed");
            return Ok(new { configured = true, reachable = false, version = (string?)null, user = (SeerrUserInfo?)null, error = ex.Message });
        }

        SeerrUserInfo? user = null;
        try
        {
            var seerrUser = await ResolveCallerAsync(cancellationToken).ConfigureAwait(false);
            user = seerrUser is null ? null : ToInfo(seerrUser);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogWarning(ex, "Seerr user lookup failed");
        }

        return Ok(new { configured = true, reachable = version is not null, version, user, error = (string?)null });
    }

    /// <summary>
    /// GET an allow-listed Seerr catalogue path (<c>search</c>, <c>discover/…</c>, <c>movie/…</c>,
    /// <c>tv/…</c>, <c>person/…</c>, <c>collection/…</c>, <c>genres/…</c>), query string included.
    /// Seerr's status and body come back as they are.
    /// </summary>
    /// <param name="path">Path under Seerr's <c>/api/v1</c>.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Seerr's JSON.</returns>
    [HttpGet("Browse/{**path}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> Browse([FromRoute] string path, CancellationToken cancellationToken)
    {
        if (!SeerrApiClient.IsConfigured)
        {
            return NotConfigured();
        }

        var clean = (path ?? string.Empty).Trim('/');
        var head = clean.Split('/', 2)[0];
        if (string.IsNullOrEmpty(head) || !BrowsePrefixes.Contains(head) || clean.Contains("..", StringComparison.Ordinal))
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "path_not_allowed", message = $"'{clean}' is not a browsable Seerr path" });
        }

        try
        {
            var response = await _seerr.SendAsync(HttpMethod.Get, clean + ForwardedQuery(), null, cancellationToken).ConfigureAwait(false);
            return PassThrough(response);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return Unreachable(ex);
        }
    }

    /// <summary>
    /// The caller's own Seerr requests (newest first).
    /// </summary>
    /// <param name="take">Page size.</param>
    /// <param name="skip">Offset.</param>
    /// <param name="filter">Seerr filter: all, pending, approved, processing, available, unavailable, failed…</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Seerr's request page, or an empty page when the caller has no Seerr account.</returns>
    [HttpGet("Requests")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Requests(
        [FromQuery] int take = 20,
        [FromQuery] int skip = 0,
        [FromQuery] string filter = "all",
        CancellationToken cancellationToken = default)
    {
        if (!SeerrApiClient.IsConfigured)
        {
            return NotConfigured();
        }

        try
        {
            var user = await ResolveCallerAsync(cancellationToken).ConfigureAwait(false);
            if (user is null)
            {
                return Content(
                    $$"""{"pageInfo":{"pages":0,"pageSize":{{Math.Clamp(take, 1, 100)}},"results":0,"page":1},"results":[]}""",
                    JsonContentType);
            }

            var query = $"request?take={Math.Clamp(take, 1, 100)}&skip={Math.Max(0, skip)}"
                        + $"&filter={Uri.EscapeDataString(filter)}&sort=added&sortDirection=desc&requestedBy={user.Id}";
            var response = await _seerr.SendAsync(HttpMethod.Get, query, null, cancellationToken).ConfigureAwait(false);
            return PassThrough(response);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return Unreachable(ex);
        }
    }

    /// <summary>
    /// Request a movie or show (or some of its seasons) as the caller's Seerr user. Seerr applies
    /// that user's permissions, quota and auto-approval.
    /// </summary>
    /// <param name="body">What to request.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Seerr's created request, or its error.</returns>
    [HttpPost("Request")]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> CreateRequest([FromBody] SeerrRequestBody body, CancellationToken cancellationToken)
    {
        if (!SeerrApiClient.IsConfigured)
        {
            return NotConfigured();
        }

        if (body is null || body.MediaId <= 0 || body.MediaType is not ("movie" or "tv"))
        {
            return BadRequest(new { error = "bad_request", message = "mediaType (movie|tv) and mediaId are required" });
        }

        try
        {
            var user = await ResolveCallerAsync(cancellationToken).ConfigureAwait(false);
            if (user is null)
            {
                return NotLinked();
            }

            var payload = new Dictionary<string, object?>
            {
                ["mediaType"] = body.MediaType,
                ["mediaId"] = body.MediaId,
                ["userId"] = user.Id,
                ["is4k"] = body.Is4k,
            };
            if (body.TvdbId is > 0)
            {
                payload["tvdbId"] = body.TvdbId;
            }

            if (body.MediaType == "tv")
            {
                // Seerr requires seasons for a show; "all" when the client didn't pick.
                payload["seasons"] = body.Seasons is { ValueKind: JsonValueKind.Array or JsonValueKind.String } seasons
                    ? seasons
                    : "all";
            }

            var response = await _seerr
                .SendAsync(HttpMethod.Post, "request", JsonSerializer.Serialize(payload), cancellationToken)
                .ConfigureAwait(false);
            if (response.IsSuccess)
            {
                _logger.LogInformation("Seerr request created for {MediaType} {MediaId} by Seerr user {UserId}", body.MediaType, body.MediaId, user.Id);
            }

            return PassThrough(response);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return Unreachable(ex);
        }
    }

    /// <summary>
    /// Withdraw one of the caller's own pending requests (request managers may delete any).
    /// </summary>
    /// <param name="requestId">Seerr request id.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>204 when deleted.</returns>
    [HttpDelete("Request/{requestId:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteRequest([FromRoute] int requestId, CancellationToken cancellationToken)
    {
        if (!SeerrApiClient.IsConfigured)
        {
            return NotConfigured();
        }

        try
        {
            var user = await ResolveCallerAsync(cancellationToken).ConfigureAwait(false);
            if (user is null)
            {
                return NotLinked();
            }

            var existing = await _seerr.SendAsync(HttpMethod.Get, $"request/{requestId}", null, cancellationToken).ConfigureAwait(false);
            if (existing.StatusCode == HttpStatusCode.NotFound)
            {
                return NotFound(new { error = "not_found", message = "Request not found" });
            }

            if (!existing.IsSuccess || existing.Json() is not { ValueKind: JsonValueKind.Object } request)
            {
                return PassThrough(existing);
            }

            var ownerId = request.TryGetProperty("requestedBy", out var owner)
                          && owner.ValueKind == JsonValueKind.Object
                          && owner.TryGetProperty("id", out var ownerIdElement)
                          && ownerIdElement.ValueKind == JsonValueKind.Number
                ? ownerIdElement.GetInt32()
                : -1;
            var status = request.TryGetProperty("status", out var statusElement) && statusElement.ValueKind == JsonValueKind.Number
                ? statusElement.GetInt32()
                : 0;
            const int Pending = 1;
            var manager = user.Has(SeerrUser.ManageRequests);
            if (!manager && (ownerId != user.Id || status != Pending))
            {
                return StatusCode(StatusCodes.Status403Forbidden, new { error = "forbidden", message = "Only your own pending requests can be withdrawn" });
            }

            var deleted = await _seerr.SendAsync(HttpMethod.Delete, $"request/{requestId}", null, cancellationToken).ConfigureAwait(false);
            return deleted.IsSuccess ? NoContent() : PassThrough(deleted);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return Unreachable(ex);
        }
    }

    /// <summary>
    /// Admin: try a Seerr URL and API key (blank fields fall back to the saved ones).
    /// </summary>
    /// <param name="body">Credentials to try.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Version plus the Seerr user matched to the admin, or the failure.</returns>
    [HttpPost("Test")]
    [Authorize(Policy = Policies.RequiresElevation)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Test([FromBody] SeerrTestBody? body, CancellationToken cancellationToken)
    {
        var baseUrl = body?.BaseUrl;
        var apiKey = body?.ApiKey;
        try
        {
            var version = await _seerr.GetVersionAsync(cancellationToken, baseUrl, apiKey).ConfigureAwait(false);
            if (version is null)
            {
                return Ok(new { ok = false, message = "Seerr answered, but not with a status; check the URL" });
            }

            // /auth/me needs the key, so it proves the key as well as the URL.
            var me = await _seerr.SendAsync(HttpMethod.Get, "auth/me", null, cancellationToken, baseUrl, apiKey).ConfigureAwait(false);
            if (!me.IsSuccess)
            {
                return Ok(new { ok = false, version, message = $"Seerr {(int)me.StatusCode}: the API key was not accepted" });
            }

            _seerr.ClearUserCache();
            return Ok(new { ok = true, version, message = $"Connected to Seerr {version}" });
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException or UriFormatException)
        {
            return Ok(new { ok = false, message = SecretRedactor.Redact(ex.Message) });
        }
    }

    private async Task<SeerrUser?> ResolveCallerAsync(CancellationToken cancellationToken)
    {
        var auth = await _authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        if (auth.UserId.Equals(Guid.Empty))
        {
            return null;
        }

        return await _seerr.ResolveUserAsync(auth.UserId, auth.User?.Username, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// The caller's query string, minus any Jellyfin credentials a client might have put there.
    /// </summary>
    private string ForwardedQuery()
    {
        var parts = new List<string>();
        foreach (var (key, values) in Request.Query)
        {
            if (StrippedQueryKeys.Contains(key))
            {
                continue;
            }

            foreach (var value in values)
            {
                parts.Add($"{Uri.EscapeDataString(key)}={Uri.EscapeDataString(value ?? string.Empty)}");
            }
        }

        return parts.Count == 0 ? string.Empty : "?" + string.Join('&', parts);
    }

    private static SeerrUserInfo ToInfo(SeerrUser user) => new()
    {
        Id = user.Id,
        DisplayName = user.DisplayName,
        Avatar = user.Avatar,
        Permissions = user.Permissions,
    };

    private IActionResult PassThrough(SeerrResponse response)
    {
        var body = string.IsNullOrWhiteSpace(response.Body) ? "{}" : response.Body;
        if (response.StatusCode == HttpStatusCode.NoContent)
        {
            return NoContent();
        }

        return new ContentResult
        {
            StatusCode = (int)response.StatusCode,
            Content = body,
            ContentType = JsonContentType,
        };
    }

    private ObjectResult NotConfigured()
        => StatusCode(StatusCodes.Status503ServiceUnavailable, new { error = "seerr_not_configured", message = "Seerr is not set up on this server" });

    private ObjectResult NotLinked()
        => StatusCode(StatusCodes.Status403Forbidden, new
        {
            error = "seerr_user_not_linked",
            message = "No Seerr account is linked to your Jellyfin account; sign in to Seerr with Jellyfin once",
        });

    private ObjectResult Unreachable(Exception ex)
    {
        _logger.LogWarning(ex, "Seerr unreachable");
        return StatusCode(StatusCodes.Status502BadGateway, new { error = "seerr_unreachable", message = SecretRedactor.Redact(ex.Message) });
    }
}
