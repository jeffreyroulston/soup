import { normalizeServerUrl } from '~/composables/useAuthSession'

export type DiscoveredServer = {
  /** Jellyfin's own server id, so two addresses for one server show once. */
  id: string
  name: string
  version: string
  /** Base URL that answered, ready for direct sign-in. */
  url: string
  host: string
}

const PROBE_TIMEOUT_MS = 2500

/** Loopback, RFC 1918, link-local and `.local` hosts. */
function isLocalHost(hostname: string): boolean {
  return hostname === 'localhost'
    || hostname.endsWith('.local')
    || /^127\./.test(hostname)
    || /^10\./.test(hostname)
    || /^192\.168\./.test(hostname)
    || /^172\.(1[6-9]|2\d|3[01])\./.test(hostname)
    || /^169\.254\./.test(hostname)
}

/**
 * Addresses worth probing. Browsers can't send Jellyfin's UDP discovery broadcast, so this
 * checks the servers we already know about and, when the app itself is served from the LAN
 * (e.g. the NAS Docker image), Jellyfin's default ports on that same host.
 */
function candidates(known: Array<string | null | undefined>): string[] {
  const urls = known.filter((url): url is string => !!url?.trim()).map(normalizeServerUrl)
  const { hostname, protocol } = location
  // Probing private addresses from a public origin triggers the browser's local-network prompt.
  if (isLocalHost(hostname)) {
    urls.push(`http://${hostname}:8096`, `https://${hostname}:8920`)
    if (hostname !== 'localhost') urls.push('http://localhost:8096')
  }
  // An https page can't reach http servers (mixed content), so don't bother asking.
  return [...new Set(urls)].filter(url => protocol !== 'https:' || url.startsWith('https:'))
}

async function probe(url: string): Promise<DiscoveredServer | null> {
  try {
    const response = await fetch(`${url}/System/Info/Public`, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    })
    if (!response.ok) return null
    const info = await response.json() as { Id?: string, ServerName?: string, Version?: string }
    if (!info.Id) return null
    return {
      id: info.Id,
      name: info.ServerName || new URL(url).host,
      version: info.Version ?? '',
      url,
      host: new URL(url).host,
    }
  }
  catch {
    return null
  }
}

/** Jellyfin servers this browser can reach right now, in candidate order. */
export async function discoverServers(known: Array<string | null | undefined>): Promise<DiscoveredServer[]> {
  const found = await Promise.all(candidates(known).map(probe))
  const byId = new Map<string, DiscoveredServer>()
  for (const server of found) {
    if (server && !byId.has(server.id)) byId.set(server.id, server)
  }
  return [...byId.values()]
}
