import { MutationCache, QueryCache, QueryClient, VueQueryPlugin } from '@tanstack/vue-query'
import type { ServerStatus } from '~/composables/useServerStatus'

/** Errors from `useJellyfinClient` read "Jellyfin <status> for <path>"; 4xx won't fix itself on retry. */
function isClientError(error: unknown): boolean {
  return error instanceof Error && /^Jellyfin 4\d\d /.test(error.message)
}

export default defineNuxtPlugin((nuxtApp) => {
  // Assigned below, before any query can run.
  let serverStatus: ServerStatus | undefined
  const status = (): ServerStatus => serverStatus!
  const queryClient: QueryClient = new QueryClient({
    // Every failure and success feeds the app-wide reachability, which shows the
    // offline banner and reconnects (then refetches) on its own.
    queryCache: new QueryCache({
      onError: error => status().report(error),
      onSuccess: () => status().reportOk(),
    }),
    mutationCache: new MutationCache({
      onError: error => status().report(error),
      onSuccess: () => status().reportOk(),
    }),
    defaultOptions: {
      queries: {
        // Fresh for a minute: back/forward navigation renders from memory without a request.
        staleTime: 60_000,
        gcTime: 5 * 60_000,
        refetchOnWindowFocus: false,
        // One quick retry for blips; once the server is known to be down, fail straight
        // away and let the reconnect loop bring it back.
        retry: (failureCount, error) =>
          failureCount < 1 && !isClientError(error) && !status().state.value.offline,
      },
    },
  })
  nuxtApp.vueApp.use(VueQueryPlugin, { queryClient })
  serverStatus = useServerStatus()
  // Also reachable as `useNuxtApp().$queryClient` outside component setup (middleware, async code).
  return { provide: { queryClient } }
})
