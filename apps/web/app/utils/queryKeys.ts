import type { LibrarySort } from '~/composables/useJellyfin'

/** Every Jellyfin query lives under this root, so one invalidation refreshes all of them. */
const root = ['jellyfin'] as const

export const queryKeys = {
  all: root,
  libraries: () => [...root, 'libraries'] as const,
  home: () => [...root, 'home'] as const,
  homeCollection: () => [...root, 'home', 'collection'] as const,
  homeExtras: () => [...root, 'home', 'extras'] as const,
  curatedCollection: (id: string) => [...root, 'curated', id] as const,
  homeGenres: () => [...root, 'home', 'genres'] as const,
  homeBecauseYouWatched: () => [...root, 'home', 'becauseYouWatched'] as const,
  item: (id: string) => [...root, 'item', id] as const,
  similar: (id: string) => [...root, 'item', id, 'similar'] as const,
  mediaSegments: (id: string) => [...root, 'item', id, 'segments'] as const,
  extras: (id: string) => [...root, 'item', id, 'extras'] as const,
  seasons: (seriesId: string) => [...root, 'series', seriesId, 'seasons'] as const,
  episodes: (seriesId: string, seasonId: string | null) =>
    [...root, 'series', seriesId, 'episodes', seasonId ?? 'all'] as const,
  seriesNextUp: (seriesId: string) => [...root, 'series', seriesId, 'nextUp'] as const,
  libraryItems: (id: string, sort: LibrarySort) => [...root, 'library', id, 'items', sort] as const,
  libraryTotal: (id: string) => [...root, 'library', id, 'total'] as const,
  libraryGenres: (id: string) => [...root, 'library', id, 'genres'] as const,
  search: (term: string) => [...root, 'search', term] as const,
  personItems: (personId: string) => [...root, 'person', personId] as const,
}
