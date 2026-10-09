import type {
  JellyfinCollection,
  JellyfinHome,
  JellyfinHomeExtras,
  JellyfinItem,
  JellyfinMediaSegment,
  JellyfinPerson,
  JellyfinPlaybackPlan,
  JellyfinSearchResults,
  JellyfinSessionPayload,
  JellyfinTrickplay,
} from '~/types/jellyfin'
import type { LibrarySort } from '~/composables/useJellyfin'
import { countGenres, type GenreCount } from './media'

const TICKS_PER_MIN = 10_000_000 * 60

export const MOCK_SESSION: JellyfinSessionPayload = {
  baseUrl: 'https://mock.soup.local',
  userId: 'mock-user',
  accessToken: 'mock-token',
  serverId: 'mock-server',
  deviceId: 'mock-web-device',
}

export const MOCK_EMAIL = 'mock@soup.dev'

/** Public-domain sample so the watch page can exercise the player. */
export const MOCK_SAMPLE_VIDEO =
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'

function svgDataUri(svg: string): string {
  return `data:image/svg+xml,${encodeURIComponent(svg)}`
}

/** 10×10 sheets of numbered 320×180 frames, one every 10 s, so seek previews can be checked by eye. */
const MOCK_TRICKPLAY: JellyfinTrickplay = {
  width: 320,
  height: 180,
  tileWidth: 10,
  tileHeight: 10,
  thumbnailCount: 600,
  interval: 10_000,
}

export function mockTrickplayTileUrl(index: number): string {
  const { width, height, tileWidth, tileHeight, interval } = MOCK_TRICKPLAY
  const perTile = tileWidth * tileHeight
  let cells = ''
  for (let i = 0; i < perTile; i++) {
    const frame = index * perTile + i
    const seconds = (frame * interval) / 1000
    const label = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
    const x = (i % tileWidth) * width
    const y = Math.floor(i / tileWidth) * height
    cells += `<rect x="${x}" y="${y}" width="${width}" height="${height}" fill="hsl(${(frame * 7) % 360} 45% 30%)"/>`
      + `<text x="${x + width / 2}" y="${y + height / 2 + 18}" font-family="sans-serif" font-size="52" font-weight="800" fill="white" text-anchor="middle">${label}</text>`
  }
  return svgDataUri(`<svg xmlns="http://www.w3.org/2000/svg" width="${width * tileWidth}" height="${height * tileHeight}">${cells}</svg>`)
}

function posterUri(title: string, hue: number): string {
  return svgDataUri(`
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="600" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="hsl(${hue} 42% 22%)"/>
      <stop offset="100%" stop-color="hsl(${(hue + 40) % 360} 55% 12%)"/>
    </linearGradient>
  </defs>
  <rect width="400" height="600" fill="url(#g)"/>
  <rect x="24" y="24" width="352" height="552" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="2"/>
  <text x="40" y="520" fill="#F4F1EA" font-family="Manrope, system-ui, sans-serif" font-size="28" font-weight="800">${escapeXml(title)}</text>
</svg>`.trim())
}

function backdropUri(title: string, hue: number): string {
  return svgDataUri(`
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <defs>
    <linearGradient id="b" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="hsl(${hue} 38% 28%)"/>
      <stop offset="55%" stop-color="hsl(${(hue + 25) % 360} 48% 14%)"/>
      <stop offset="100%" stop-color="#0B0B0C"/>
    </linearGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#b)"/>
  <text x="96" y="920" fill="#F4F1EA" font-family="Manrope, system-ui, sans-serif" font-size="72" font-weight="800">${escapeXml(title)}</text>
</svg>`.trim())
}

function personUri(name: string, hue: number): string {
  const initials = name.split(/\s+/).map(part => part[0] ?? '').join('').slice(0, 2).toUpperCase()
  return svgDataUri(`
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <circle cx="128" cy="128" r="128" fill="hsl(${hue} 35% 28%)"/>
  <text x="128" y="148" text-anchor="middle" fill="#F4F1EA" font-family="Manrope, system-ui, sans-serif" font-size="72" font-weight="800">${escapeXml(initials)}</text>
</svg>`.trim())
}

function escapeXml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
}

type MockMovie = JellyfinItem & { _hue: number }
type MockSeries = JellyfinItem & { _hue: number }
type MockEpisode = JellyfinItem & { _hue: number }

const people: JellyfinPerson[] = [
  { id: 'person-ada', name: 'Ada Meridian', role: 'Director', type: 'Director', primaryImageTag: 'p' },
  { id: 'person-jon', name: 'Jon Harbor', role: 'Lead', type: 'Actor', primaryImageTag: 'p' },
  { id: 'person-mira', name: 'Mira Solace', role: 'Lead', type: 'Actor', primaryImageTag: 'p' },
  { id: 'person-kai', name: 'Kai North', role: 'Supporting', type: 'Actor', primaryImageTag: 'p' },
]

const movies: MockMovie[] = [
  movie('movie-northlight', 'Northlight', 2021, 118, 8.2, 'PG-13', 210, ['Sci-Fi', 'Drama'], 0.42),
  movie('movie-glass-harbor', 'Glass Harbor', 2019, 104, 7.4, 'R', 195, ['Thriller'], null),
  movie('movie-ember-road', 'Ember Road', 2023, 96, 7.9, 'PG', 18, ['Adventure', 'Family'], null),
  movie('movie-paper-moon', 'Paper Moon Circuit', 2017, 132, 8.6, 'PG-13', 250, ['Mystery'], null),
  movie('movie-salt-line', 'The Salt Line', 2020, 110, 7.1, 'R', 165, ['Crime'], 0.18),
  movie('movie-violet-hour', 'Violet Hour', 2024, 101, 8.0, 'PG-13', 32, ['Romance', 'Drama'], null),
  movie('movie-static-bloom', 'Static Bloom', 2018, 89, 6.8, 'PG', 140, ['Comedy'], null),
  movie('movie-iron-tide', 'Iron Tide', 2022, 141, 7.7, 'PG-13', 55, ['Action'], null),
]

// One title with only a YouTube trailer, to exercise the embedded trailer player.
Object.assign(movies.find(item => item.id === 'movie-static-bloom')!, { localTrailerCount: 0, specialFeatureCount: 0 })

const seriesList: MockSeries[] = [
  series('series-signal', 'Signal Drift', 2022, 8.4, 'TV-14', 225, ['Sci-Fi'], 2),
  series('series-kitchen', 'After Kitchen', 2020, 7.8, 'TV-MA', 40, ['Drama'], 1),
]

const seasons: JellyfinItem[] = [
  season('season-signal-1', 'series-signal', 1, 'Season 1'),
  season('season-signal-2', 'series-signal', 2, 'Season 2'),
  season('season-kitchen-1', 'series-kitchen', 1, 'Season 1'),
]

const episodes: MockEpisode[] = [
  episode('ep-signal-1-1', 'series-signal', 'season-signal-1', 'Signal Drift', 1, 1, 'Pilot Frequency', 48, null),
  episode('ep-signal-1-2', 'series-signal', 'season-signal-1', 'Signal Drift', 1, 2, 'Ghost Carrier', 46, 0.55),
  episode('ep-signal-1-3', 'series-signal', 'season-signal-1', 'Signal Drift', 1, 3, 'Lattice', 51, null),
  episode('ep-signal-2-1', 'series-signal', 'season-signal-2', 'Signal Drift', 2, 1, 'Second Harmonic', 49, null),
  episode('ep-kitchen-1-1', 'series-kitchen', 'season-kitchen-1', 'After Kitchen', 1, 1, 'Service', 42, null),
  episode('ep-kitchen-1-2', 'series-kitchen', 'season-kitchen-1', 'After Kitchen', 1, 2, 'Closing Duties', 44, 0.3),
]

const libraries: JellyfinItem[] = [
  {
    id: 'lib-movies',
    name: 'Movies',
    type: 'CollectionFolder',
    collectionType: 'movies',
    primaryImageTag: 'lib',
    sortName: 'Movies',
  },
  {
    id: 'lib-tv',
    name: 'TV Shows',
    type: 'CollectionFolder',
    collectionType: 'tvshows',
    primaryImageTag: 'lib',
    sortName: 'TV Shows',
  },
  {
    id: 'lib-collections',
    name: 'Collections',
    type: 'CollectionFolder',
    collectionType: 'boxsets',
    primaryImageTag: 'lib',
    sortName: 'Collections',
  },
]

const spotlightCollection: JellyfinItem = {
  id: 'box-festival',
  name: 'Festival Night',
  type: 'BoxSet',
  overview: 'A mock spotlight collection for UI work.',
  primaryImageTag: 'box',
  backdropImageTag: 'box',
  sortName: 'Festival Night',
}

const personHues: Record<string, number> = {
  'person-ada': 210,
  'person-jon': 18,
  'person-mira': 320,
  'person-kai': 150,
}

const favorites = new Set<string>()
const played = new Set<string>(['ep-signal-1-1'])

function movie(
  id: string,
  name: string,
  year: number,
  minutes: number,
  rating: number,
  official: string,
  hue: number,
  genres: string[],
  resumeFraction: number | null,
): MockMovie {
  const runTimeTicks = minutes * TICKS_PER_MIN
  const playbackPositionTicks = resumeFraction != null
    ? Math.round(runTimeTicks * resumeFraction)
    : null
  return {
    id,
    name,
    type: 'Movie',
    sortName: name,
    overview: `${name} is mock Festival catalog filler — enough metadata to exercise home, detail, and search.`,
    productionYear: year,
    communityRating: rating,
    officialRating: official,
    runTimeTicks,
    primaryImageTag: 'p',
    backdropImageTag: 'b',
    genres,
    studios: ['Mock Studio'],
    people: people.map(person => ({ ...person })),
    mediaSourceId: `${id}-source`,
    mediaStreams: defaultStreams(),
    chapters: [
      { name: 'Opening', startPositionTicks: 0 },
      { name: 'Midpoint', startPositionTicks: Math.round(runTimeTicks * 0.45) },
    ],
    trickplay: MOCK_TRICKPLAY,
    remoteTrailers: [{ url: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ', name: 'Official Trailer' }],
    localTrailerCount: 1,
    specialFeatureCount: 2,
    isFavorite: false,
    played: false,
    playedPercentage: resumeFraction != null ? resumeFraction * 100 : null,
    playbackPositionTicks,
    path: `/mock/${id}.mp4`,
    _hue: hue,
  }
}

function series(
  id: string,
  name: string,
  year: number,
  rating: number,
  official: string,
  hue: number,
  genres: string[],
  childCount: number,
): MockSeries {
  return {
    id,
    name,
    type: 'Series',
    sortName: name,
    overview: `${name} is a mock series used to exercise seasons, episodes, and next-up rows.`,
    productionYear: year,
    communityRating: rating,
    officialRating: official,
    primaryImageTag: 'p',
    backdropImageTag: 'b',
    genres,
    studios: ['Mock Television'],
    people: people.map(person => ({ ...person })),
    childCount,
    isFavorite: false,
    played: false,
    _hue: hue,
  }
}

function season(id: string, seriesId: string, index: number, name: string): JellyfinItem {
  const parent = seriesList.find(item => item.id === seriesId)!
  return {
    id,
    name,
    type: 'Season',
    seriesId,
    seriesName: parent.name,
    indexNumber: index,
    parentIndexNumber: index,
    primaryImageTag: 'p',
    sortName: `${index.toString().padStart(2, '0')} - ${name}`,
  }
}

function episode(
  id: string,
  seriesId: string,
  seasonId: string,
  seriesName: string,
  season: number,
  index: number,
  name: string,
  minutes: number,
  resumeFraction: number | null,
): MockEpisode {
  const parent = seriesList.find(item => item.id === seriesId)!
  const runTimeTicks = minutes * TICKS_PER_MIN
  const playbackPositionTicks = resumeFraction != null
    ? Math.round(runTimeTicks * resumeFraction)
    : null
  return {
    id,
    name,
    type: 'Episode',
    seriesId,
    seasonId,
    seriesName,
    indexNumber: index,
    parentIndexNumber: season,
    overview: `Mock episode ${season}x${index} of ${seriesName}.`,
    runTimeTicks,
    primaryImageTag: 'p',
    backdropImageTag: 'b',
    parentBackdropItemId: seriesId,
    parentBackdropImageTag: 'b',
    seriesPrimaryImageTag: 'p',
    mediaSourceId: `${id}-source`,
    mediaStreams: defaultStreams(),
    trickplay: MOCK_TRICKPLAY,
    isFavorite: false,
    played: false,
    playedPercentage: resumeFraction != null ? resumeFraction * 100 : null,
    playbackPositionTicks,
    path: `/mock/${id}.mp4`,
    _hue: parent._hue + index * 8,
  }
}

function defaultStreams() {
  return [
    {
      index: 0,
      type: 'Video' as const,
      codec: 'h264',
      displayTitle: '1080p H264',
      isDefault: true,
      isExternal: false,
      isTextSubtitle: false,
      width: 1920,
      height: 1080,
    },
    {
      index: 1,
      type: 'Audio' as const,
      codec: 'aac',
      language: 'eng',
      displayTitle: 'English AAC',
      isDefault: true,
      isExternal: false,
      isTextSubtitle: false,
    },
    {
      index: 2,
      type: 'Subtitle' as const,
      codec: 'vtt',
      language: 'eng',
      displayTitle: 'English',
      isDefault: false,
      isExternal: true,
      isTextSubtitle: true,
    },
  ]
}

function withUserFlags<T extends JellyfinItem>(item: T): T {
  return {
    ...item,
    isFavorite: favorites.has(item.id),
    played: played.has(item.id),
  }
}

function allCatalogItems(): JellyfinItem[] {
  return [...movies, ...seriesList, ...episodes].map(withUserFlags)
}

function findRaw(id: string): (MockMovie | MockSeries | MockEpisode | JellyfinItem) | undefined {
  return (
    movies.find(item => item.id === id)
    ?? seriesList.find(item => item.id === id)
    ?? episodes.find(item => item.id === id)
    ?? seasons.find(item => item.id === id)
    ?? libraries.find(item => item.id === id)
    ?? (spotlightCollection.id === id ? spotlightCollection : undefined)
    ?? mockExtrasFor(id.replace(/^extra-(.+)-\d+$/, '$1')).find(item => item.id === id)
  )
}

const MOCK_EXTRAS: { name: string, extraType: string, minutes: number }[] = [
  { name: 'Teaser Trailer', extraType: 'Trailer', minutes: 2 },
  { name: 'Making Of', extraType: 'BehindTheScenes', minutes: 14 },
  { name: 'The Lost Scene', extraType: 'DeletedScene', minutes: 4 },
]

/** Movies get a trailer and two special features, with ids `extra-<movie>-<n>`. */
function mockExtrasFor(movieId: string): JellyfinItem[] {
  const movie = movies.find(item => item.id === movieId)
  if (!movie?.localTrailerCount) return []
  return MOCK_EXTRAS.map((extra, i) => ({
    id: `extra-${movieId}-${i}`,
    name: extra.name,
    type: extra.extraType === 'Trailer' ? 'Trailer' : 'Video',
    extraType: extra.extraType,
    runTimeTicks: extra.minutes * TICKS_PER_MIN,
    primaryImageTag: 'p',
    mediaSourceId: `extra-${movieId}-${i}-source`,
    mediaStreams: defaultStreams(),
    isFavorite: false,
    played: false,
  }))
}

export function mockGetExtras(itemId: string): JellyfinItem[] {
  return mockExtrasFor(itemId)
}

function hueFor(item: { id: string, _hue?: number }): number {
  if (typeof item._hue === 'number') return item._hue
  if (item.id.startsWith('lib')) return 200
  if (item.id.startsWith('box')) return 48
  if (item.id.startsWith('season-signal')) return 225
  if (item.id.startsWith('season-kitchen')) return 40
  return 220
}

export function mockImageUrl(
  itemId: string,
  type: 'Primary' | 'Backdrop',
  _tag: string | null | undefined,
  _maxWidth: number,
): string | null {
  if (itemId.startsWith('person-')) {
    return personUri(
      people.find(person => person.id === itemId)?.name ?? '?',
      personHues[itemId] ?? 200,
    )
  }
  const item = findRaw(itemId)
  if (!item) return null
  const hue = hueFor(item as { id: string, _hue?: number })
  if (type === 'Backdrop') {
    return backdropUri(item.name, hue)
  }
  return posterUri(item.name, hue)
}

export function mockPersonImageUrl(person: JellyfinPerson): string | null {
  return mockImageUrl(person.id, 'Primary', person.primaryImageTag, 256)
}

export function mockGetLibraries(): JellyfinItem[] {
  return libraries.map(withUserFlags)
}

export function mockGetHome(): JellyfinHome {
  const resume = allCatalogItems().filter(item => (item.playbackPositionTicks ?? 0) > 0)
  const nextUp = [withUserFlags(episodes[2]!), withUserFlags(episodes[5]!)]
    .filter(item => !resume.some(resumeItem => resumeItem.id === item.id))
  return {
    resume,
    nextUp,
    recentlyAddedMovies: movies.slice(0, 6).map(withUserFlags),
    recentlyAddedTv: [withUserFlags(episodes[1]!), withUserFlags(episodes[5]!), withUserFlags(episodes[3]!)],
  }
}

export function mockGetHomeExtras(): JellyfinHomeExtras {
  const spotlight: JellyfinCollection = {
    collection: withUserFlags(spotlightCollection),
    items: movies.slice(0, 4).map(withUserFlags),
  }
  return {
    topRated: [...movies].sort((a, b) => (b.communityRating ?? 0) - (a.communityRating ?? 0)).slice(0, 9).map(withUserFlags),
    spotlight,
  }
}

export function mockGetLibraryItems(libraryId: string, sortBy: LibrarySort = 'SortName'): JellyfinItem[] {
  const items = libraryId === 'lib-tv'
    ? seriesList.map(withUserFlags)
    : libraryId === 'lib-collections'
      ? [withUserFlags(spotlightCollection)]
      : movies.map(withUserFlags)
  return sortItems(items, sortBy)
}

export function mockGetLibraryTotal(libraryId: string): number {
  return mockGetLibraryItems(libraryId).length
}

export function mockGetLibraryGenreCounts(libraryId: string): GenreCount[] {
  return countGenres(mockGetLibraryItems(libraryId))
}

function sortItems(items: JellyfinItem[], sortBy: LibrarySort): JellyfinItem[] {
  const copy = [...items]
  copy.sort((a, b) => {
    if (sortBy === 'DateCreated') return (b.productionYear ?? 0) - (a.productionYear ?? 0)
    if (sortBy === 'ProductionYear') return (b.productionYear ?? 0) - (a.productionYear ?? 0)
    if (sortBy === 'CommunityRating') return (b.communityRating ?? 0) - (a.communityRating ?? 0)
    return (a.sortName || a.name).localeCompare(b.sortName || b.name)
  })
  return copy
}

export function mockGetItem(itemId: string): JellyfinItem {
  const item = findRaw(itemId)
  if (!item || item.type === 'CollectionFolder') {
    throw new Error(`Mock item not found: ${itemId}`)
  }
  return withUserFlags(item)
}

export function mockGetSimilar(itemId: string): JellyfinItem[] {
  const item = mockGetItem(itemId)
  const pool = item.type === 'Series' || item.type === 'Episode' ? seriesList : movies
  return pool
    .filter(candidate => candidate.id !== itemId && candidate.id !== item.seriesId)
    .slice(0, 8)
    .map(withUserFlags)
}

export function mockGetSeasons(seriesId: string): JellyfinItem[] {
  return seasons.filter(seasonItem => seasonItem.seriesId === seriesId).map(withUserFlags)
}

export function mockGetEpisodes(seriesId: string, seasonId?: string): JellyfinItem[] {
  return episodes
    .filter(episodeItem => episodeItem.seriesId === seriesId && (!seasonId || episodeItem.seasonId === seasonId))
    .map(withUserFlags)
}

export function mockGetSeriesNextUp(seriesId: string): JellyfinItem | null {
  const unwatched = episodes.find(episodeItem =>
    episodeItem.seriesId === seriesId && !played.has(episodeItem.id))
  return unwatched ? withUserFlags(unwatched) : null
}

export function mockSearch(term: string): JellyfinSearchResults {
  const trimmed = term.trim().toLowerCase()
  if (!trimmed) return { items: [], people: [] }
  return {
    items: allCatalogItems().filter(item =>
      item.name.toLowerCase().includes(trimmed)
      || (item.seriesName?.toLowerCase().includes(trimmed) ?? false)
      || (item.genres?.some(genre => genre.toLowerCase().includes(trimmed)) ?? false)),
    people: people.filter(person => person.name.toLowerCase().includes(trimmed)),
  }
}

export function mockGetPersonItems(personId: string): JellyfinItem[] {
  if (!people.some(person => person.id === personId)) return []
  return [...movies.slice(0, 4), ...seriesList].map(withUserFlags)
}

export function mockSetFavorite(itemId: string, favorite: boolean) {
  if (favorite) favorites.add(itemId)
  else favorites.delete(itemId)
}

export function mockSetPlayed(itemId: string, value: boolean) {
  if (value) played.add(itemId)
  else played.delete(itemId)
}

export function mockPlaybackPlan(itemId: string, startPositionTicks = 0): JellyfinPlaybackPlan {
  const item = mockGetItem(itemId)
  return {
    itemId,
    mediaSourceId: item.mediaSourceId || `${itemId}-source`,
    playSessionId: `mock-play-${itemId}`,
    directUrl: MOCK_SAMPLE_VIDEO,
    directMethod: 'DirectPlay',
    hlsUrl: null,
    startPositionTicks,
    audioStreamIndex: 1,
    subtitleStreamIndex: null,
  }
}

/** Episodes get a 0:20–1:05 intro so the Skip Intro button can be exercised. */
export function mockGetMediaSegments(itemId: string): JellyfinMediaSegment[] {
  if (!episodes.some(episodeItem => episodeItem.id === itemId)) return []
  return [{ type: 'Intro', startTicks: 20 * 10_000_000, endTicks: 65 * 10_000_000 }]
}

export function mockSubtitleTrackUrl(): string | null {
  return `data:text/vtt,${encodeURIComponent('WEBVTT\n\n')}`
}
