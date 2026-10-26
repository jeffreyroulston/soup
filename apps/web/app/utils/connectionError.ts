/** What went wrong talking to the server, in terms a person can act on. */
export type ConnectionErrorKind = 'unreachable' | 'timeout' | 'signedOut' | 'server' | 'notFound' | 'unknown'

/** Kinds that can clear up on their own, so they're retried automatically. */
export const RETRYABLE_KINDS: readonly ConnectionErrorKind[] = ['unreachable', 'timeout', 'server']

/** Kinds that mean the whole server is gone, not just one request. */
export const OFFLINE_KINDS: readonly ConnectionErrorKind[] = ['unreachable', 'timeout']

/** Seconds between automatic retries: 3, 6, 12, 24, then every 30. */
export function retryDelaySeconds(attempt: number): number {
  return Math.min(3 * 2 ** attempt, 30)
}

/**
 * Classifies a thrown error. `useJellyfinClient` throws "Jellyfin <status> for <path>"
 * for HTTP errors; fetch throws a TypeError when the server can't be reached, and
 * `AbortSignal.timeout` a DOMException named TimeoutError.
 */
export function classifyError(error: unknown): ConnectionErrorKind {
  if (error instanceof DOMException && (error.name === 'TimeoutError' || error.name === 'AbortError')) return 'timeout'
  // "Failed to fetch" (Chrome), "NetworkError when attempting to fetch resource." (Firefox), "Load failed" (Safari).
  if (error instanceof TypeError) return 'unreachable'
  const message = error instanceof Error ? error.message : typeof error === 'string' ? error : ''
  if (message === 'Not signed in to Jellyfin') return 'signedOut'
  const status = /^Jellyfin (\d{3}) /.exec(message)?.[1]
  if (status) {
    const code = Number(status)
    if (code === 401) return 'signedOut'
    if (code === 404) return 'notFound'
    // A proxy in front of a stopped server answers 502/503, and 504 when it stops answering.
    if (code === 502 || code === 503) return 'unreachable'
    if (code === 504) return 'timeout'
    if (code >= 500) return 'server'
    return 'unknown'
  }
  if (import.meta.client && navigator.onLine === false) return 'unreachable'
  return 'unknown'
}

export function errorCopy(kind: ConnectionErrorKind, serverName?: string | null): { title: string, message: string } {
  const server = serverName?.trim() || 'your server'
  switch (kind) {
    case 'unreachable':
      return {
        title: `Can't reach ${server}`,
        message: `Make sure ${server} is turned on and connected to your network, then try again.`,
      }
    case 'timeout':
      return {
        title: `${upperFirst(server)} isn't responding`,
        message: 'It\'s taking too long to answer. It may be busy or restarting.',
      }
    case 'signedOut':
      return { title: 'You\'ve been signed out', message: 'Sign in again to keep watching.' }
    case 'server':
      return {
        title: `${upperFirst(server)} ran into a problem`,
        message: 'Try again in a moment. If it keeps happening, check the server\'s logs.',
      }
    case 'notFound':
      return { title: 'This title isn\'t available', message: `It may have been removed from ${server}.` }
    default:
      return { title: 'Something went wrong', message: 'Try again in a moment.' }
  }
}

/** The raw text behind an error, for the collapsed details. */
export function errorDetail(error: unknown): string {
  if (error instanceof Error) return error.message || error.name
  return typeof error === 'string' ? error : ''
}

function upperFirst(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1)
}
