import type {
  JellyfinPlayMethod,
  JellyfinPlaybackPlan,
} from '~/types/jellyfin'
import { mockPlaybackPlan } from '~/utils/mockCatalog'
import { isMockMode } from '~/utils/mockMode'

const WEB_DEVICE_PROFILE = {
  Name: 'Soup Web',
  MaxStreamingBitrate: 120_000_000,
  MaxStaticBitrate: 120_000_000,
  MusicStreamingTranscodingBitrate: 384_000,
  DirectPlayProfiles: [
    {
      Container: 'mp4,m4v',
      Type: 'Video',
      VideoCodec: 'h264,av1',
      AudioCodec: 'aac,mp3,opus',
    },
    {
      Container: 'webm',
      Type: 'Video',
      VideoCodec: 'vp8,vp9,av1',
      AudioCodec: 'vorbis,opus',
    },
  ],
  TranscodingProfiles: [
    {
      Container: 'ts',
      Type: 'Video',
      Protocol: 'hls',
      AudioCodec: 'aac',
      VideoCodec: 'h264',
      Context: 'Streaming',
      MaxAudioChannels: '2',
      MinSegments: '1',
      BreakOnNonKeyFrames: true,
    },
  ],
  ContainerProfiles: [],
  CodecProfiles: [
    {
      Type: 'Video',
      Codec: 'h264',
      Conditions: [
        { Condition: 'EqualsAny', Property: 'VideoProfile', Value: 'high|main|baseline|constrained baseline', IsRequired: false },
        { Condition: 'LessThanEqual', Property: 'VideoLevel', Value: '51', IsRequired: false },
      ],
    },
  ],
  SubtitleProfiles: [
    { Format: 'vtt', Method: 'External' },
    { Format: 'webvtt', Method: 'External' },
    { Format: 'srt', Method: 'External' },
  ],
  ResponseProfiles: [
    {
      Type: 'Video',
      Container: 'm3u8',
      MimeType: 'application/x-mpegURL',
      Protocol: 'hls',
    },
  ],
}

/** Optional track picks sent with a PlaybackInfo request. */
export type StreamSelection = {
  audioStreamIndex?: number | null
  /** Set only for subtitles Jellyfin must burn in (image formats). */
  subtitleStreamIndex?: number | null
  /** Bitrate cap in bits/s; Jellyfin transcodes (and scales down) to fit. Null = no cap. */
  maxBitrate?: number | null
}

const DEFAULT_MAX_BITRATE = 120_000_000

const BROWSER_CONTAINERS = new Set(['mp4', 'm4v', 'webm'])
const BROWSER_VIDEO_CODECS = ['h264', 'avc', 'avc1', 'vp8', 'vp9', 'av01', 'av1']
const BROWSER_AUDIO_CODECS = ['aac', 'mp3', 'opus', 'vorbis', 'flac', 'mp4a']

function isBrowserContainer(container: string): boolean {
  const primary = container.split(',')[0]?.trim().toLowerCase() ?? ''
  return BROWSER_CONTAINERS.has(primary)
}

function codecMatches(codec: string, allowed: string[]): boolean {
  const normalized = codec.toLowerCase()
  return allowed.some(item => normalized === item || normalized.includes(item))
}

function isBrowserSafeSource(source: Record<string, unknown>): boolean {
  if (!isBrowserContainer(String(source.Container ?? ''))) return false
  const streams = Array.isArray(source.MediaStreams) ? source.MediaStreams : []
  let hasVideo = false
  for (const raw of streams) {
    if (!raw || typeof raw !== 'object') continue
    const stream = raw as Record<string, unknown>
    const type = String(stream.Type ?? '')
    const codec = String(stream.Codec ?? '')
    if (!codec) continue
    if (type === 'Video') {
      hasVideo = true
      if (!codecMatches(codec, BROWSER_VIDEO_CODECS)) return false
    }
    if (type === 'Audio' && !codecMatches(codec, BROWSER_AUDIO_CODECS)) {
      // Surround tracks like DTS/TrueHD break progressive <video> even in mp4.
      return false
    }
  }
  return hasVideo
}

export function usePlayback() {
  const client = useJellyfinClient()
  const { $queryClient } = useNuxtApp()
  const { requireSession } = client
  const mock = isMockMode()

  /** Absolute URL for a stream path Jellyfin returned, with the token in the query. */
  function resolvePlaybackUrl(pathOrUrl: string): string {
    const session = requireSession()
    const url = new URL(pathOrUrl.replace(/^\//, ''), `${session.baseUrl}/`)
    if (!url.searchParams.has('api_key')) url.searchParams.set('api_key', session.accessToken)
    return url.toString()
  }

  async function jfPost(path: string, body: unknown): Promise<unknown> {
    const response = await client.send('POST', path, { body })
    if (!response.ok) {
      const text = await response.text().catch(() => '')
      throw new Error(text || `Jellyfin ${response.status} for ${path}`)
    }
    const contentType = response.headers.get('content-type') || ''
    return contentType.includes('application/json') ? response.json() : null
  }

  async function fetchPlaybackInfo(
    itemId: string,
    startPositionTicks: number,
    options: {
      enableDirectPlay: boolean
      enableDirectStream: boolean
    },
    streams: StreamSelection = {},
  ): Promise<Record<string, unknown>> {
    const session = requireSession()
    const selection: Record<string, number> = {}
    if (streams.audioStreamIndex != null) selection.AudioStreamIndex = streams.audioStreamIndex
    if (streams.subtitleStreamIndex != null) selection.SubtitleStreamIndex = streams.subtitleStreamIndex
    const maxBitrate = streams.maxBitrate ?? DEFAULT_MAX_BITRATE
    return (await jfPost(`Items/${itemId}/PlaybackInfo`, {
      ...selection,
      UserId: session.userId,
      StartTimeTicks: startPositionTicks,
      IsPlayback: true,
      AutoOpenLiveStream: true,
      EnableDirectPlay: options.enableDirectPlay,
      EnableDirectStream: options.enableDirectStream,
      EnableTranscoding: true,
      AllowVideoStreamCopy: true,
      AllowAudioStreamCopy: true,
      MaxStreamingBitrate: maxBitrate,
      DeviceProfile: { ...WEB_DEVICE_PROFILE, MaxStreamingBitrate: maxBitrate },
    })) as Record<string, unknown>
  }

  function planFromPlaybackInfo(
    itemId: string,
    startPositionTicks: number,
    decoded: Record<string, unknown>,
    streams: StreamSelection = {},
  ): JellyfinPlaybackPlan {
    const session = requireSession()
    const sources = decoded.MediaSources
    if (!Array.isArray(sources) || !sources.length || typeof sources[0] !== 'object') {
      throw new Error('Jellyfin did not provide a playable media source')
    }
    const source = sources[0] as Record<string, unknown>
    const mediaSourceId = String(source.Id ?? itemId)
    const playSessionId = String(decoded.PlaySessionId ?? '')
    const container = String(source.Container ?? 'mp4')
    const supportsDirectPlay = Boolean(source.SupportsDirectPlay)
    const supportsDirectStream = Boolean(source.SupportsDirectStream)
    const directStreamUrl = source.DirectStreamUrl as string | undefined
    const transcodingUrl = source.TranscodingUrl as string | undefined

    let directUrl: string | null = null
    let directMethod: JellyfinPlayMethod | null = null
    // Progressive <video> is picky — only DirectPlay clearly browser-safe sources.
    // Remux DirectStream often still carries codecs Chrome rejects (code 4).
    if (supportsDirectPlay && isBrowserSafeSource(source)) {
      directUrl = client.mediaUrl(`Videos/${itemId}/stream.${container.split(',')[0]}`, {
        Static: 'true',
        MediaSourceId: mediaSourceId,
        PlaySessionId: playSessionId,
        DeviceId: session.deviceId,
      })
      directMethod = 'DirectPlay'
    }

    const hlsUrl = transcodingUrl ? resolvePlaybackUrl(transcodingUrl) : null

    // Prefer DirectStream only when HLS is unavailable and JF remuxed to a path.
    if (!directUrl && !hlsUrl && supportsDirectStream && directStreamUrl) {
      directUrl = resolvePlaybackUrl(directStreamUrl)
      directMethod = 'DirectStream'
    }

    return {
      itemId,
      mediaSourceId,
      playSessionId,
      directUrl,
      directMethod,
      hlsUrl,
      startPositionTicks,
      audioStreamIndex: streams.audioStreamIndex ?? null,
      subtitleStreamIndex: streams.subtitleStreamIndex ?? null,
      maxBitrate: streams.maxBitrate ?? null,
    }
  }

  async function getPlaybackPlan(
    itemId: string,
    startPositionTicks = 0,
  ): Promise<JellyfinPlaybackPlan> {
    if (mock) return mockPlaybackPlan(itemId, startPositionTicks)
    let plan = planFromPlaybackInfo(
      itemId,
      startPositionTicks,
      await fetchPlaybackInfo(itemId, startPositionTicks, {
        enableDirectPlay: true,
        enableDirectStream: true,
      }),
    )

    // If we only got an unsafe progressive URL (or nothing), force a transcode plan.
    if (!plan.hlsUrl && !plan.directUrl) {
      plan = planFromPlaybackInfo(
        itemId,
        startPositionTicks,
        await fetchPlaybackInfo(itemId, startPositionTicks, {
          enableDirectPlay: false,
          enableDirectStream: false,
        }),
      )
    }
    else if (!plan.hlsUrl && plan.directMethod === 'DirectStream') {
      // DirectStream alone is a common code-4 source in Chrome — ensure HLS exists.
      const forced = planFromPlaybackInfo(
        itemId,
        startPositionTicks,
        await fetchPlaybackInfo(itemId, startPositionTicks, {
          enableDirectPlay: false,
          enableDirectStream: false,
        }),
      )
      if (forced.hlsUrl) {
        plan = {
          ...plan,
          hlsUrl: forced.hlsUrl,
          playSessionId: forced.playSessionId || plan.playSessionId,
          mediaSourceId: forced.mediaSourceId || plan.mediaSourceId,
          directUrl: null,
          directMethod: null,
        }
      }
    }

    if (!plan.directUrl && !plan.hlsUrl) {
      throw new Error('This item has no browser-compatible playback source')
    }

    return plan
  }

  async function getHlsPlaybackPlan(
    itemId: string,
    startPositionTicks = 0,
    streams: StreamSelection = {},
  ): Promise<JellyfinPlaybackPlan> {
    if (mock) {
      throw new Error('Mock mode only supports direct playback')
    }
    const plan = planFromPlaybackInfo(
      itemId,
      startPositionTicks,
      await fetchPlaybackInfo(itemId, startPositionTicks, {
        enableDirectPlay: false,
        enableDirectStream: false,
      }, streams),
      streams,
    )
    if (!plan.hlsUrl) {
      throw new Error('Jellyfin did not provide an HLS stream')
    }
    return {
      ...plan,
      directUrl: null,
      directMethod: null,
    }
  }

  async function reportPlayback(
    path: 'Sessions/Playing' | 'Sessions/Playing/Progress' | 'Sessions/Playing/Stopped',
    plan: JellyfinPlaybackPlan,
    method: JellyfinPlayMethod,
    positionSeconds: number,
    paused: boolean,
  ) {
    if (mock) return
    await jfPost(path, {
      ItemId: plan.itemId,
      MediaSourceId: plan.mediaSourceId,
      PlaySessionId: plan.playSessionId,
      PositionTicks: secondsToTicks(positionSeconds),
      IsPaused: paused,
      CanSeek: true,
      PlayMethod: method,
    })
    // The stop report lands after the player unmounts, so refetch once the server has it.
    if (path === 'Sessions/Playing/Stopped') {
      void $queryClient.invalidateQueries({ queryKey: queryKeys.all })
    }
  }

  return {
    getPlaybackPlan,
    getHlsPlaybackPlan,
    reportStarted: (
      plan: JellyfinPlaybackPlan,
      method: JellyfinPlayMethod,
      positionSeconds: number,
    ) => reportPlayback('Sessions/Playing', plan, method, positionSeconds, false),
    reportProgress: (
      plan: JellyfinPlaybackPlan,
      method: JellyfinPlayMethod,
      positionSeconds: number,
      paused: boolean,
    ) => reportPlayback('Sessions/Playing/Progress', plan, method, positionSeconds, paused),
    reportStopped: (
      plan: JellyfinPlaybackPlan,
      method: JellyfinPlayMethod,
      positionSeconds: number,
    ) => reportPlayback('Sessions/Playing/Stopped', plan, method, positionSeconds, false),
  }
}
