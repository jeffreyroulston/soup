export type JellyfinSessionPayload = {
  baseUrl: string
  userId: string
  accessToken: string
  serverId: string
  deviceId: string
  /** Signed in with a Jellyfin username and password rather than Soup Identity. */
  direct?: boolean
  /** Soup roster id of the server, for Soup sign-ins. */
  soupServerId?: string
  /** Display name from the Soup roster. */
  serverName?: string
}

export type AuthSessionResponse = {
  email: string
  jellyfin: JellyfinSessionPayload | null
}

export type JellyfinPerson = {
  id: string
  name: string
  role?: string | null
  type?: string | null
  primaryImageTag?: string | null
}

export type JellyfinMediaStreamType = 'Video' | 'Audio' | 'Subtitle'

export type JellyfinMediaStream = {
  index: number
  type: JellyfinMediaStreamType
  codec?: string | null
  language?: string | null
  displayTitle?: string | null
  isDefault: boolean
  isExternal: boolean
  /** True when the browser can render the stream as a text <track>. */
  isTextSubtitle: boolean
  width?: number | null
  height?: number | null
}

export type JellyfinChapter = {
  name: string
  startPositionTicks: number
  /** Set only when the library extracts chapter images and this one has been generated. */
  imageTag?: string | null
}

export type JellyfinMediaSegmentType = 'Intro' | 'Outro' | 'Recap' | 'Preview' | 'Commercial'

/** A marked stretch of an item (Jellyfin 10.10+ media segments, e.g. from Intro Skipper). */
export type JellyfinMediaSegment = {
  type: JellyfinMediaSegmentType
  startTicks: number
  endTicks: number
}

/** Seek-bar thumbnails: sprite sheets of `tileWidth` × `tileHeight` frames, one every `interval` ms. */
export type JellyfinTrickplay = {
  /** Thumbnail width; also the {width} in the tile URL. */
  width: number
  height: number
  tileWidth: number
  tileHeight: number
  thumbnailCount: number
  interval: number
}

/** A trailer hosted elsewhere (usually YouTube). */
export type JellyfinRemoteTrailer = {
  url: string
  name: string | null
}

export type JellyfinItem = {
  id: string
  name: string
  type: string
  sortName?: string | null
  genres?: string[]
  studios?: string[]
  people?: JellyfinPerson[]
  isFavorite?: boolean
  played?: boolean
  seriesId?: string | null
  seasonId?: string | null
  premiereDate?: string | null
  endDate?: string | null
  childCount?: number | null
  /** Everything under a folder item (a series' seasons and episodes); only requested where needed. */
  recursiveItemCount?: number | null
  path?: string | null
  mediaSourceId?: string | null
  mediaStreams?: JellyfinMediaStream[]
  chapters?: JellyfinChapter[]
  /** Thumbnails for the first media source, at the size closest to the seek-bar preview. */
  trickplay?: JellyfinTrickplay | null
  remoteTrailers?: JellyfinRemoteTrailer[]
  localTrailerCount?: number | null
  specialFeatureCount?: number | null
  /** Set on trailers and special features: Trailer, BehindTheScenes, DeletedScene… */
  extraType?: string | null
  collectionType?: string | null
  overview?: string | null
  productionYear?: number | null
  communityRating?: number | null
  criticRating?: number | null
  officialRating?: string | null
  /** Series airing status from Jellyfin (Continuing, Ended, …). */
  status?: string | null
  originalTitle?: string | null
  productionLocations?: string[]
  tags?: string[]
  networks?: string[]
  /** External catalogue ids, e.g. Imdb / Tmdb / Tvdb. */
  providerIds?: Record<string, string>
  runTimeTicks?: number | null
  primaryImageTag?: string | null
  backdropImageTag?: string | null
  parentBackdropItemId?: string | null
  parentBackdropImageTag?: string | null
  seriesName?: string | null
  seriesPrimaryImageTag?: string | null
  indexNumber?: number | null
  parentIndexNumber?: number | null
  playedPercentage?: number | null
  playbackPositionTicks?: number | null
}

export type JellyfinCollection = {
  collection: JellyfinItem
  items: JellyfinItem[]
}

/** A titled home row, e.g. one genre or one "Because you watched". */
export type JellyfinShelf = {
  title: string
  items: JellyfinItem[]
  /** Where "See All" goes, if anywhere. */
  seeAllTo?: string | null
}

export type JellyfinHome = {
  resume: JellyfinItem[]
  nextUp: JellyfinItem[]
  /** Recently Added for each video library (titled with the library's name), in the server's order. */
  recentlyAdded: JellyfinShelf[]
}

/** A Soup-curated pack matched against this library (hard-coded ids, not a Jellyfin BoxSet). */
export type SoupCuratedCollection = {
  id: string
  title: string
  description: string
  itemCount: number
  countLabel: string
  theme: { bg: string, accent: string, mid: string, label: string }
  to: string
  items: JellyfinItem[]
}

/** The home collection card: Soup packs matched to the library, or a BoxSet fallback. */
export type HomeCollection = {
  /** Every hard-coded Soup collection with enough library hits; the home page shows one. */
  curated: SoupCuratedCollection[]
  /** Jellyfin BoxSet spotlight when no curated packs match. */
  spotlight: JellyfinCollection | null
}

/** Home rows below the fold, loaded after the first paint. */
export type JellyfinHomeExtras = {
  topRated: JellyfinItem[]
  /** Highly rated titles the user hasn't watched, minus anything already in `topRated`. */
  unwatchedTopRated: JellyfinItem[]
}

export type JellyfinSearchResults = {
  items: JellyfinItem[]
  people: JellyfinPerson[]
}

export type JellyfinPlayMethod = 'DirectPlay' | 'DirectStream' | 'Transcode'

export type JellyfinPlaybackPlan = {
  itemId: string
  mediaSourceId: string
  playSessionId: string
  /** Prefer this for progressive MP4/WebM in <video>. */
  directUrl: string | null
  directMethod: JellyfinPlayMethod | null
  /** HLS master playlist when direct isn't available. */
  hlsUrl: string | null
  startPositionTicks: number
  audioStreamIndex?: number | null
  subtitleStreamIndex?: number | null
  /** Quality cap the stream was requested with, or null for none. */
  maxBitrate?: number | null
}
