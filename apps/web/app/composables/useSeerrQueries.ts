import { queryOptions, useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'
import type { SeerrMediaType, SeerrRequestFilter, SeerrRequestPayload } from '~/types/seerr'

/** Query options for every Seerr read, keyed under `queryKeys.seerr()`. */
export function useSeerrQueries() {
  const api = useSeerr()
  return {
    status: () => queryOptions({
      queryKey: queryKeys.seerrStatus(),
      queryFn: api.status,
      // Whether Seerr is set up rarely changes; the nav asks on every page.
      staleTime: 5 * 60_000,
      retry: seerrRetry,
    }),
    search: (term: string, page = 1) => queryOptions({
      queryKey: queryKeys.seerrSearch(term, page),
      queryFn: () => api.search(term, page),
      retry: seerrRetry,
    }),
    discover: (path: string, page = 1) => queryOptions({
      queryKey: queryKeys.seerrDiscover(path, page),
      queryFn: () => api.discover(path, page),
      // TMDB charts move slowly; library status on them refreshes with the page.
      staleTime: 10 * 60_000,
      retry: seerrRetry,
    }),
    details: (mediaType: SeerrMediaType, tmdbId: number) => queryOptions({
      queryKey: queryKeys.seerrTitle(mediaType, tmdbId),
      queryFn: () => api.details(mediaType, tmdbId),
      retry: seerrRetry,
    }),
    requests: (filter: SeerrRequestFilter = 'all', take = 20, skip = 0) => queryOptions({
      queryKey: queryKeys.seerrRequests(filter, skip),
      queryFn: () => api.myRequests(filter, take, skip),
      // Approvals and downloads happen elsewhere; look again when the tab comes back.
      refetchOnWindowFocus: true,
      retry: seerrRetry,
    }),
  }
}

/**
 * Whether the active server offers Seerr, and as whom. `available` drives the Explore tab;
 * it stays false until the plugin has answered, so the tab never flashes in and out.
 */
export function useSeerrStatus() {
  const { jellyfin } = useAuthSession()
  const queries = useSeerrQueries()
  const query = useQuery(computed(() => ({
    ...queries.status(),
    enabled: Boolean(jellyfin.value),
  })))
  const status = computed(() => query.data.value ?? null)
  return {
    status,
    loaded: computed(() => query.isSuccess.value || query.isError.value),
    available: computed(() => status.value?.configured === true),
    user: computed(() => status.value?.user ?? null),
    error: computed(() => query.error.value),
    refetch: query.refetch,
    canRequest: (mediaType: SeerrMediaType) => seerrCanRequest(status.value?.user ?? null, mediaType),
  }
}

/** Ask Seerr for a title; every Seerr read refreshes afterwards, since library status moved. */
export function useSeerrRequestMutation() {
  const api = useSeerr()
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (payload: SeerrRequestPayload) => api.createRequest(payload),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.seerr() }),
  })
}

export function useSeerrCancelMutation() {
  const api = useSeerr()
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: number) => api.cancelRequest(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.seerr() }),
  })
}
