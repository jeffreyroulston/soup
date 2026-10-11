import { queryOptions, useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'
import type { QueryClient } from '@tanstack/vue-query'
import type { JellyfinItem, JellyfinShelf } from '~/types/jellyfin'
import type { LibrarySort } from '~/composables/useJellyfin'

/**
 * Query options for every Jellyfin read, keyed by `queryKeys`. Pages pass these to
 * `useQuery`, or `fetchQuery`/`prefetchQuery` when they need data imperatively.
 */
export function useJellyfinQueries() {
  const api = useJellyfin()
  return {
    libraries: () => queryOptions({
      queryKey: queryKeys.libraries(),
      queryFn: api.getLibraries,
    }),
    home: () => queryOptions({
      queryKey: queryKeys.home(),
      queryFn: api.getHome,
      // Continue Watching moves when something else plays, so check again on return to the tab.
      refetchOnWindowFocus: true,
    }),
    homeExtras: () => queryOptions({
      queryKey: queryKeys.homeExtras(),
      queryFn: api.getHomeExtras,
    }),
    homeCollection: () => queryOptions({
      queryKey: queryKeys.homeCollection(),
      queryFn: api.getHomeCollection,
      // A whole-library match; the daily pick doesn't need it redone often.
      staleTime: 30 * 60_000,
    }),
    curatedCollection: (id: string) => queryOptions({
      queryKey: queryKeys.curatedCollection(id),
      queryFn: () => api.getCuratedCollection(id),
    }),
    // Optional rows: an error just leaves them out.
    homeGenres: () => queryOptions({
      queryKey: queryKeys.homeGenres(),
      queryFn: () => api.getGenreShelves().catch((): JellyfinShelf[] => []),
      // Picks rotate daily and the genre tally is a whole-library scan; no need to redo it often.
      staleTime: 30 * 60_000,
    }),
    homeBecauseYouWatched: () => queryOptions({
      queryKey: queryKeys.homeBecauseYouWatched(),
      queryFn: () => api.getBecauseYouWatched().catch((): JellyfinShelf[] => []),
    }),
    item: (id: string) => queryOptions({
      queryKey: queryKeys.item(id),
      queryFn: () => api.getItem(id),
    }),
    similar: (id: string) => queryOptions({
      queryKey: queryKeys.similar(id),
      // Related is optional: an error just leaves the row out.
      queryFn: () => api.getSimilar(id).catch((): JellyfinItem[] => []),
    }),
    mediaSegments: (id: string) => queryOptions({
      queryKey: queryKeys.mediaSegments(id),
      queryFn: () => api.getMediaSegments(id),
      // Markers only change when the server re-analyses the file.
      staleTime: 30 * 60_000,
    }),
    extras: (item: Pick<JellyfinItem, 'id' | 'localTrailerCount' | 'specialFeatureCount'>) => queryOptions({
      queryKey: queryKeys.extras(item.id),
      // Extras are optional: an error just leaves the row out.
      queryFn: () => api.getExtras(item).catch((): JellyfinItem[] => []),
    }),
    seasons: (seriesId: string) => queryOptions({
      queryKey: queryKeys.seasons(seriesId),
      queryFn: () => api.getSeasons(seriesId),
    }),
    episodes: (seriesId: string, seasonId: string | null) => queryOptions({
      queryKey: queryKeys.episodes(seriesId, seasonId),
      queryFn: () => api.getEpisodes(seriesId, seasonId ?? undefined),
    }),
    seriesNextUp: (seriesId: string) => queryOptions({
      queryKey: queryKeys.seriesNextUp(seriesId),
      queryFn: () => api.getSeriesNextUp(seriesId).catch(() => null),
    }),
    // A library's id fixes its collection type, so the type isn't part of these keys.
    libraryItems: (id: string, sort: LibrarySort, collectionType?: string | null) => queryOptions({
      queryKey: queryKeys.libraryItems(id, sort),
      queryFn: () => api.getLibraryItems(id, sort, collectionType),
    }),
    libraryTotal: (id: string, collectionType?: string | null) => queryOptions({
      queryKey: queryKeys.libraryTotal(id),
      queryFn: () => api.getLibraryTotal(id, collectionType),
    }),
    libraryGenres: (id: string, collectionType?: string | null) => queryOptions({
      queryKey: queryKeys.libraryGenres(id),
      queryFn: () => api.getLibraryGenreCounts(id, collectionType),
    }),
    search: (term: string) => queryOptions({
      queryKey: queryKeys.search(term),
      queryFn: () => api.search(term),
    }),
    personItems: (personId: string) => queryOptions({
      queryKey: queryKeys.personItems(personId),
      queryFn: () => api.getPersonItems(personId),
    }),
  }
}

/** The signed-in user's libraries (nav, search's Browse grid, library titles). */
export function useLibraries() {
  const { jellyfin } = useAuthSession()
  const queries = useJellyfinQueries()
  const query = useQuery(computed(() => ({
    ...queries.libraries(),
    enabled: Boolean(jellyfin.value),
  })))
  return {
    libraries: computed(() => query.data.value ?? []),
    /** False until the first response, so the nav can hold space for the tabs. */
    loaded: computed(() => query.isSuccess.value),
  }
}

/**
 * Applies `patch` to every cached copy of item `id` (home rows, library grid, item
 * page…), returning the same reference wherever nothing changed.
 */
function patchItemIn(value: unknown, id: string, patch: Partial<JellyfinItem>): unknown {
  if (Array.isArray(value)) {
    let changed = false
    const next = value.map((entry) => {
      const patched = patchItemIn(entry, id, patch)
      if (patched !== entry) changed = true
      return patched
    })
    return changed ? next : value
  }
  if (!value || typeof value !== 'object') return value
  const record = value as Record<string, unknown>
  if (record.id === id && typeof record.type === 'string') return { ...record, ...patch }
  let changed = false
  const next: Record<string, unknown> = {}
  for (const [key, entry] of Object.entries(record)) {
    const patched = patchItemIn(entry, id, patch)
    if (patched !== entry) changed = true
    next[key] = patched
  }
  return changed ? next : value
}

/** Toggle mutation that updates the UI at once, rolls back on error and then refetches. */
function useItemToggle(
  queryClient: QueryClient,
  write: (id: string, value: boolean) => Promise<void>,
  field: 'isFavorite' | 'played',
) {
  return useMutation({
    mutationFn: ({ id, value }: { id: string, value: boolean }) => write(id, value),
    onMutate: async ({ id, value }) => {
      await queryClient.cancelQueries({ queryKey: queryKeys.all })
      const snapshot = queryClient.getQueriesData({ queryKey: queryKeys.all })
      queryClient.setQueriesData({ queryKey: queryKeys.all }, data => patchItemIn(data, id, { [field]: value }))
      return { snapshot }
    },
    onError: (_error, _vars, context) => {
      for (const [key, data] of context?.snapshot ?? []) queryClient.setQueryData(key, data)
    },
    // Watched state feeds Next Up, progress and episode lists, so refetch whatever is on screen.
    onSettled: () => queryClient.invalidateQueries({ queryKey: queryKeys.all }),
  })
}

export function useFavoriteMutation() {
  return useItemToggle(useQueryClient(), useJellyfin().setFavorite, 'isFavorite')
}

export function usePlayedMutation() {
  return useItemToggle(useQueryClient(), useJellyfin().setPlayed, 'played')
}

/** Warms an item page's main query (e.g. on card hover) so navigating there is instant. */
export function usePrefetchItem() {
  const queryClient = useQueryClient()
  const queries = useJellyfinQueries()
  return (id: string) => {
    void queryClient.prefetchQuery(queries.item(id))
  }
}
