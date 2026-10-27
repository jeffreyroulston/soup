// Pure helpers for Seerr data: mapping its JSON, TMDB image URLs, labels and permissions.
import type {
  SeerrCastMember,
  SeerrDetails,
  SeerrMediaInfo,
  SeerrMediaStatus,
  SeerrMediaType,
  SeerrPerson,
  SeerrRequest,
  SeerrRequestStatus,
  SeerrRequester,
  SeerrSearchResults,
  SeerrSeason,
  SeerrSeasonStatus,
  SeerrStatus,
  SeerrTitle,
  SeerrUser,
} from '~/types/seerr'
import { SEERR_MEDIA_STATUS, SEERR_REQUEST_STATUS } from '~/types/seerr'

/** A failed Seerr call: the plugin's or Seerr's own `{ error, message }`, with the HTTP status. */
export class SeerrError extends Error {
  constructor(
    public readonly status: number,
    /** Machine code: `seerr_not_configured`, `seerr_unreachable`, `seerr_user_not_linked`, or Seerr's own. */
    public readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = 'SeerrError'
  }
}

/** Retry only what can clear up: a down Seerr, not a declined request or a missing account. */
export function seerrRetry(failureCount: number, error: unknown): boolean {
  if (failureCount >= 1) return false
  return !(error instanceof SeerrError && error.status < 500)
}

/** Seerr permission bits (server/lib/permissions.ts). */
const PERMISSION = {
  ADMIN: 2,
  MANAGE_REQUESTS: 16,
  REQUEST: 32,
  REQUEST_MOVIE: 262144,
  REQUEST_TV: 524288,
} as const

function hasPermission(user: SeerrUser, bit: number): boolean {
  // JS bitwise ops are 32-bit signed; Seerr's bits stay well under that.
  return (user.permissions & PERMISSION.ADMIN) === PERMISSION.ADMIN || (user.permissions & bit) === bit
}

/** Whether Seerr would accept a request for this kind of title from the user. */
export function seerrCanRequest(user: SeerrUser | null, mediaType: SeerrMediaType): boolean {
  if (!user) return false
  if (hasPermission(user, PERMISSION.REQUEST) || hasPermission(user, PERMISSION.MANAGE_REQUESTS)) return true
  return hasPermission(user, mediaType === 'movie' ? PERMISSION.REQUEST_MOVIE : PERMISSION.REQUEST_TV)
}

type TmdbImageKind = 'poster' | 'backdrop' | 'profile'

const TMDB_SIZES: Record<TmdbImageKind, string> = {
  poster: 'w500',
  backdrop: 'w1280',
  profile: 'w185',
}

/**
 * A TMDB image URL for a Seerr `posterPath`/`backdropPath`/`profilePath`. Paths that are
 * already URLs (the mock catalogue's local posters) pass through.
 */
export function tmdbImage(path: string | null | undefined, kind: TmdbImageKind): string | null {
  if (!path) return null
  if (/^(https?:)?\/\//.test(path) || path.startsWith('/posters/') || path.startsWith('data:')) return path
  return `https://image.tmdb.org/t/p/${TMDB_SIZES[kind]}${path.startsWith('/') ? path : `/${path}`}`
}

type Json = Record<string, unknown>

function obj(value: unknown): Json | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Json : null
}

function str(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null
}

function num(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function arr(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

export function yearOf(date: string | null | undefined): number | null {
  const year = date ? Number(date.slice(0, 4)) : NaN
  return Number.isInteger(year) && year > 1800 ? year : null
}

function mediaStatus(value: unknown): SeerrMediaStatus {
  const n = num(value)
  return n != null && n >= 1 && n <= 6 ? n as SeerrMediaStatus : SEERR_MEDIA_STATUS.UNKNOWN
}

function requestStatus(value: unknown): SeerrRequestStatus {
  const n = num(value)
  return n != null && n >= 1 && n <= 5 ? n as SeerrRequestStatus : SEERR_REQUEST_STATUS.PENDING
}

function mapSeasonStatuses(value: unknown): SeerrSeasonStatus[] {
  return arr(value).flatMap((raw) => {
    const season = obj(raw)
    const seasonNumber = season ? num(season.seasonNumber) : null
    return season && seasonNumber != null ? [{ seasonNumber, status: mediaStatus(season.status) }] : []
  })
}

function mapRequester(raw: unknown): SeerrRequester | null {
  const user = obj(raw)
  const id = user ? num(user.id) : null
  if (!user || id == null) return null
  return {
    id,
    displayName: str(user.displayName) ?? str(user.username) ?? str(user.jellyfinUsername) ?? str(user.plexUsername) ?? `User ${id}`,
    avatar: str(user.avatar),
  }
}

/** A request as Seerr lists it. `fallbackType`/`fallbackTmdbId` cover `mediaInfo.requests`, where `media` is omitted. */
export function mapSeerrRequest(
  raw: unknown,
  fallback: { mediaType?: SeerrMediaType, tmdbId?: number, mediaStatus?: SeerrMediaStatus } = {},
): SeerrRequest | null {
  const request = obj(raw)
  const id = request ? num(request.id) : null
  if (!request || id == null) return null
  const media = obj(request.media)
  const type = media ? str(media.mediaType) : null
  const mediaType: SeerrMediaType | undefined = type === 'movie' || type === 'tv' ? type : fallback.mediaType
  const tmdbId = (media ? num(media.tmdbId) : null) ?? fallback.tmdbId
  if (!mediaType || tmdbId == null) return null
  return {
    id,
    status: requestStatus(request.status),
    is4k: request.is4k === true,
    createdAt: str(request.createdAt) ?? '',
    updatedAt: str(request.updatedAt) ?? str(request.createdAt) ?? '',
    mediaType,
    tmdbId,
    mediaStatus: media ? mediaStatus(request.is4k ? media.status4k : media.status) : fallback.mediaStatus ?? SEERR_MEDIA_STATUS.UNKNOWN,
    seasons: mapSeasonStatuses(request.seasons),
    requestedBy: mapRequester(request.requestedBy),
  }
}

export function mapSeerrMediaInfo(raw: unknown, mediaType: SeerrMediaType): SeerrMediaInfo | null {
  const info = obj(raw)
  const id = info ? num(info.id) : null
  const tmdbId = info ? num(info.tmdbId) : null
  if (!info || id == null || tmdbId == null) return null
  const status = mediaStatus(info.status)
  return {
    id,
    tmdbId,
    tvdbId: num(info.tvdbId),
    status,
    jellyfinMediaId: str(info.jellyfinMediaId),
    seasons: mapSeasonStatuses(info.seasons),
    requests: arr(info.requests)
      .map(request => mapSeerrRequest(request, { mediaType, tmdbId, mediaStatus: status }))
      .filter((request): request is SeerrRequest => request !== null),
  }
}

function mapTitle(raw: Json, mediaType: SeerrMediaType): SeerrTitle | null {
  const tmdbId = num(raw.id)
  const title = str(raw.title) ?? str(raw.name) ?? str(raw.originalTitle) ?? str(raw.originalName)
  if (tmdbId == null || !title) return null
  const releaseDate = str(raw.releaseDate) ?? str(raw.firstAirDate)
  return {
    tmdbId,
    mediaType,
    title,
    year: yearOf(releaseDate),
    releaseDate,
    overview: str(raw.overview),
    posterPath: str(raw.posterPath),
    backdropPath: str(raw.backdropPath),
    voteAverage: num(raw.voteAverage) || null,
    mediaInfo: mapSeerrMediaInfo(raw.mediaInfo, mediaType),
  }
}

/** A search or discover result: a title, a person, or (unknown kinds) null. */
export function mapSeerrResult(raw: unknown): SeerrTitle | SeerrPerson | null {
  const result = obj(raw)
  if (!result) return null
  const mediaType = str(result.mediaType)
  if (mediaType === 'movie' || mediaType === 'tv') return mapTitle(result, mediaType)
  if (mediaType === 'person') {
    const tmdbId = num(result.id)
    const name = str(result.name)
    if (tmdbId == null || !name) return null
    return {
      tmdbId,
      name,
      profilePath: str(result.profilePath),
      knownFor: arr(result.knownFor).map(mapSeerrResult).filter(isSeerrTitle),
    }
  }
  return null
}

export function isSeerrTitle(value: SeerrTitle | SeerrPerson | null): value is SeerrTitle {
  return value !== null && 'mediaType' in value
}

export function isSeerrPerson(value: SeerrTitle | SeerrPerson | null): value is SeerrPerson {
  return value !== null && 'knownFor' in value
}

export function mapSeerrResults(raw: unknown): SeerrSearchResults {
  const page = obj(raw)
  const results = arr(page?.results).map(mapSeerrResult)
  return {
    page: num(page?.page) ?? 1,
    totalPages: num(page?.totalPages) ?? 1,
    totalResults: num(page?.totalResults) ?? results.length,
    titles: results.filter(isSeerrTitle),
    people: results.filter(isSeerrPerson),
  }
}

function mapSeason(raw: unknown): SeerrSeason | null {
  const season = obj(raw)
  const seasonNumber = season ? num(season.seasonNumber) : null
  if (!season || seasonNumber == null) return null
  return {
    seasonNumber,
    name: str(season.name) ?? `Season ${seasonNumber}`,
    episodeCount: num(season.episodeCount) ?? 0,
    airDate: str(season.airDate),
    posterPath: str(season.posterPath),
    overview: str(season.overview),
  }
}

function mapCast(raw: unknown): SeerrCastMember | null {
  const member = obj(raw)
  const id = member ? num(member.id) : null
  const name = member ? str(member.name) : null
  if (!member || id == null || !name) return null
  return { id, name, character: str(member.character), profilePath: str(member.profilePath) }
}

/** The YouTube trailer TMDB lists first, if any. */
function trailerUrl(raw: Json): string | null {
  for (const video of arr(raw.relatedVideos)) {
    const entry = obj(video)
    if (!entry) continue
    const url = str(entry.url)
    const type = str(entry.type)?.toLowerCase()
    if (url && (type === 'trailer' || type === 'teaser') && /youtube|youtu\.be/.test(url)) return url
  }
  return null
}

function contentRating(raw: Json, mediaType: SeerrMediaType): string | null {
  if (mediaType === 'movie') {
    for (const release of arr(obj(raw.releases)?.results)) {
      const entry = obj(release)
      if (entry?.iso_3166_1 !== 'US') continue
      for (const date of arr(entry.release_dates)) {
        const certification = str(obj(date)?.certification)
        if (certification) return certification
      }
    }
    return null
  }
  for (const rating of arr(obj(raw.contentRatings)?.results)) {
    const entry = obj(rating)
    if (entry?.iso_3166_1 === 'US') return str(entry.rating)
  }
  return null
}

export function mapSeerrDetails(raw: unknown, mediaType: SeerrMediaType): SeerrDetails | null {
  const details = obj(raw)
  const title = details ? mapTitle(details, mediaType) : null
  if (!details || !title) return null
  const externalIds = obj(details.externalIds)
  const runtime = mediaType === 'movie'
    ? num(details.runtime)
    : arr(details.episodeRunTime).map(num).find((n): n is number => n != null && n > 0) ?? null
  return {
    ...title,
    tagline: str(details.tagline),
    runtime: runtime && runtime > 0 ? runtime : null,
    genres: arr(details.genres).map(genre => str(obj(genre)?.name)).filter((name): name is string => name !== null),
    status: mediaType === 'tv' ? str(details.status) : null,
    contentRating: contentRating(details, mediaType),
    imdbId: str(details.imdbId) ?? str(externalIds?.imdbId),
    tvdbId: num(externalIds?.tvdbId) ?? title.mediaInfo?.tvdbId ?? null,
    seasons: arr(details.seasons).map(mapSeason).filter((season): season is SeerrSeason => season !== null && season.seasonNumber > 0),
    cast: arr(obj(details.credits)?.cast).map(mapCast).filter((member): member is SeerrCastMember => member !== null).slice(0, 20),
    networks: arr(details.networks).map(network => str(obj(network)?.name)).filter((name): name is string => name !== null),
    trailerUrl: trailerUrl(details),
  }
}

export function mapSeerrStatus(raw: unknown): SeerrStatus {
  const status = obj(raw)
  const user = obj(status?.user)
  const userId = user ? num(user.id) : null
  return {
    configured: status?.configured === true,
    reachable: status?.reachable === true,
    version: str(status?.version),
    user: user && userId != null
      ? {
          id: userId,
          displayName: str(user.displayName) ?? `User ${userId}`,
          avatar: str(user.avatar),
          permissions: num(user.permissions) ?? 0,
        }
      : null,
    error: str(status?.error),
  }
}

/** Short label for where a title stands in the library, or null when it's simply not there. */
export function availabilityLabel(info: SeerrMediaInfo | null | undefined): string | null {
  switch (info?.status) {
    case SEERR_MEDIA_STATUS.AVAILABLE: return 'In your library'
    case SEERR_MEDIA_STATUS.PARTIALLY_AVAILABLE: return 'Partly in library'
    case SEERR_MEDIA_STATUS.PROCESSING: return 'On its way'
    case SEERR_MEDIA_STATUS.PENDING: return 'Requested'
    default: return null
  }
}

export type AvailabilityTone = 'ok' | 'partial' | 'pending'

export function availabilityTone(info: SeerrMediaInfo | null | undefined): AvailabilityTone | null {
  switch (info?.status) {
    case SEERR_MEDIA_STATUS.AVAILABLE: return 'ok'
    case SEERR_MEDIA_STATUS.PARTIALLY_AVAILABLE: return 'partial'
    case SEERR_MEDIA_STATUS.PROCESSING:
    case SEERR_MEDIA_STATUS.PENDING: return 'pending'
    default: return null
  }
}

export function isInLibrary(info: SeerrMediaInfo | null | undefined): boolean {
  return info?.status === SEERR_MEDIA_STATUS.AVAILABLE || info?.status === SEERR_MEDIA_STATUS.PARTIALLY_AVAILABLE
}

/** Whether the title (or, for a show, every season) is already there or on its way, so there's nothing left to request. */
export function nothingToRequest(info: SeerrMediaInfo | null | undefined, seasons: { seasonNumber: number }[] = []): boolean {
  if (!info) return false
  if (info.status === SEERR_MEDIA_STATUS.AVAILABLE) return true
  if (seasons.length === 0) {
    return info.status === SEERR_MEDIA_STATUS.PENDING || info.status === SEERR_MEDIA_STATUS.PROCESSING
  }
  return seasons.every(season => seasonStatus(info, season.seasonNumber) !== null)
}

/** A season's own status when Seerr has it: in the library, or covered by a request. */
export function seasonStatus(info: SeerrMediaInfo | null | undefined, seasonNumber: number): SeerrMediaStatus | null {
  if (!info) return null
  const own = info.seasons.find(season => season.seasonNumber === seasonNumber)
  if (own && own.status !== SEERR_MEDIA_STATUS.UNKNOWN) return own.status
  for (const request of info.requests) {
    if (request.status === SEERR_REQUEST_STATUS.DECLINED || request.status === SEERR_REQUEST_STATUS.FAILED) continue
    if (request.seasons.some(season => season.seasonNumber === seasonNumber)) {
      return request.status === SEERR_REQUEST_STATUS.PENDING ? SEERR_MEDIA_STATUS.PENDING : SEERR_MEDIA_STATUS.PROCESSING
    }
  }
  return null
}

export function seasonStatusLabel(status: SeerrMediaStatus | null): string | null {
  switch (status) {
    case SEERR_MEDIA_STATUS.AVAILABLE: return 'In library'
    case SEERR_MEDIA_STATUS.PARTIALLY_AVAILABLE: return 'Partly in library'
    case SEERR_MEDIA_STATUS.PROCESSING: return 'On its way'
    case SEERR_MEDIA_STATUS.PENDING: return 'Requested'
    default: return null
  }
}

/** What a request's row says about it. */
export function requestStatusLabel(request: SeerrRequest): { label: string, tone: AvailabilityTone | 'declined' } {
  switch (request.status) {
    case SEERR_REQUEST_STATUS.DECLINED: return { label: 'Declined', tone: 'declined' }
    case SEERR_REQUEST_STATUS.FAILED: return { label: 'Failed', tone: 'declined' }
    case SEERR_REQUEST_STATUS.PENDING: return { label: 'Pending approval', tone: 'pending' }
    default:
      if (request.mediaStatus === SEERR_MEDIA_STATUS.AVAILABLE) return { label: 'In your library', tone: 'ok' }
      if (request.mediaStatus === SEERR_MEDIA_STATUS.PARTIALLY_AVAILABLE) return { label: 'Partly in library', tone: 'partial' }
      return { label: 'Approved, on its way', tone: 'pending' }
  }
}

/** "3 seasons", "Season 2", "Seasons 1, 3" — or null for a movie. */
export function seasonsLabel(request: SeerrRequest): string | null {
  if (request.mediaType !== 'tv' || request.seasons.length === 0) return null
  const numbers = request.seasons.map(season => season.seasonNumber).sort((a, b) => a - b)
  if (numbers.length === 1) return `Season ${numbers[0]}`
  if (numbers.length > 4) return `${numbers.length} seasons`
  return `Seasons ${numbers.join(', ')}`
}

export function seerrTitleRoute(title: Pick<SeerrTitle, 'mediaType' | 'tmdbId'>): string {
  return `/explore/${title.mediaType}/${title.tmdbId}`
}

export function mediaTypeLabel(mediaType: SeerrMediaType): string {
  return mediaType === 'movie' ? 'Movie' : 'Series'
}

export function runtimeMinutesLabel(minutes: number | null): string | null {
  if (!minutes) return null
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  if (hours === 0) return `${rest}m`
  return rest ? `${hours}h ${rest}m` : `${hours}h`
}

/** "12 Mar 2026" for a request's date, in the viewer's locale. */
export function shortDate(iso: string | null | undefined): string | null {
  if (!iso) return null
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return null
  return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
}
