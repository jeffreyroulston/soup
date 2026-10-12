import type { QueryClient } from '@tanstack/vue-query'
import type { NuxtApp } from '#app'

type ServerStatusState = {
  /** The server itself can't be reached (not just one failed request). */
  offline: boolean
  kind: ConnectionErrorKind | null
  /** Raw text of the last failure, for the collapsed details. */
  detail: string
  /** When the next automatic reconnect attempt runs (ms since epoch). */
  retryAt: number | null
  attempt: number
  probing: boolean
  /** Full-page error states on screen; the banner stays out of their way. */
  fullPageErrors: number
}

const PROBE_TIMEOUT_MS = 8000

function createServerStatus(nuxtApp: NuxtApp) {
  const state = useState<ServerStatusState>('server-status', () => ({
    offline: false,
    kind: null,
    detail: '',
    retryAt: null,
    attempt: 0,
    probing: false,
    fullPageErrors: 0,
  }))
  const auth = useAuthSession()
  let timer: ReturnType<typeof setTimeout> | null = null

  function clearTimer() {
    if (timer) clearTimeout(timer)
    timer = null
  }

  function schedule() {
    clearTimer()
    const delay = retryDelaySeconds(state.value.attempt) * 1000
    state.value.retryAt = Date.now() + delay
    timer = setTimeout(() => void probe(), delay)
  }

  /** Back online: everything on screen loads again. */
  function recover() {
    clearTimer()
    const wasOffline = state.value.offline
    state.value.offline = false
    state.value.kind = null
    state.value.detail = ''
    state.value.retryAt = null
    state.value.attempt = 0
    if (wasOffline) {
      const queryClient = nuxtApp.$queryClient as QueryClient
      void queryClient.invalidateQueries()
    }
  }

  /** Any answer from the server's public endpoint means it's reachable again. */
  async function probe() {
    const baseUrl = auth.jellyfin.value?.baseUrl
    if (!baseUrl) {
      recover()
      return
    }
    state.value.probing = true
    state.value.retryAt = null
    try {
      await fetch(jellyfinUrl(baseUrl, 'System/Info/Public'), { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
      recover()
    }
    catch (error) {
      if (!state.value.offline) return
      state.value.kind = classifyError(error) === 'timeout' ? 'timeout' : 'unreachable'
      state.value.attempt += 1
      schedule()
    }
    finally {
      state.value.probing = false
    }
  }

  /** A request failed; only server-wide failures take the app offline. */
  function report(error: unknown) {
    if (isMockMode()) return
    const kind = classifyError(error)
    if (!OFFLINE_KINDS.includes(kind)) return
    state.value.kind = kind
    state.value.detail = errorDetail(error)
    if (state.value.offline) return
    state.value.offline = true
    state.value.attempt = 0
    schedule()
  }

  /** A request succeeded, so the server is back (whatever the probe last saw). */
  function reportOk() {
    if (state.value.offline) recover()
  }

  function retryNow() {
    if (state.value.probing) return
    clearTimer()
    void probe()
  }

  if (import.meta.client) {
    window.addEventListener('offline', () => report(new TypeError('The device went offline')))
    window.addEventListener('online', () => {
      if (state.value.offline) retryNow()
    })
  }

  return {
    state: readonly(state),
    report,
    reportOk,
    retryNow,
    /** Called by full-page error states as they mount/unmount. */
    trackFullPageError(delta: 1 | -1) {
      state.value.fullPageErrors = Math.max(0, state.value.fullPageErrors + delta)
    },
  }
}

export type ServerStatus = ReturnType<typeof createServerStatus>

const statuses = new WeakMap<NuxtApp, ServerStatus>()

/** App-wide reachability of the current Jellyfin server, with automatic reconnects. */
export function useServerStatus(): ServerStatus {
  const nuxtApp = useNuxtApp()
  let status = statuses.get(nuxtApp)
  if (!status) {
    status = createServerStatus(nuxtApp)
    statuses.set(nuxtApp, status)
  }
  return status
}
