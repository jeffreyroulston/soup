/**
 * Runtime deployment config. A `soup.config.json` beside the built files lets an
 * operator point the app at their Identity server (and optionally prefill the
 * Jellyfin server or rename the app) without rebuilding. Missing file = build defaults.
 */
type SoupConfigFile = {
  soupIdentityBaseUrl?: string
  jellyfinUrl?: string
  appName?: string
}

export default defineNuxtPlugin(async () => {
  const config = useRuntimeConfig()
  const identity = useIdentityConfig()
  const build = String(config.public.soupIdentityBaseUrl)
  let file: string | null = null

  try {
    const res = await fetch(`${config.app.baseURL}soup.config.json`, { cache: 'no-store' })
    if (res.ok) {
      const json = (await res.json()) as SoupConfigFile
      if (typeof json.soupIdentityBaseUrl === 'string' && json.soupIdentityBaseUrl.trim()) {
        file = normalizeIdentityUrl(json.soupIdentityBaseUrl)
      }
      if (typeof json.jellyfinUrl === 'string') config.public.jellyfinUrl = json.jellyfinUrl
      if (typeof json.appName === 'string' && json.appName.trim()) config.public.appName = json.appName.trim()
    }
  }
  catch {
    // No runtime config: keep build-time values.
  }

  identity.initialize({ build, file })
})
