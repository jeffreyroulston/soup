/** What Seerr (Jellyseerr/Overseerr) tells us through the Soup plugin, in the app's own shapes. */

export type SeerrMediaType = 'movie' | 'tv'

/** Seerr `MediaStatus`: how much of a title the library holds. */
export const SEERR_MEDIA_STATUS = {
  UNKNOWN: 1,
  PENDING: 2,
  PROCESSING: 3,
  PARTIALLY_AVAILABLE: 4,
  AVAILABLE: 5,
  DELETED: 6,
} as const
export type SeerrMediaStatus = (typeof SEERR_MEDIA_STATUS)[keyof typeof SEERR_MEDIA_STATUS]

/** Seerr `MediaRequestStatus`: where a request stands with the approvers. */
export const SEERR_REQUEST_STATUS = {
  PENDING: 1,
  APPROVED: 2,
  DECLINED: 3,
  FAILED: 4,
  COMPLETED: 5,
} as const
export type SeerrRequestStatus = (typeof SEERR_REQUEST_STATUS)[keyof typeof SEERR_REQUEST_STATUS]

export type SeerrSeasonStatus = {
  seasonNumber: number
  status: SeerrMediaStatus
}

/** Seerr's record of a title: whether it's in the library and what's been asked for. Absent when nobody has touched it. */
export type SeerrMediaInfo = {
  id: number
  tmdbId: number
  tvdbId: number | null
  status: SeerrMediaStatus
  /** The Jellyfin item Seerr matched the title to, when it's in the library. */
  jellyfinMediaId: string | null
  seasons: SeerrSeasonStatus[]
  requests: SeerrRequest[]
}

export type SeerrRequester = {
  id: number
  displayName: string
  avatar: string | null
}

export type SeerrRequest = {
  id: number
  status: SeerrRequestStatus
  is4k: boolean
  createdAt: string
  updatedAt: string
  mediaType: SeerrMediaType
  tmdbId: number
  /** The title's library status, as of this request. */
  mediaStatus: SeerrMediaStatus
  /** Seasons this request covers (shows only). */
  seasons: SeerrSeasonStatus[]
  requestedBy: SeerrRequester | null
}

/** A movie or show as Seerr lists it: TMDB data plus library status. */
export type SeerrTitle = {
  tmdbId: number
  mediaType: SeerrMediaType
  title: string
  year: number | null
  releaseDate: string | null
  overview: string | null
  posterPath: string | null
  backdropPath: string | null
  /** TMDB score out of 10. */
  voteAverage: number | null
  mediaInfo: SeerrMediaInfo | null
}

export type SeerrPerson = {
  tmdbId: number
  name: string
  profilePath: string | null
  knownFor: SeerrTitle[]
}

export type SeerrSearchResults = {
  page: number
  totalPages: number
  totalResults: number
  titles: SeerrTitle[]
  people: SeerrPerson[]
}

export type SeerrSeason = {
  seasonNumber: number
  name: string
  episodeCount: number
  airDate: string | null
  posterPath: string | null
  overview: string | null
}

export type SeerrCastMember = {
  id: number
  name: string
  character: string | null
  profilePath: string | null
}

/** One title in full: what the detail page shows. */
export type SeerrDetails = SeerrTitle & {
  tagline: string | null
  /** Minutes: a movie's runtime, or a show's typical episode length. */
  runtime: number | null
  genres: string[]
  /** A show's airing status from TMDB (Returning Series, Ended…). */
  status: string | null
  contentRating: string | null
  imdbId: string | null
  tvdbId: number | null
  /** Shows: every season TMDB lists, specials (season 0) excluded. */
  seasons: SeerrSeason[]
  cast: SeerrCastMember[]
  networks: string[]
  trailerUrl: string | null
}

export type SeerrUser = {
  id: number
  displayName: string
  avatar: string | null
  /** Seerr's permission bitmask; see `seerrCanRequest`. */
  permissions: number
}

export type SeerrStatus = {
  /** The plugin has a Seerr URL and key; the Explore tab shows when true. */
  configured: boolean
  /** Seerr answered the plugin's probe. */
  reachable: boolean
  version: string | null
  /** The Seerr account linked to the signed-in Jellyfin user; null means they can browse but not request. */
  user: SeerrUser | null
  error: string | null
}

export type SeerrRequestPayload = {
  mediaType: SeerrMediaType
  mediaId: number
  tvdbId?: number | null
  /** Shows: season numbers, or 'all'. */
  seasons?: number[] | 'all'
  is4k?: boolean
}

export type SeerrRequestFilter = 'all' | 'pending' | 'approved' | 'processing' | 'available' | 'unavailable' | 'failed'

export type SeerrRequestsPage = {
  total: number
  pages: number
  requests: SeerrRequest[]
}
