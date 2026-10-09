export type JellyfinSessionPayload = {
  baseUrl: string
  userId: string
  accessToken: string
  serverId: string
  deviceId: string
  /** Signed in with a Jellyfin username and password rather than Soup Identity. */
  direct?: boolean
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
  officialRating?: string | null
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

export type JellyfinHome = {
  resume: JellyfinItem[]
  nextUp: JellyfinItem[]
  recentlyAddedMovies: JellyfinItem[]
  recentlyAddedTv: JellyfinItem[]
}

/** Home rows below the fold, loaded after the first paint. */
export type JellyfinHomeExtras = {
  topRated: JellyfinItem[]
  spotlight: JellyfinCollection | null
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
