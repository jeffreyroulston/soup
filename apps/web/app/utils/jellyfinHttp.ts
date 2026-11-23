// Pure helpers shared by the browser client and the Nitro exchange (no Nuxt imports).

export const CLIENT_NAME = 'Soup'
export const DEVICE_NAME = 'Soup Web'
export const CLIENT_VERSION = '0.1.0'

export const TICKS_PER_SECOND = 10_000_000

/** `Authorization: MediaBrowser …` value; the token is omitted before sign-in. */
export function mediaBrowserAuth(deviceId: string, token?: string): string {
  const parts = [
    `Client="${CLIENT_NAME}"`,
    `Device="${DEVICE_NAME}"`,
    `DeviceId="${deviceId}"`,
    `Version="${CLIENT_VERSION}"`,
  ]
  if (token) parts.push(`Token="${token}"`)
  return `MediaBrowser ${parts.join(', ')}`
}

/** `baseUrl` + `path` (leading slash optional) + query, without allocating a URL object. */
export function jellyfinUrl(baseUrl: string, path: string, query?: Record<string, string>): string {
  const url = `${baseUrl}/${path.replace(/^\//, '')}`
  if (!query) return url
  const search = new URLSearchParams(query).toString()
  return search ? `${url}?${search}` : url
}

/**
 * Jellyfin user profile picture URL. Returns null when `primaryImageTag` is explicitly `null`
 * (the server confirmed no avatar is set); `undefined` omits `tag` so older stored sessions
 * still attempt to load the image.
 */
export function userAvatarUrl(
  baseUrl?: string | null,
  userId?: string | null,
  primaryImageTag?: string | null,
  maxHeight = 256,
): string | null {
  if (!baseUrl || !userId || primaryImageTag === null) return null
  const query: Record<string, string> = { maxHeight: String(maxHeight) }
  if (primaryImageTag) query.tag = primaryImageTag
  return jellyfinUrl(baseUrl, `Users/${userId}/Images/Primary`, query)
}

export function secondsToTicks(seconds: number): number {
  return Math.max(0, Math.round(seconds * TICKS_PER_SECOND))
}

export function ticksToSeconds(ticks: number): number {
  return ticks / TICKS_PER_SECOND
}
