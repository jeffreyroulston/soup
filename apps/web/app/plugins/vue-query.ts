import { QueryClient, VueQueryPlugin } from '@tanstack/vue-query'

/** Errors from `useJellyfinClient` read "Jellyfin <status> for <path>"; 4xx won't fix itself on retry. */
function isClientError(error: unknown): boolean {
  return error instanceof Error && /^Jellyfin 4\d\d /.test(error.message)
}

export default defineNuxtPlugin((nuxtApp) => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        // Fresh for a minute: back/forward navigation renders from memory without a request.
        staleTime: 60_000,
        gcTime: 5 * 60_000,
        refetchOnWindowFocus: false,
        retry: (failureCount, error) => failureCount < 2 && !isClientError(error),
      },
    },
  })
  nuxtApp.vueApp.use(VueQueryPlugin, { queryClient })
  // Also reachable as `useNuxtApp().$queryClient` outside component setup (middleware, async code).
  return { provide: { queryClient } }
})
