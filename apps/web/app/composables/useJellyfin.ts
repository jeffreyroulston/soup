import type {
  JellyfinChapter,
  JellyfinCollection,
  JellyfinHome,
  HomeCollection,
  JellyfinHomeExtras,
  JellyfinItem,
  JellyfinMediaSegment,
  JellyfinMediaStream,
  JellyfinPerson,
  JellyfinRemoteTrailer,
  JellyfinSearchResults,
  JellyfinShelf,
  JellyfinTrickplay,
} from '~/types/jellyfin'
import {
  mockGetEpisodes,
  mockGetBecauseYouWatched,
  mockGetExtras,
  mockGetFavorites,
  mockGetHistory,
  mockGetGenreShelves,
  mockGetHome,
  mockGetHomeCollection,
  mockGetHomeExtras,
  mockGetItem,
  mockGetLibraries,
  mockGetLibraryGenreCounts,
  mockGetLibraryItems,
  mockGetLibraryTotal,
  mockGetMediaSegments,
  mockGetPersonItems,
  mockGetSeasons,
  mockGetSeriesNextUp,
  mockGetSimilar,
  mockImageUrl,
  mockPersonImageUrl,
  mockSearch,
  mockSetFavorite,
  mockSetPlayed,
  mockSubtitleTrackUrl,
  mockTrickplayTileUrl,
} from '~/utils/mockCatalog'
import { isMockMode } from '~/utils/mockMode'
import { collapseKeepWatching, countGenres, orderKeepWatching, dailyShuffle, type GenreCount } from '~/utils/media'
import {
  getCuratedPack,
  matchCuratedCollections,
  matchCuratedPack,
  toCuratedCard,
} from '~/utils/curatedCollections'
import type { SoupCuratedCollection } from '~/types/jellyfin'

// Only fields mapItem reads; every extra field is payload and server work on each list.
const DETAIL_FIELDS =
  'Overview,ProductionYear,RunTimeTicks,OfficialRating,CommunityRating,CriticRating,MediaSources,MediaStreams,Genres,Studios,Networks,People,Path,Chapters,SortName,ChildCount,Trickplay,RemoteTrailers,LocalTrailerCount,SpecialFeatureCount,OriginalTitle,ProductionLocations,Tags,ProviderIds,Status'

const LIST_FIELDS =
  'Overview,ProductionYear,RunTimeTicks,OfficialRating,CommunityRating,Genres,SortName,ChildCount,MediaStreams,DateCreated,DateLastMediaAdded'

/** Lean fields for matching Soup curated packs against the whole library. */
const CURATED_MATCH_FIELDS = 'ProviderIds,ProductionYear,SortName'

/** The library grid only shows poster, title, year and watched state; filtering needs genres. */
const LIBRARY_GRID_FIELDS = 'ProductionYear,Genres,SortName'

const TEXT_SUBTITLE_CODECS = new Set([
  'srt',
  'subrip',
  'ass',
  'ssa',
  'vtt',
  'webvtt',
  'mov_text',
  'text',
  'ttml',
])

export type LibrarySort = 'SortName' | 'DateCreated' | 'ProductionYear' | 'CommunityRating'

type ImageKind = 'Primary' | 'Backdrop' | 'Logo'

/** Libraries whose recent additions are worth a home row (not collections, playlists, music…). */
const NON_VIDEO_LIBRARIES = new Set(['boxsets', 'playlists', 'music', 'books', 'photos', 'livetv'])

function isVideoLibrary(library: JellyfinItem): boolean {
  return !NON_VIDEO_LIBRARIES.has(library.collectionType ?? '')
}

/**
 * Query for item lists: the shared field set plus one image of each requested kind.
 * Jellyfin only fills an episode's ParentBackdrop* (the show's backdrop) when Thumb is also
 * enabled, so a Backdrop request always asks for Thumb too.
 */
function listQuery(imageTypes: string, extra: Record<string, string> = {}): Record<string, string> {
  const types = imageTypes.includes('Backdrop') && !imageTypes.includes('Thumb') ? `${imageTypes},Thumb` : imageTypes
  return { Fields: LIST_FIELDS, EnableImageTypes: types, ImageTypeLimit: '1', ...extra }
}

function asPeople(value: unknown): JellyfinPerson[] {
  return Array.isArray(value)
    ? value.map(mapPerson).filter((p): p is JellyfinPerson => p !== null)
    : []
}

function asItems(value: unknown): JellyfinItem[] {
  if (Array.isArray(value)) {
    return value.map(mapItem).filter((item): item is JellyfinItem => item !== null)
  }
  if (value && typeof value === 'object' && Array.isArray((value as { Items?: unknown }).Items)) {
    return ((value as { Items: unknown[] }).Items)
      .map(mapItem)
      .filter((item): item is JellyfinItem => item !== null)
  }
  return []
}

function asStrings(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value
    .map(entry => (typeof entry === 'string'
      ? entry
      : entry && typeof entry === 'object'
        ? String((entry as { Name?: unknown }).Name ?? '')
        : ''))
    .filter(Boolean)
}

function mapProviderIds(value: unknown): Record<string, string> | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined
  const out: Record<string, string> = {}
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (typeof raw === 'string' && raw.trim()) out[key] = raw.trim()
  }
  return Object.keys(out).length ? out : undefined
}

function mapPerson(raw: unknown): JellyfinPerson | null {
  if (!raw || typeof raw !== 'object') return null
  const json = raw as Record<string, unknown>
  const id = String(json.Id ?? '')
  const name = String(json.Name ?? '')
  if (!id || !name) return null
  const imageTags = (json.ImageTags as Record<string, string> | undefined) ?? {}
  return {
    id,
    name,
    role: (json.Role as string | undefined) || null,
    type: (json.Type as string | undefined) ?? null,
    primaryImageTag: (json.PrimaryImageTag as string | undefined) ?? imageTags.Primary ?? null,
  }
}

function mapStream(raw: unknown): JellyfinMediaStream | null {
  if (!raw || typeof raw !== 'object') return null
  const json = raw as Record<string, unknown>
  const type = json.Type
  if (type !== 'Video' && type !== 'Audio' && type !== 'Subtitle') return null
  const codec = typeof json.Codec === 'string' ? json.Codec.toLowerCase() : null
  return {
    index: typeof json.Index === 'number' ? json.Index : -1,
    type,
    codec,
    language: (json.Language as string | undefined) ?? null,
    displayTitle: (json.DisplayTitle as string | undefined) ?? null,
    isDefault: Boolean(json.IsDefault),
    isExternal: Boolean(json.IsExternal),
    isTextSubtitle: type === 'Subtitle'
      && (Boolean(json.IsTextSubtitleStream) || (codec != null && TEXT_SUBTITLE_CODECS.has(codec))),
    width: typeof json.Width === 'number' ? json.Width : null,
    height: typeof json.Height === 'number' ? json.Height : null,
  }
}

function mapChapters(value: unknown): JellyfinChapter[] {
  if (!Array.isArray(value)) return []
  return value
    .map((raw): JellyfinChapter | null => {
      if (!raw || typeof raw !== 'object') return null
      const json = raw as Record<string, unknown>
      if (typeof json.StartPositionTicks !== 'number') return null
      return {
        name: String(json.Name ?? ''),
        startPositionTicks: json.StartPositionTicks,
        imageTag: typeof json.ImageTag === 'string' ? json.ImageTag : null,
      }
    })
    .filter((chapter): chapter is JellyfinChapter => chapter !== null)
}

/** Seek-bar previews are drawn about this wide; pick the generated size nearest it. */
const TRICKPLAY_TARGET_WIDTH = 320

function mapTrickplay(value: unknown, mediaSourceId: string | null): JellyfinTrickplay | null {
  if (!value || typeof value !== 'object') return null
  const bySource = value as Record<string, unknown>
  const sizes = (mediaSourceId && bySource[mediaSourceId]) || Object.values(bySource)[0]
  if (!sizes || typeof sizes !== 'object') return null
  const options = Object.values(sizes as Record<string, unknown>)
    .map((raw): JellyfinTrickplay | null => {
      if (!raw || typeof raw !== 'object') return null
      const json = raw as Record<string, unknown>
      const numbers = [json.Width, json.Height, json.TileWidth, json.TileHeight, json.ThumbnailCount, json.Interval]
      if (!numbers.every(n => typeof n === 'number' && n > 0)) return null
      return {
        width: json.Width as number,
        height: json.Height as number,
        tileWidth: json.TileWidth as number,
        tileHeight: json.TileHeight as number,
        thumbnailCount: json.ThumbnailCount as number,
        interval: json.Interval as number,
      }
    })
    .filter((info): info is JellyfinTrickplay => info !== null)
  if (!options.length) return null
  return options.reduce((best, info) =>
    Math.abs(info.width - TRICKPLAY_TARGET_WIDTH) < Math.abs(best.width - TRICKPLAY_TARGET_WIDTH) ? info : best)
}

function mapRemoteTrailers(value: unknown): JellyfinRemoteTrailer[] {
  if (!Array.isArray(value)) return []
  return value
    .map((raw): JellyfinRemoteTrailer | null => {
      if (!raw || typeof raw !== 'object') return null
      const json = raw as Record<string, unknown>
      return typeof json.Url === 'string' && json.Url
        ? { url: json.Url, name: (json.Name as string | undefined) || null }
        : null
    })
    .filter((trailer): trailer is JellyfinRemoteTrailer => trailer !== null)
}

const SEGMENT_TYPES = new Set(['Intro', 'Outro', 'Recap', 'Preview', 'Commercial'])

function mapSegment(raw: unknown): JellyfinMediaSegment | null {
  if (!raw || typeof raw !== 'object') return null
  const json = raw as Record<string, unknown>
  const type = String(json.Type ?? '')
  if (!SEGMENT_TYPES.has(type)) return null
  if (typeof json.StartTicks !== 'number' || typeof json.EndTicks !== 'number') return null
  if (json.EndTicks <= json.StartTicks) return null
  return { type: type as JellyfinMediaSegment['type'], startTicks: json.StartTicks, endTicks: json.EndTicks }
}

function mapItem(raw: unknown): JellyfinItem | null {
  if (!raw || typeof raw !== 'object') return null
  const json = raw as Record<string, unknown>
  const id = String(json.Id ?? '')
  const name = String(json.Name ?? '')
  if (!id || !name) return null
  const imageTags = (json.ImageTags as Record<string, string> | undefined) ?? {}
  const backdropTags = json.BackdropImageTags
  const parentBackdropTags = json.ParentBackdropImageTags
  const userData = json.UserData as Record<string, unknown> | undefined
  const sources = Array.isArray(json.MediaSources) ? json.MediaSources : []
  const firstSource = (sources[0] && typeof sources[0] === 'object')
    ? sources[0] as Record<string, unknown>
    : null
  const rawStreams = firstSource?.MediaStreams ?? json.MediaStreams
  const mediaSourceId = firstSource ? String(firstSource.Id ?? '') || null : null
  return {
    id,
    name,
    type: String(json.Type ?? ''),
    sortName: (json.SortName as string | undefined) ?? null,
    collectionType: (json.CollectionType as string | undefined) ?? null,
    overview: (json.Overview as string | undefined) ?? null,
    productionYear: typeof json.ProductionYear === 'number' ? json.ProductionYear : null,
    communityRating: typeof json.CommunityRating === 'number' ? json.CommunityRating : null,
    criticRating: typeof json.CriticRating === 'number' ? json.CriticRating : null,
    officialRating: (json.OfficialRating as string | undefined) ?? null,
    status: (json.Status as string | undefined) ?? null,
    originalTitle: (json.OriginalTitle as string | undefined) ?? null,
    productionLocations: asStrings(json.ProductionLocations),
    tags: asStrings(json.Tags),
    networks: asStrings(json.Networks),
    providerIds: mapProviderIds(json.ProviderIds),
    runTimeTicks: typeof json.RunTimeTicks === 'number' ? json.RunTimeTicks : null,
    primaryImageTag: imageTags.Primary ?? null,
    backdropImageTag:
      Array.isArray(backdropTags) && backdropTags.length
        ? String(backdropTags[0])
        : null,
    parentBackdropItemId: (json.ParentBackdropItemId as string | undefined) ?? null,
    parentBackdropImageTag:
      Array.isArray(parentBackdropTags) && parentBackdropTags.length
        ? String(parentBackdropTags[0])
        : null,
    logoImageTag: imageTags.Logo ?? null,
    parentLogoItemId: (json.ParentLogoItemId as string | undefined) ?? null,
    parentLogoImageTag: (json.ParentLogoImageTag as string | undefined) ?? null,
    seriesName: (json.SeriesName as string | undefined) ?? null,
    seriesPrimaryImageTag: (json.SeriesPrimaryImageTag as string | undefined) ?? null,
    seriesId: (json.SeriesId as string | undefined) ?? null,
    seasonId: (json.SeasonId as string | undefined) ?? null,
    indexNumber: typeof json.IndexNumber === 'number' ? json.IndexNumber : null,
    parentIndexNumber: typeof json.ParentIndexNumber === 'number' ? json.ParentIndexNumber : null,
    premiereDate: (json.PremiereDate as string | undefined) ?? null,
    endDate: (json.EndDate as string | undefined) ?? null,
    dateAdded: ((json.DateLastMediaAdded ?? json.DateCreated) as string | undefined) ?? null,
    childCount: typeof json.ChildCount === 'number' ? json.ChildCount : null,
    recursiveItemCount: typeof json.RecursiveItemCount === 'number' ? json.RecursiveItemCount : null,
    path: (json.Path as string | undefined) ?? null,
    genres: asStrings(json.Genres),
    studios: asStrings(json.Studios),
    people: asPeople(json.People),
    mediaSourceId,
    sourceBitrate: typeof firstSource?.Bitrate === 'number' && firstSource.Bitrate > 0 ? firstSource.Bitrate : null,
    mediaStreams: Array.isArray(rawStreams)
      ? rawStreams.map(mapStream).filter((s): s is JellyfinMediaStream => s !== null)
      : [],
    chapters: mapChapters(json.Chapters),
    trickplay: mapTrickplay(json.Trickplay, mediaSourceId),
    remoteTrailers: mapRemoteTrailers(json.RemoteTrailers),
    localTrailerCount: typeof json.LocalTrailerCount === 'number' ? json.LocalTrailerCount : null,
    specialFeatureCount: typeof json.SpecialFeatureCount === 'number' ? json.SpecialFeatureCount : null,
    extraType: (json.ExtraType as string | undefined) ?? null,
    isFavorite: Boolean(userData?.IsFavorite),
    played: Boolean(userData?.Played),
    playedPercentage:
      typeof userData?.PlayedPercentage === 'number' ? userData.PlayedPercentage : null,
    playbackPositionTicks:
      typeof userData?.PlaybackPositionTicks === 'number'
        ? userData.PlaybackPositionTicks
        : null,
    lastPlayedDate: (userData?.LastPlayedDate as string | undefined) ?? null,
  }
}

export function useJellyfin() {
  const nuxtApp = useNuxtApp()
  let api = apis.get(nuxtApp)
  if (!api) {
    api = createJellyfin()
    apis.set(nuxtApp, api)
  }
  return api
}

const apis = new WeakMap<object, ReturnType<typeof createJellyfin>>()

function createJellyfin() {
  const client = useJellyfinClient()
  const { jellyfin, requireSession, get } = client
  const mock = isMockMode()

  /** POST/DELETE that tries the 10.9+ route, then the legacy per-user route. */
  async function sendWithFallback(method: 'POST' | 'DELETE', path: string, legacyPath: string) {
    const session = requireSession()
    let response = await client.send(method, path, { query: { userId: session.userId } })
    if (response.status === 404 || response.status === 405) {
      response = await client.send(method, legacyPath)
    }
    if (!response.ok) {
      throw new Error(`Jellyfin ${response.status} for ${path}`)
    }
  }

  function imageUrlFor(
    itemId: string,
    type: ImageKind,
    tag: string | null | undefined,
    maxWidth: number,
  ): string | null {
    if (mock) return mockImageUrl(itemId, type, tag, maxWidth)
    if (!tag) return null
    return client.mediaUrl(`Items/${itemId}/Images/${type}`, {
      tag,
      maxWidth: String(maxWidth),
      quality: '80',
    })
  }

  function imageUrl(item: JellyfinItem, type: ImageKind = 'Primary', maxWidth = 480): string | null {
    if (type === 'Backdrop') {
      return imageUrlFor(item.id, 'Backdrop', item.backdropImageTag, maxWidth)
        ?? (item.parentBackdropItemId
          ? imageUrlFor(item.parentBackdropItemId, 'Backdrop', item.parentBackdropImageTag, maxWidth)
          : null)
    }
    if (type === 'Logo') {
      return imageUrlFor(item.id, 'Logo', item.logoImageTag, maxWidth)
        ?? (item.parentLogoItemId
          ? imageUrlFor(item.parentLogoItemId, 'Logo', item.parentLogoImageTag, maxWidth)
          : null)
    }
    return imageUrlFor(item.id, 'Primary', item.primaryImageTag, maxWidth)
  }

  /** 2:3 key art; episodes use their series poster rather than the episode still, seasons fall back to it. */
  function posterUrl(item: JellyfinItem, maxWidth = 480): string | null {
    const series = item.seriesId ? imageUrlFor(item.seriesId, 'Primary', item.seriesPrimaryImageTag, maxWidth) : null
    if (item.type === 'Episode' && series) return series
    return imageUrl(item, 'Primary', maxWidth) ?? (item.type === 'Season' ? series : null)
  }

  function personImageUrl(person: JellyfinPerson, maxWidth = 256): string | null {
    if (mock) return mockPersonImageUrl(person)
    return imageUrlFor(person.id, 'Primary', person.primaryImageTag, maxWidth)
  }

  function subtitleTrackUrl(itemId: string, mediaSourceId: string, streamIndex: number): string | null {
    if (mock) return mockSubtitleTrackUrl()
    return client.mediaUrl(`Videos/${itemId}/${mediaSourceId}/Subtitles/${streamIndex}/Stream.vtt`)
  }

  /** One sprite sheet of seek-bar thumbnails (see `JellyfinTrickplay`). */
  /** Still for chapter `index` (its position in item.chapters), or null when the library has none. */
  function chapterImageUrl(item: JellyfinItem, index: number, maxWidth = 320): string | null {
    if (mock) return null
    const tag = item.chapters?.[index]?.imageTag
    if (!tag) return null
    return client.mediaUrl(`Items/${item.id}/Images/Chapter/${index}`, {
      tag,
      maxWidth: String(maxWidth),
      quality: '80',
    })
  }

  function trickplayTileUrl(item: JellyfinItem, width: number, index: number): string | null {
    if (mock) return mockTrickplayTileUrl(index)
    const query: Record<string, string> = item.mediaSourceId ? { MediaSourceId: item.mediaSourceId } : {}
    return client.mediaUrl(`Videos/${item.id}/Trickplay/${width}/${index}.jpg`, query)
  }

  function userItems(query: Record<string, string>) {
    return get(`Users/${requireSession().userId}/Items`, query)
  }

  async function getLibraries(): Promise<JellyfinItem[]> {
    if (mock) return mockGetLibraries()
    return asItems(await get(`Users/${requireSession().userId}/Views`, { IncludeExternalContent: 'false' }))
  }

  async function getSpotlight(): Promise<JellyfinCollection | null> {
    const sets = asItems(await userItems(listQuery('Primary,Backdrop', {
      IncludeItemTypes: 'BoxSet',
      Recursive: 'true',
      SortBy: 'Random',
      Limit: '1',
    })))
    const collection = sets[0]
    if (!collection) return null
    const items = asItems(await userItems(listQuery('Primary,Backdrop', { ParentId: collection.id })))
    return items.length ? { collection, items } : null
  }

  /** Above-the-fold home rows; `getHomeExtras` loads the slower rows below them. */
  async function getHome(): Promise<JellyfinHome> {
    if (mock) {
      const home = mockGetHome()
      const collapsed = collapseKeepWatching(home.resume, home.nextUp)
      return { ...home, ...collapsed, keepWatching: orderKeepWatching(collapsed, home.resume) }
    }
    const { userId } = requireSession()
    // Logo: the hero shows title art over the backdrop when the item has it.
    const images = 'Primary,Backdrop,Logo'
    const [resume, nextUp, recentlyAdded, random, played] = await Promise.all([
      // Generous limit so a show's earlier part-watched episodes aren't cut off before collapsing.
      get(`Users/${userId}/Items/Resume`, listQuery(images, { Limit: '50', MediaTypes: 'Video' })),
      // Room for shows last watched a while ago, so their new seasons can reach the hero.
      get('Shows/NextUp', listQuery(images, { UserId: userId, Limit: '30' })).catch(() => null),
      getLibraries().then(libraries => Promise.all(
        libraries.filter(isVideoLibrary).map(library => getLatestShelf(library, images)),
      )),
      userItems(listQuery(images, {
        IncludeItemTypes: 'Movie,Series',
        Recursive: 'true',
        SortBy: 'Random',
        ImageTypes: 'Backdrop',
        Limit: '12',
      })).catch(() => null),
      // Play dates for Keep Watching's order: a Next Up episode is unplayed, so its show's
      // last watched episode says when you were last on it.
      userItems({
        IncludeItemTypes: 'Episode',
        Recursive: 'true',
        Filters: 'IsPlayed',
        SortBy: 'DatePlayed',
        SortOrder: 'Descending',
        Limit: '200',
        EnableImages: 'false',
      }).catch(() => null),
    ])
    const resumeItems = asItems(resume)
    // A show's first episode isn't "up next" until you've started it (Jellyfin 12 dropped
    // the server-side DisableFirstEpisode option, so filter here).
    const started = asItems(nextUp).filter(item => !(item.parentIndexNumber === 1 && item.indexNumber === 1))
    const collapsed = collapseKeepWatching(resumeItems, started)
    return {
      ...collapsed,
      keepWatching: orderKeepWatching(collapsed, [...resumeItems, ...asItems(played)]),
      recentlyAdded: recentlyAdded.filter(shelf => shelf.items.length),
      random: asItems(random),
    }
  }

  /** Recently Added for one library; a library that fails to load just has no row. */
  async function getLatestShelf(library: JellyfinItem, images: string): Promise<JellyfinShelf> {
    const types: Record<string, string> = library.collectionType === 'movies'
      ? { IncludeItemTypes: 'Movie' }
      : library.collectionType === 'tvshows'
        ? { IncludeItemTypes: 'Episode', GroupItems: 'true' }
        : {}
    const raw = await get(`Users/${requireSession().userId}/Items/Latest`, listQuery(images, {
      ParentId: library.id,
      Limit: '25',
      ...types,
    })).catch(() => null)
    return { title: library.name, items: asItems(raw), seeAllTo: `/library/${library.id}` }
  }

  /** Movies + series with provider ids, used only to resolve curated packs. Pages load in parallel. */
  async function getLibraryForCuratedMatch(): Promise<JellyfinItem[]> {
    const pageSize = 500
    const fetchPage = (start: number) => userItems({
      Fields: CURATED_MATCH_FIELDS,
      IncludeItemTypes: 'Movie,Series',
      Recursive: 'true',
      EnableImageTypes: 'Primary',
      ImageTypeLimit: '1',
      StartIndex: String(start),
      Limit: String(pageSize),
    })
    const first = await fetchPage(0)
    const total = Number((first as { TotalRecordCount?: unknown })?.TotalRecordCount) || 0
    const starts: number[] = []
    for (let start = pageSize; start < Math.min(total, 10_000); start += pageSize) starts.push(start)
    const rest = await Promise.all(starts.map(fetchPage))
    return [first, ...rest].flatMap(asItems)
  }

  async function getCuratedCollections(): Promise<SoupCuratedCollection[]> {
    const library = mock
      ? [...(await mockGetLibraryItems('lib-movies', 'SortName')), ...(await mockGetLibraryItems('lib-tv', 'SortName'))]
      : await getLibraryForCuratedMatch()
    const { all } = matchCuratedCollections(library)
    return all.map(toCuratedCard)
  }

  async function getCuratedCollection(packId: string): Promise<SoupCuratedCollection | null> {
    const pack = getCuratedPack(packId)
    if (!pack) return null
    const library = mock
      ? [...(await mockGetLibraryItems('lib-movies', 'SortName')), ...(await mockGetLibraryItems('lib-tv', 'SortName'))]
      : await getLibraryForCuratedMatch()
    const matched = matchCuratedPack(pack, library)
    return matched ? toCuratedCard(matched) : null
  }

  async function getHomeExtras(): Promise<JellyfinHomeExtras> {
    if (mock) return mockGetHomeExtras()
    const [topRated, unwatched] = await Promise.all([
      getRated('Primary,Backdrop', 9).catch((): JellyfinItem[] => []),
      // Over-fetch so the row stays full after dropping anything already in Top Rated.
      getRated('Primary', 30, { IsPlayed: 'false' }).catch((): JellyfinItem[] => []),
    ])
    const topIds = new Set(topRated.map(item => item.id))
    return {
      topRated,
      unwatchedTopRated: unwatched.filter(item => !topIds.has(item.id)).slice(0, 20),
    }
  }

  /** The collection card loads on its own so the library match doesn't hold up Top Rated. */
  async function getHomeCollection(): Promise<HomeCollection> {
    if (mock) return mockGetHomeCollection()
    const curated = await getCuratedCollections().catch((): SoupCuratedCollection[] => [])
    // BoxSet spotlight only when Soup packs didn't fill the slot.
    const spotlight = curated.length ? null : await getSpotlight().catch(() => null)
    return { curated, spotlight }
  }

  /**
   * Highest community rating first. Jellyfin keeps no vote counts, so a title scored 10 by
   * a handful of people would otherwise top the list; these filters screen those out.
   * Movies need a critic score of 60+ (Rotten Tomatoes only scores titles with enough
   * reviews). Series rarely have one, so they need a score under 9.5 (only tiny vote counts
   * average that high) and 6+ seasons and episodes, which drops specials and OVAs.
   */
  async function getRated(images: string, limit: number, extra: Record<string, string> = {}): Promise<JellyfinItem[]> {
    const query = (fetchLimit: number, params: Record<string, string>) => userItems(listQuery(images, {
      Recursive: 'true',
      SortBy: 'CommunityRating',
      SortOrder: 'Descending',
      HasCommunityRating: 'true',
      Limit: String(fetchLimit),
      ...extra,
      ...params,
    })).then(asItems)
    const [movies, series] = await Promise.all([
      query(limit, { IncludeItemTypes: 'Movie', MinCriticRating: '60' }),
      // Over-fetch: the series filters run here, not on the server.
      query(100, {
        IncludeItemTypes: 'Series',
        Fields: `${LIST_FIELDS},RecursiveItemCount`,
      }).then(items => items.filter(item =>
        (item.communityRating ?? 0) < 9.5 && (item.recursiveItemCount ?? 0) >= 6)),
    ])
    return [...movies, ...series]
      .sort((a, b) => (b.communityRating ?? 0) - (a.communityRating ?? 0))
      .slice(0, limit)
  }

  /**
   * A few genre rows, picked from the library's most common genres. Both the genres and
   * each row's titles rotate daily rather than on every request.
   */
  async function getGenreShelves(): Promise<JellyfinShelf[]> {
    if (mock) return mockGetGenreShelves()
    const titles = { Recursive: 'true', IncludeItemTypes: 'Movie,Series' }
    const tally = countGenres(asItems(await userItems({
      ...titles,
      Fields: 'Genres',
      EnableTotalRecordCount: 'false',
      EnableImages: 'false',
      EnableUserData: 'false',
    })))
    // Common enough to fill a row; the top dozen keeps niche genres out of the rotation.
    const pool = tally.filter(genre => genre.count >= 8).slice(0, 12).map(genre => genre.name)
    const picks = dailyShuffle(pool, 'genres').slice(0, 4)
    const shelves = await Promise.all(picks.map(async (genre): Promise<JellyfinShelf> => {
      const raw = await userItems(listQuery('Primary', {
        ...titles,
        Genres: genre,
        SortBy: 'CommunityRating',
        SortOrder: 'Descending',
        Limit: '60',
      })).catch(() => null)
      return { title: genre, items: dailyShuffle(asItems(raw), genre).slice(0, 20) }
    }))
    return shelves.filter(shelf => shelf.items.length >= 4)
  }

  /** "Because you watched X" rows for the last couple of distinct titles the user finished. */
  async function getBecauseYouWatched(): Promise<JellyfinShelf[]> {
    if (mock) return mockGetBecauseYouWatched()
    const recent = asItems(await userItems({
      Recursive: 'true',
      IncludeItemTypes: 'Movie,Episode',
      Filters: 'IsPlayed',
      SortBy: 'DatePlayed',
      SortOrder: 'Descending',
      Limit: '20',
      EnableImages: 'false',
    }))
    // Episodes stand in for their show, so one binge doesn't take both rows.
    const anchors = new Map<string, string>()
    for (const item of recent) {
      const id = item.seriesId || item.id
      if (!anchors.has(id)) anchors.set(id, item.seriesName || item.name)
      if (anchors.size === 2) break
    }
    const shelves = await Promise.all([...anchors].map(async ([id, name]): Promise<JellyfinShelf> => ({
      title: `Because You Watched ${name}`,
      items: (await getSimilar(id).catch((): JellyfinItem[] => [])).filter(item => !anchors.has(item.id)),
    })))
    return shelves.filter(shelf => shelf.items.length >= 4)
  }

  /**
   * Titles under a library or collection. Jellyfin's Collections view (`boxsets`) lists
   * the collections themselves; anywhere else a recursive Movie/Series query would
   * return the films inside them.
   */
  function libraryQuery(libraryId: string, collectionType?: string | null): Record<string, string> {
    return {
      ParentId: libraryId,
      Recursive: 'true',
      IncludeItemTypes: collectionType === 'boxsets' ? 'BoxSet' : 'Movie,Series',
    }
  }

  /** Title count only: Limit=0 skips building any items, so this returns fast. */
  async function getLibraryTotal(libraryId: string, collectionType?: string | null): Promise<number> {
    if (mock) return mockGetLibraryTotal(libraryId)
    const raw = await userItems({
      ...libraryQuery(libraryId, collectionType),
      Limit: '0',
      EnableTotalRecordCount: 'true',
      EnableImages: 'false',
      EnableUserData: 'false',
    }) as { TotalRecordCount?: number }
    return typeof raw.TotalRecordCount === 'number' ? raw.TotalRecordCount : 0
  }

  /**
   * Genre tallies scoped to this library, from a light query (genres only; no
   * images, user data or media info). /Genres can return counts, but they aren't
   * scoped to the parent library.
   */
  async function getLibraryGenreCounts(libraryId: string, collectionType?: string | null): Promise<GenreCount[]> {
    if (mock) return mockGetLibraryGenreCounts(libraryId)
    const raw = await userItems({
      ...libraryQuery(libraryId, collectionType),
      Fields: 'Genres',
      EnableTotalRecordCount: 'false',
      EnableImages: 'false',
      EnableUserData: 'false',
    })
    return countGenres(asItems(raw))
  }

  async function getLibraryItems(
    libraryId: string,
    sortBy: LibrarySort = 'SortName',
    collectionType?: string | null,
  ): Promise<JellyfinItem[]> {
    if (mock) return mockGetLibraryItems(libraryId, sortBy)
    const descending = sortBy === 'DateCreated' || sortBy === 'CommunityRating' || sortBy === 'ProductionYear'
    const raw = await userItems({
      ...libraryQuery(libraryId, collectionType),
      SortBy: sortBy === 'SortName' ? 'SortName' : `${sortBy},SortName`,
      SortOrder: descending ? 'Descending' : 'Ascending',
      Fields: LIBRARY_GRID_FIELDS,
      EnableTotalRecordCount: 'false',
      EnableImageTypes: 'Primary',
      ImageTypeLimit: '1',
    })
    return asItems(raw)
  }

  /**
   * The user's favourite movies, shows and episodes. Jellyfin doesn't record when something
   * was favourited, so "recent" sorts by when it was added to the library.
   */
  async function getFavorites(sortBy: LibrarySort = 'SortName'): Promise<JellyfinItem[]> {
    if (mock) return mockGetFavorites(sortBy)
    const descending = sortBy === 'DateCreated' || sortBy === 'CommunityRating' || sortBy === 'ProductionYear'
    return asItems(await userItems(listQuery('Primary,Backdrop', {
      Filters: 'IsFavorite',
      Recursive: 'true',
      IncludeItemTypes: 'Movie,Series,Episode',
      SortBy: sortBy === 'SortName' ? 'SortName' : `${sortBy},SortName`,
      SortOrder: descending ? 'Descending' : 'Ascending',
    })))
  }

  /** Movies and episodes the user has finished, most recently watched first. */
  async function getHistory(): Promise<JellyfinItem[]> {
    if (mock) return mockGetHistory()
    return asItems(await userItems(listQuery('Primary,Backdrop', {
      Filters: 'IsPlayed',
      Recursive: 'true',
      IncludeItemTypes: 'Movie,Episode',
      SortBy: 'DatePlayed',
      SortOrder: 'Descending',
      Limit: '200',
    })))
  }

  async function getItem(itemId: string): Promise<JellyfinItem> {
    if (mock) return mockGetItem(itemId)
    const raw = await get(`Users/${requireSession().userId}/Items/${itemId}`, { Fields: DETAIL_FIELDS })
    const item = mapItem(raw)
    if (!item) throw new Error('Unreadable item')
    return item
  }

  async function getSimilar(itemId: string): Promise<JellyfinItem[]> {
    if (mock) return mockGetSimilar(itemId)
    return asItems(await get(`Items/${itemId}/Similar`, listQuery('Primary,Backdrop', {
      UserId: requireSession().userId,
      Limit: '12',
    })))
  }

  async function getSeasons(seriesId: string): Promise<JellyfinItem[]> {
    if (mock) return mockGetSeasons(seriesId)
    return asItems(await get(`Shows/${seriesId}/Seasons`, listQuery('Primary', {
      UserId: requireSession().userId,
    })))
  }

  async function getEpisodes(seriesId: string, seasonId?: string): Promise<JellyfinItem[]> {
    if (mock) return mockGetEpisodes(seriesId, seasonId)
    const query = listQuery('Primary,Backdrop', { UserId: requireSession().userId })
    if (seasonId) query.SeasonId = seasonId
    return asItems(await get(`Shows/${seriesId}/Episodes`, query))
  }

  /** The episode Jellyfin would play next for a series (in progress or next unwatched). */
  async function getSeriesNextUp(seriesId: string): Promise<JellyfinItem | null> {
    if (mock) return mockGetSeriesNextUp(seriesId)
    const raw = await get('Shows/NextUp', {
      UserId: requireSession().userId,
      SeriesId: seriesId,
      Limit: '1',
      Fields: LIST_FIELDS,
      EnableResumable: 'true',
      DisableFirstEpisode: 'false',
    })
    return asItems(raw)[0] ?? null
  }

  async function search(term: string): Promise<JellyfinSearchResults> {
    if (mock) return mockSearch(term)
    const { userId } = requireSession()
    const trimmed = term.trim()
    if (!trimmed) return { items: [], people: [] }
    const [items, people] = await Promise.all([
      userItems(listQuery('Primary,Backdrop', {
        searchTerm: trimmed,
        Recursive: 'true',
        IncludeItemTypes: 'Movie,Series,Episode',
        Limit: '40',
      })),
      get<{ Items?: unknown }>('Persons', {
        searchTerm: trimmed,
        userId,
        limit: '12',
        enableImageTypes: 'Primary',
      }).catch(() => null),
    ])
    return { items: asItems(items), people: asPeople(people?.Items) }
  }

  async function getPersonItems(personId: string): Promise<JellyfinItem[]> {
    if (mock) return mockGetPersonItems(personId)
    return asItems(await userItems(listQuery('Primary,Backdrop', {
      PersonIds: personId,
      Recursive: 'true',
      IncludeItemTypes: 'Movie,Series',
      SortBy: 'ProductionYear,SortName',
      SortOrder: 'Descending',
    })))
  }

  /**
   * Intro/credits/recap markers. Jellyfin itself only stores them; a provider plugin
   * (usually Intro Skipper) detects them. Servers before 10.10 have no endpoint, so an
   * error just means no segments.
   */
  async function getMediaSegments(itemId: string): Promise<JellyfinMediaSegment[]> {
    if (mock) return mockGetMediaSegments(itemId)
    try {
      const raw = await get<{ Items?: unknown }>(`MediaSegments/${itemId}`)
      return Array.isArray(raw.Items)
        ? raw.Items.map(mapSegment).filter((s): s is JellyfinMediaSegment => s !== null)
        : []
    }
    catch {
      return []
    }
  }

  /**
   * Local trailers, then special features (featurettes, deleted scenes…). Each list is
   * only requested when the item says it has some.
   */
  async function getExtras(
    item: Pick<JellyfinItem, 'id' | 'localTrailerCount' | 'specialFeatureCount'>,
  ): Promise<JellyfinItem[]> {
    if (mock) return mockGetExtras(item.id)
    const { userId } = requireSession()
    const [trailers, features] = await Promise.all([
      item.localTrailerCount ? get(`Items/${item.id}/LocalTrailers`, { userId }).catch(() => []) : [],
      item.specialFeatureCount ? get(`Items/${item.id}/SpecialFeatures`, { userId }).catch(() => []) : [],
    ])
    return [
      ...asItems(trailers).map(extra => ({ ...extra, extraType: extra.extraType ?? 'Trailer' })),
      ...asItems(features),
    ]
  }

  async function setFavorite(itemId: string, favorite: boolean) {
    if (mock) {
      mockSetFavorite(itemId, favorite)
      return
    }
    await sendWithFallback(
      favorite ? 'POST' : 'DELETE',
      `UserFavoriteItems/${itemId}`,
      `Users/${requireSession().userId}/FavoriteItems/${itemId}`,
    )
  }

  async function setPlayed(itemId: string, played: boolean) {
    if (mock) {
      mockSetPlayed(itemId, played)
      return
    }
    await sendWithFallback(
      played ? 'POST' : 'DELETE',
      `UserPlayedItems/${itemId}`,
      `Users/${requireSession().userId}/PlayedItems/${itemId}`,
    )
  }

  return {
    jellyfin,
    getHome,
    getHomeExtras,
    getHomeCollection,
    getCuratedCollection,
    getGenreShelves,
    getBecauseYouWatched,
    getLibraries,
    getLibraryItems,
    getLibraryTotal,
    getLibraryGenreCounts,
    getFavorites,
    getHistory,
    getItem,
    getSimilar,
    getSeasons,
    getEpisodes,
    getSeriesNextUp,
    getPersonItems,
    getMediaSegments,
    getExtras,
    search,
    setFavorite,
    setPlayed,
    imageUrl,
    posterUrl,
    personImageUrl,
    subtitleTrackUrl,
    trickplayTileUrl,
    chapterImageUrl,
  }
}
