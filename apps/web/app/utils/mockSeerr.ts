// Seerr-shaped JSON for mock mode, so the Explore tab works without a server and the real
// mappers in utils/seerr.ts get exercised. Posters reuse the public-domain scans in public/posters.
import type { SeerrMediaType, SeerrRequestPayload } from '~/types/seerr'

type MockTitle = {
  id: number
  mediaType: SeerrMediaType
  title: string
  date: string
  poster: string
  overview: string
  vote: number
  runtime: number
  genres: string[]
  seasons?: number
  /** Seerr MediaStatus, when the library knows the title. */
  status?: number
  /** Which mock Jellyfin item the title is, when it's in the library. */
  jellyfinId?: string
}

const TITLES: MockTitle[] = [
  { id: 101, mediaType: 'movie', title: 'Metropolis', date: '1927-01-10', poster: 'metropolis', vote: 8.2, runtime: 153, genres: ['Drama', 'Science Fiction'], status: 5, jellyfinId: 'movie-1', overview: 'In a futuristic city sharply divided between the working class and the city planners, the son of the city\'s mastermind falls in love with a working-class prophet.' },
  { id: 102, mediaType: 'movie', title: 'The Cabinet of Dr. Caligari', date: '1920-02-27', poster: 'caligari', vote: 8.0, runtime: 76, genres: ['Horror', 'Mystery'], overview: 'Hypnotist Dr. Caligari uses a somnambulist, Cesare, to commit murders.' },
  { id: 103, mediaType: 'movie', title: 'The General', date: '1926-12-25', poster: 'the-general', vote: 8.1, runtime: 78, genres: ['Comedy', 'Action'], status: 3, overview: 'When Union spies steal an engineer\'s beloved locomotive, he pursues it single-handedly and straight through enemy lines.' },
  { id: 104, mediaType: 'movie', title: 'The Kid', date: '1921-01-21', poster: 'the-kid', vote: 8.2, runtime: 68, genres: ['Comedy', 'Drama'], overview: 'The Tramp cares for an abandoned child, but events put their relationship in jeopardy.' },
  { id: 105, mediaType: 'movie', title: 'Night of the Living Dead', date: '1968-10-01', poster: 'night-of-the-living-dead', vote: 7.8, runtime: 96, genres: ['Horror'], status: 2, overview: 'A group of people try to survive when the dead start to rise.' },
  { id: 106, mediaType: 'movie', title: 'Charade', date: '1963-12-05', poster: 'charade', vote: 7.8, runtime: 113, genres: ['Comedy', 'Mystery', 'Romance'], overview: 'Romance and suspense ensue in Paris as a woman is pursued by several men who want a fortune her murdered husband had stolen.' },
  { id: 201, mediaType: 'tv', title: 'The Phantom of the Opera', date: '1925-11-15', poster: 'phantom-of-the-opera', vote: 7.6, runtime: 45, genres: ['Drama', 'Horror'], seasons: 3, status: 4, jellyfinId: 'series-1', overview: 'A disfigured composer haunts the Paris Opera House and falls for a young soprano.' },
  { id: 202, mediaType: 'tv', title: 'Safety Last!', date: '1923-04-01', poster: 'safety-last', vote: 8.1, runtime: 30, genres: ['Comedy'], seasons: 2, overview: 'A boy leaves his small country town and heads to the big city to get a job.' },
  { id: 203, mediaType: 'tv', title: 'The Gold Rush', date: '1925-06-26', poster: 'gold-rush', vote: 8.1, runtime: 50, genres: ['Adventure', 'Comedy'], seasons: 4, overview: 'A prospector goes to the Klondike in search of gold and finds it and more.' },
  { id: 204, mediaType: 'tv', title: 'Sunrise', date: '1927-09-23', poster: 'sunrise', vote: 8.0, runtime: 55, genres: ['Drama', 'Romance'], seasons: 1, overview: 'A married farmer falls under the spell of a slatternly woman from the city.' },
  { id: 205, mediaType: 'tv', title: 'His Girl Friday', date: '1940-01-18', poster: 'his-girl-friday', vote: 7.8, runtime: 25, genres: ['Comedy'], seasons: 5, overview: 'A newspaper editor uses every trick in the book to keep his ace reporter ex-wife from remarrying.' },
]

type MockRequest = {
  id: number
  tmdbId: number
  status: number
  seasons: number[]
  createdAt: string
}

const requests: MockRequest[] = [
  { id: 1, tmdbId: 103, status: 2, seasons: [], createdAt: '2026-10-20T18:12:00.000Z' },
  { id: 2, tmdbId: 105, status: 1, seasons: [], createdAt: '2026-10-25T09:40:00.000Z' },
  { id: 3, tmdbId: 201, status: 2, seasons: [1, 2], createdAt: '2026-09-02T20:05:00.000Z' },
]
let nextRequestId = 4

const MOCK_USER = { id: 1, displayName: 'Mock Viewer', avatar: null, permissions: 32 }

function posterPath(name: string): string {
  const baseURL = useRuntimeConfig().app.baseURL.replace(/\/$/, '')
  return `${baseURL}/posters/${name}.jpg`
}

function mediaStatusFor(title: MockTitle): number | undefined {
  const own = requests.filter(request => request.tmdbId === title.id && request.status !== 3)
  if (title.status) return title.status
  if (own.some(request => request.status === 2)) return 3
  if (own.some(request => request.status === 1)) return 2
  return undefined
}

function rawRequest(request: MockRequest, withMedia = true) {
  const title = TITLES.find(entry => entry.id === request.tmdbId)!
  return {
    id: request.id,
    status: request.status,
    is4k: false,
    createdAt: request.createdAt,
    updatedAt: request.createdAt,
    requestedBy: MOCK_USER,
    seasons: request.seasons.map(seasonNumber => ({ seasonNumber, status: mediaStatusFor(title) ?? 1 })),
    ...(withMedia ? { media: { id: title.id, tmdbId: title.id, mediaType: title.mediaType, status: mediaStatusFor(title) ?? 1 } } : {}),
  }
}

function mediaInfo(title: MockTitle) {
  const status = mediaStatusFor(title)
  if (!status) return undefined
  const own = requests.filter(request => request.tmdbId === title.id)
  return {
    id: title.id,
    tmdbId: title.id,
    tvdbId: null,
    status,
    jellyfinMediaId: title.jellyfinId ?? null,
    seasons: title.mediaType === 'tv' && status === 4 ? [{ seasonNumber: 1, status: 5 }, { seasonNumber: 2, status: 3 }] : [],
    requests: own.map(request => rawRequest(request, false)),
  }
}

function rawTitle(title: MockTitle) {
  const common = {
    id: title.id,
    mediaType: title.mediaType,
    overview: title.overview,
    posterPath: posterPath(title.poster),
    backdropPath: null,
    voteAverage: title.vote,
    mediaInfo: mediaInfo(title),
  }
  return title.mediaType === 'movie'
    ? { ...common, title: title.title, releaseDate: title.date }
    : { ...common, name: title.title, firstAirDate: title.date }
}

function page(items: MockTitle[]) {
  return { page: 1, totalPages: 1, totalResults: items.length, results: items.map(rawTitle) }
}

export function mockSeerrStatus() {
  return { configured: true, reachable: true, version: 'mock', user: MOCK_USER, error: null }
}

export function mockSeerrSearch(term: string) {
  const needle = term.trim().toLowerCase()
  const titles = needle ? TITLES.filter(title => title.title.toLowerCase().includes(needle)) : []
  const result = page(titles)
  if (needle && 'chaplin'.includes(needle)) {
    result.results.push({
      id: 13848,
      mediaType: 'person',
      name: 'Charlie Chaplin',
      profilePath: null,
      knownFor: [rawTitle(TITLES[3]!), rawTitle(TITLES[8]!)],
    } as never)
  }
  return result
}

export function mockSeerrDiscover(path: string) {
  if (path.startsWith('discover/trending')) return page([...TITLES].sort((a, b) => b.vote - a.vote))
  if (path.startsWith('discover/movies/upcoming')) return page(TITLES.filter(title => title.mediaType === 'movie').slice(3))
  if (path.startsWith('discover/movies')) return page(TITLES.filter(title => title.mediaType === 'movie'))
  if (path.startsWith('discover/tv')) return page(TITLES.filter(title => title.mediaType === 'tv'))
  return page([])
}

export function mockSeerrDetails(mediaType: SeerrMediaType, tmdbId: number) {
  const title = TITLES.find(entry => entry.id === tmdbId && entry.mediaType === mediaType)
  if (!title) return null
  const base = rawTitle(title)
  const credits = {
    cast: [
      { id: 1, name: 'Ada Meridian', character: 'The Lead', profilePath: null },
      { id: 2, name: 'Jon Harbor', character: 'The Rival', profilePath: null },
    ],
  }
  const genres = title.genres.map((name, index) => ({ id: index + 1, name }))
  if (mediaType === 'movie') {
    return { ...base, runtime: title.runtime, genres, tagline: 'A mock classic.', credits, imdbId: 'tt0000001', relatedVideos: [] }
  }
  return {
    ...base,
    episodeRunTime: [title.runtime],
    genres,
    tagline: null,
    credits,
    status: 'Ended',
    networks: [{ name: 'Mock Network' }],
    externalIds: { tvdbId: 70000 + title.id },
    seasons: Array.from({ length: title.seasons ?? 1 }, (_, index) => ({
      id: title.id * 10 + index + 1,
      seasonNumber: index + 1,
      name: `Season ${index + 1}`,
      episodeCount: 8 + index,
      airDate: `${1920 + index}-01-01`,
      posterPath: null,
      overview: null,
    })),
  }
}

export function mockSeerrRequests(filter: string) {
  const list = [...requests].sort((a, b) => b.createdAt.localeCompare(a.createdAt)).filter((request) => {
    if (filter === 'pending') return request.status === 1
    if (filter === 'approved' || filter === 'processing') return request.status === 2
    if (filter === 'available') return TITLES.find(title => title.id === request.tmdbId)?.status === 5
    return true
  })
  return {
    pageInfo: { pages: 1, pageSize: 20, results: list.length, page: 1 },
    results: list.map(request => rawRequest(request)),
  }
}

export function mockSeerrCreateRequest(payload: SeerrRequestPayload) {
  const title = TITLES.find(entry => entry.id === payload.mediaId && entry.mediaType === payload.mediaType)
  if (!title) throw new SeerrError(404, 'not_found', 'Unknown title')
  const seasons = payload.mediaType === 'tv'
    ? (payload.seasons === 'all' || !payload.seasons
        ? Array.from({ length: title.seasons ?? 1 }, (_, index) => index + 1)
        : payload.seasons)
    : []
  const request: MockRequest = { id: nextRequestId++, tmdbId: title.id, status: 1, seasons, createdAt: new Date().toISOString() }
  requests.push(request)
  return rawRequest(request)
}

export function mockSeerrCancelRequest(id: number) {
  const index = requests.findIndex(request => request.id === id)
  if (index < 0) throw new SeerrError(404, 'not_found', 'Request not found')
  if (requests[index]!.status !== 1) throw new SeerrError(403, 'forbidden', 'Only your own pending requests can be withdrawn')
  requests.splice(index, 1)
}
