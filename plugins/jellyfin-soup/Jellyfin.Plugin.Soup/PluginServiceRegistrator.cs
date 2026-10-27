using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;
using Jellyfin.Plugin.Soup.Services;

namespace Jellyfin.Plugin.Soup;

/// <summary>
/// Registers plugin services into Jellyfin DI.
/// </summary>
public class PluginServiceRegistrator : IPluginServiceRegistrator
{
    /// <inheritdoc />
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        serviceCollection.AddHttpClient(SoupApiClient.HttpClientName);
        serviceCollection.AddHttpClient(TailscaleApiClient.HttpClientName);
        // Catalogue reads should fail fast: a slow Seerr must not hold a Jellyfin request thread for long.
        serviceCollection.AddHttpClient(SeerrApiClient.HttpClientName, client => client.Timeout = TimeSpan.FromSeconds(20));
        serviceCollection.AddSingleton<SoupApiClient>();
        serviceCollection.AddSingleton<TailscaleApiClient>();
        serviceCollection.AddSingleton<SeerrApiClient>();
        serviceCollection.AddSingleton<AssertionVerifier>();
        serviceCollection.AddSingleton<AssertionReplayStore>();
        serviceCollection.AddSingleton<EntitlementService>();
        serviceCollection.AddSingleton<UserLinkService>();
    }
}
