import type {
  SeerrDetails,
  SeerrMediaType,
  SeerrRequest,
  SeerrRequestFilter,
  SeerrRequestPayload,
  SeerrRequestsPage,
  SeerrSearchResults,
  SeerrStatus,
} from '~/types/seerr'
import type { JellyfinClient } from '~/composables/useJellyfinClient'
import { isMockMode } from '~/utils/mockMode'
import {
  mockSeerrCancelRequest,
  mockSeerrCreateRequest,
  mockSeerrDetails,
  mockSeerrDiscover,
  mockSeerrRequests,
  mockSeerrSearch,
  mockSeerrStatus,
} from '~/utils/mockSeerr'

/** Where the Soup plugin exposes Seerr on the Jellyfin server. */
const BASE = 'SoupSeerr'

/**
 * Seerr through the active server's Soup plugin. Every call carries the Jellyfin session; the
 * plugin maps it to the user's Seerr account, so requests are theirs and nothing here holds a
 * Seerr key. Errors are `SeerrError`s, which the app-wide reachability check leaves alone: a
 * down Seerr is not a down Jellyfin.
 */
export function createSeerr(client: JellyfinClient) {
  const mock = isMockMode()

  async function fail(response: Response, path: string): Promise<never> {
    let code = `http_${response.status}`
    let message = `Seerr ${response.status} for ${path}`
    try {
      const body = await response.json() as { error?: unknown, message?: unknown }
      if (typeof body.error === 'string' && body.error) code = body.error
      if (typeof body.message === 'string' && body.message) message = body.message
      else if (typeof body.error === 'string' && body.error) message = body.error
    }
    catch {
      // Not JSON; keep the status line.
    }
    throw new SeerrError(response.status, code, message)
  }

  async function call<T>(
    method: 'GET' | 'POST' | 'DELETE',
    path: string,
    options: { query?: Record<string, string>, body?: unknown } = {},
  ): Promise<T> {
    const response = await client.send(method, `${BASE}/${path}`, options)
    if (!response.ok) await fail(response, path)
    if (response.status === 204) return undefined as T
    return response.json() as Promise<T>
  }

  /** A Seerr catalogue read (`search`, `discover/…`, `movie/…`, `tv/…`), raw JSON. */
  function browse(path: string, query: Record<string, string> = {}): Promise<unknown> {
    return call('GET', `Browse/${path}`, { query })
  }

  async function status(): Promise<SeerrStatus> {
    if (mock) return mapSeerrStatus(mockSeerrStatus())
    return mapSeerrStatus(await call('GET', 'Status'))
  }

  async function search(term: string, page = 1): Promise<SeerrSearchResults> {
    const trimmed = term.trim()
    if (!trimmed) return { page: 1, totalPages: 0, totalResults: 0, titles: [], people: [] }
    if (mock) return mapSeerrResults(mockSeerrSearch(trimmed))
    return mapSeerrResults(await browse('search', { query: trimmed, page: String(page) }))
  }

  /** `discover/trending`, `discover/movies`, `discover/tv`, `discover/movies/upcoming`… */
  async function discover(path: string, page = 1): Promise<SeerrSearchResults> {
    if (mock) return mapSeerrResults(mockSeerrDiscover(path))
    return mapSeerrResults(await browse(path, { page: String(page) }))
  }

  async function details(mediaType: SeerrMediaType, tmdbId: number): Promise<SeerrDetails> {
    const raw = mock ? mockSeerrDetails(mediaType, tmdbId) : await browse(`${mediaType}/${tmdbId}`)
    const mapped = mapSeerrDetails(raw, mediaType)
    if (!mapped) throw new SeerrError(404, 'not_found', 'Seerr has no such title')
    return mapped
  }

  async function myRequests(filter: SeerrRequestFilter = 'all', take = 20, skip = 0): Promise<SeerrRequestsPage> {
    const raw = mock
      ? mockSeerrRequests(filter)
      : await call<unknown>('GET', 'Requests', { query: { filter, take: String(take), skip: String(skip) } })
    const page = raw && typeof raw === 'object' ? raw as { pageInfo?: { results?: number, pages?: number }, results?: unknown[] } : {}
    const requests = (page.results ?? []).map(entry => mapSeerrRequest(entry)).filter((entry): entry is SeerrRequest => entry !== null)
    return {
      total: page.pageInfo?.results ?? requests.length,
      pages: page.pageInfo?.pages ?? 1,
      requests,
    }
  }

  async function createRequest(payload: SeerrRequestPayload): Promise<SeerrRequest | null> {
    const raw = mock ? mockSeerrCreateRequest(payload) : await call<unknown>('POST', 'Request', { body: payload })
    return mapSeerrRequest(raw, { mediaType: payload.mediaType, tmdbId: payload.mediaId })
  }

  async function cancelRequest(id: number): Promise<void> {
    if (mock) {
      mockSeerrCancelRequest(id)
      return
    }
    await call('DELETE', `Request/${id}`)
  }

  return { status, search, discover, details, myRequests, createRequest, cancelRequest }
}

export type SeerrApi = ReturnType<typeof createSeerr>

const apis = new WeakMap<object, SeerrApi>()

/** Seerr via the active server, one per app. */
export function useSeerr(): SeerrApi {
  const nuxtApp = useNuxtApp()
  let api = apis.get(nuxtApp)
  if (!api) {
    api = createSeerr(useJellyfinClient())
    apis.set(nuxtApp, api)
  }
  return api
}
