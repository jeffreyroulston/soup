import type { NuxtApp } from '#app'
import type { JellyfinSessionPayload } from '~/types/jellyfin'

/** Whole-library scans can take a while on big servers; past this, give up. */
const REQUEST_TIMEOUT_MS = 30_000

function createJellyfinClient() {
  const { jellyfin, reexchange } = useAuthSession()

  function requireSession(): JellyfinSessionPayload {
    if (!jellyfin.value) throw new Error('Not signed in to Jellyfin')
    return jellyfin.value
  }

  function url(path: string, query?: Record<string, string>): string {
    return jellyfinUrl(requireSession().baseUrl, path, query)
  }

  /** Same as `url`, with the token in the query for <img>, <video> and <track> sources. */
  function mediaUrl(path: string, query: Record<string, string> = {}): string | null {
    const session = jellyfin.value
    if (!session) return null
    return jellyfinUrl(session.baseUrl, path, { ...query, api_key: session.accessToken })
  }

  async function request(
    method: string,
    path: string,
    options: { query?: Record<string, string>, body?: unknown } = {},
    retried = false,
  ): Promise<Response> {
    const session = requireSession()
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Authorization': mediaBrowserAuth(session.deviceId, session.accessToken),
      'X-Emby-Token': session.accessToken,
    }
    if (options.body !== undefined) headers['Content-Type'] = 'application/json'
    const response = await fetch(jellyfinUrl(session.baseUrl, path, options.query), {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      // A server that accepts the connection but never answers reads as "isn't responding".
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
    if (response.status === 401 && !retried) {
      await reexchange(session.accessToken)
      return request(method, path, options, true)
    }
    return response
  }

  /** JSON GET. Caching and de-duplication happen a level up, in TanStack Query. */
  async function get<T>(path: string, query?: Record<string, string>): Promise<T> {
    const response = await request('GET', path, { query })
    if (!response.ok) throw new Error(`Jellyfin ${response.status} for ${path}`)
    return response.json() as Promise<T>
  }

  function send(
    method: 'POST' | 'DELETE',
    path: string,
    options: { query?: Record<string, string>, body?: unknown } = {},
  ): Promise<Response> {
    return request(method, path, options)
  }

  return {
    jellyfin,
    requireSession,
    url,
    mediaUrl,
    get,
    send,
  }
}

export type JellyfinClient = ReturnType<typeof createJellyfinClient>

const clients = new WeakMap<NuxtApp, JellyfinClient>()

/** One client per app, so nothing is rebuilt per component. */
export function useJellyfinClient(): JellyfinClient {
  const nuxtApp = useNuxtApp()
  let client = clients.get(nuxtApp)
  if (!client) {
    client = createJellyfinClient()
    clients.set(nuxtApp, client)
  }
  return client
}
