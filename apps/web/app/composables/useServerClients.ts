import type { JellyfinApi } from '~/composables/useJellyfin'
import type { JellyfinClient, SessionSource } from '~/composables/useJellyfinClient'

type ServerClient = { client: JellyfinClient, api: JellyfinApi }

const caches = new WeakMap<object, Map<string, ServerClient>>()

/**
 * Clients and APIs for any server in `useServers().entries`, by `ServerEntry.key`, without
 * switching to it. Roster servers sign in on first use with a token kept for this tab;
 * directly added servers use their saved token.
 */
export function useServerClients() {
  const nuxtApp = useNuxtApp()
  const auth = useAuthSession()
  let cache = caches.get(nuxtApp)
  if (!cache) {
    cache = new Map()
    caches.set(nuxtApp, cache)
  }

  function sourceFor(key: string): SessionSource {
    const split = key.indexOf(':')
    const kind = key.slice(0, split)
    const id = key.slice(split + 1)
    if (kind === 'soup') {
      return {
        current: () => (auth.activeSoupServerId.value === id ? auth.jellyfin.value : auth.pool.value[id] ?? null),
        ensure: () => auth.soupSession(id),
        renew: failedToken => auth.soupSession(id, failedToken),
      }
    }
    if (kind === 'direct') {
      return {
        current: () => {
          const server = auth.savedServers.value.find(entry => entry.id === id)
          return server ? savedSession(server) : null
        },
        ensure: () => auth.directSession(id),
        renew: failedToken => auth.directSession(id, failedToken),
      }
    }
    throw new Error(`Unknown server key: ${key}`)
  }

  function entryFor(key: string): ServerClient {
    let entry = cache!.get(key)
    if (!entry) {
      const client = createJellyfinClient(sourceFor(key))
      entry = { client, api: createJellyfin(client) }
      cache!.set(key, entry)
    }
    return entry
  }

  /** The client for `key`; its `mediaUrl` is null until something has signed it in. */
  function clientFor(key: string): JellyfinClient {
    return entryFor(key).client
  }

  /** The API for `key`, once there's a session to call it with. */
  async function apiFor(key: string): Promise<JellyfinApi> {
    const entry = entryFor(key)
    await entry.client.ensure()
    return entry.api
  }

  return { clientFor, apiFor }
}
