<script setup lang="ts">
import Hls from 'hls.js'
import { useQuery } from '@tanstack/vue-query'
import type {
  JellyfinItem,
  JellyfinMediaStream,
  JellyfinPlayMethod,
  JellyfinPlaybackPlan,
} from '~/types/jellyfin'
import type { StreamSelection } from '~/composables/usePlayback'
import type { SkipRange } from '~/utils/media'
import { QUALITY_CAPS, SKIP_LABELS, skipRanges } from '~/utils/media'

const props = defineProps<{
  plan: JellyfinPlaybackPlan
  item: JellyfinItem
  title: string
  subtitle?: string
  episodes?: JellyfinItem[]
  nextEpisode?: JellyfinItem | null
  /** Text subtitle to show once playback starts (image subtitles come burned into `plan`). */
  initialSubtitleIndex?: number | null
}>()

const emit = defineEmits<{
  ended: []
  close: []
  next: []
  playEpisode: [episode: JellyfinItem]
  error: [message: string]
}>()

const {
  getPlaybackPlan,
  getHlsPlaybackPlan,
  reportStarted,
  reportProgress,
  reportStopped,
} = usePlayback()
const { subtitleTrackUrl, imageUrl, trickplayTileUrl, chapterImageUrl } = useJellyfin()
const { prefs } = usePlaybackPrefs()

type Panel = 'settings' | 'episodes' | 'chapters'

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 2]
/** Seconds the up-next card counts down before starting the next episode. */
const UP_NEXT_SECONDS = 10
/** Without a credits marker, the up-next card shows this long before the end. */
const UP_NEXT_LEAD_SECONDS = 30
/** Width of the seek-bar thumbnail, in CSS pixels. */
const PREVIEW_WIDTH = 224

const rootRef = ref<HTMLElement | null>(null)
const videoRef = ref<HTMLVideoElement | null>(null)
const seekRef = ref<HTMLElement | null>(null)
/** Error message shown over the video; loading uses `loading` instead. */
const status = ref('')
/** Stream is starting, switching or falling back: the play button shows a spinner. */
const loading = ref(true)
const chromeVisible = ref(true)
const playMethod = ref<JellyfinPlayMethod | null>(null)
const activePlan = ref<JellyfinPlaybackPlan>(props.plan)

const paused = ref(true)
// Seeded from the resume point and runtime so the seek bar is filled before the stream loads.
const currentTime = ref(ticksToSeconds(props.plan.startPositionTicks))
const duration = ref(ticksToSeconds(props.item.runTimeTicks ?? 0))
const bufferedEnd = ref(0)
const volume = ref(1)
const muted = ref(false)
const rate = ref(1)
const isFullscreen = ref(false)
const panel = ref<Panel | null>(null)
const hoverRatio = ref<number | null>(null)
const scrubbing = ref(false)
const switching = ref(false)

const audioIndex = ref<number | null>(null)
/** Text subtitle shown as a <track>, or null. */
const textSubtitleIndex = ref<number | null>(null)
/** Image subtitle burned in by Jellyfin, or null. */
const burnedSubtitleIndex = ref<number | null>(null)
/** Quality cap in bits/s, or null for Auto (no cap). */
const maxBitrate = ref<number | null>(null)
const subtitleTrackSrc = ref<string | null>(null)
/** Current cue text; drawn by us so it can sit above the control bar. */
const subtitleText = ref('')

let hls: Hls | null = null
let progressTimer: ReturnType<typeof setInterval> | null = null
let chromeTimer: ReturnType<typeof setTimeout> | null = null
let startedReported = false
let lastReportedSec = -1
let fallingBack = false
let ignoreMediaErrors = false
/** Set on unmount; nothing may attach or play after this. */
let disposed = false
/** Bumped by each attachSource so a slower, older attach can't take over the element. */
let attachRun = 0

/** Thrown when an attach is abandoned because the player closed or a newer source took over. */
class PlaybackCancelled extends Error {}

function rethrowIfCancelled(error: unknown) {
  if (error instanceof PlaybackCancelled) throw error
}

const startSeconds = computed(() => ticksToSeconds(activePlan.value.startPositionTicks))

const streams = computed(() => props.item.mediaStreams ?? [])
const audioStreams = computed(() => streams.value.filter(s => s.type === 'Audio'))
const subtitleStreams = computed(() => streams.value.filter(s => s.type === 'Subtitle'))
const videoStream = computed(() => streams.value.find(s => s.type === 'Video') ?? null)
const defaultAudioIndex = computed(() => defaultAudioStream(props.item)?.index ?? null)
const chapters = computed(() => (props.item.chapters ?? []).filter(ch => ch.startPositionTicks > 0))
/** Chapter stills, only present when the library has chapter image extraction turned on. */
const chapterImages = computed(() => (props.item.chapters ?? []).map((_, i) => chapterImageUrl(props.item, i)))
const hasChapterImages = computed(() => chapterImages.value.some(Boolean))

const segmentsQuery = useQuery(useJellyfinQueries().mediaSegments(props.item.id))
/** Intros, recaps, credits… from server media segments, else from chapter names. */
const skips = computed(() => skipRanges(
  segmentsQuery.data.value ?? [],
  props.item.chapters ?? [],
  ticksToSeconds(props.item.runTimeTicks ?? 0) || duration.value,
))
/** The range under the playhead (not in its last second, where a button would just flash). */
const rangeAtPlayhead = computed(() => {
  if (loading.value || scrubbing.value) return null
  return skips.value.find(r => currentTime.value >= r.start && currentTime.value < r.end - 1) ?? null
})
/** Range to offer a Skip button for. Credits before a next episode get the up-next card instead. */
const activeSkip = computed(() => {
  const range = rangeAtPlayhead.value
  if (!range || status.value || panel.value) return null
  if (range.kind === 'Outro' && props.nextEpisode) return null
  return range
})
/** "Skipped intro" after an automatic skip. */
const skipNotice = ref('')
let skipNoticeTimer: ReturnType<typeof setTimeout> | null = null
/** Ranges already skipped automatically, by start, so seeking back into one plays it. */
const autoSkipped = new Set<number>()

/** When the up-next card appears: the start of the credits, else shortly before the end. */
const upNextAt = computed(() => {
  if (!props.nextEpisode || !duration.value) return null
  const credits = skips.value.find(r => r.kind === 'Outro')
  if (credits && credits.start < duration.value - 1) return credits.start
  return Math.max(0, duration.value - UP_NEXT_LEAD_SECONDS)
})
/** Set by "Watch credits"; cleared by seeking back before the card's start. */
const upNextDismissed = ref(false)
const upNextVisible = computed(() => upNextAt.value != null
  && currentTime.value >= upNextAt.value
  && !upNextDismissed.value
  && !loading.value
  && !scrubbing.value
  && !status.value)
const upNextCountdown = ref(UP_NEXT_SECONDS)
let upNextTimer: ReturnType<typeof setInterval> | null = null
const nextEpisodeImage = computed(() => (props.nextEpisode ? imageUrl(props.nextEpisode, 'Primary', 480) : null))
const nextEpisodeLabel = computed(() => {
  const ep = props.nextEpisode
  if (!ep) return ''
  const code = ep.parentIndexNumber != null && ep.indexNumber != null
    ? `S${ep.parentIndexNumber} E${ep.indexNumber}`
    : ep.indexNumber != null ? `Episode ${ep.indexNumber}` : null
  return code ? `${code} · ${ep.name}` : ep.name
})
const mediaSourceId = computed(() => activePlan.value.mediaSourceId || props.item.mediaSourceId || props.item.id)

/** Source resolution class (1080, 720…), not raw height: cropped widescreen is often e.g. 1280×536. */
const sourceHeight = computed(() => resolutionClass(videoStream.value))

/** Quality options no taller than the source (all of them if its resolution is unknown). */
const qualityOptions = computed(() => {
  const source = sourceHeight.value
  return source ? QUALITY_CAPS.filter(q => q.height <= source) : QUALITY_CAPS
})

const methodLabel = computed(() => {
  const method = playMethod.value
  if (!method) return null
  const label = method === 'DirectPlay' ? 'Direct Play' : method === 'DirectStream' ? 'Direct Stream' : 'Transcode'
  const capped = QUALITY_CAPS.find(q => q.bitrate === maxBitrate.value)
  const source = sourceHeight.value
  const height = capped && source ? Math.min(capped.height, source) : capped?.height ?? source
  return height ? `${label} · ${resolutionLabel(height)}` : label
})

const chromeShown = computed(() => chromeVisible.value || paused.value || panel.value !== null || loading.value || Boolean(status.value))
const playedRatio = computed(() => (duration.value ? Math.min(1, currentTime.value / duration.value) : 0))
const bufferedRatio = computed(() => (duration.value ? Math.min(1, bufferedEnd.value / duration.value) : 0))
const hoverTime = computed(() => (hoverRatio.value != null ? hoverRatio.value * duration.value : null))
const hoverChapter = computed(() => {
  if (hoverTime.value == null) return null
  let match: string | null = null
  for (const ch of chapters.value) {
    if (ticksToSeconds(ch.startPositionTicks) <= hoverTime.value) match = ch.name
  }
  return match
})

/** The trickplay frame under the pointer: one cell of a sprite sheet, scaled to PREVIEW_WIDTH. */
const hoverPreview = computed(() => {
  const info = props.item.trickplay
  if (!info || hoverTime.value == null) return null
  const frame = Math.min(info.thumbnailCount - 1, Math.max(0, Math.floor((hoverTime.value * 1000) / info.interval)))
  const perTile = info.tileWidth * info.tileHeight
  const cell = frame % perTile
  const url = trickplayTileUrl(props.item, info.width, Math.floor(frame / perTile))
  if (!url) return null
  const scale = PREVIEW_WIDTH / info.width
  const height = Math.round(info.height * scale)
  return {
    height,
    style: {
      backgroundImage: `url("${url}")`,
      // Width only: the last sheet can have fewer rows, so its height must follow its aspect.
      backgroundSize: `${info.tileWidth * PREVIEW_WIDTH}px auto`,
      backgroundPosition: `-${(cell % info.tileWidth) * PREVIEW_WIDTH}px -${Math.floor(cell / info.tileWidth) * height}px`,
    },
  }
})

function formatTime(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) seconds = 0
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const ss = String(s).padStart(2, '0')
  return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`
}

function clearProgressTimer() {
  if (progressTimer) {
    clearInterval(progressTimer)
    progressTimer = null
  }
}

function clearChromeTimer() {
  if (chromeTimer) {
    clearTimeout(chromeTimer)
    chromeTimer = null
  }
}

function showChrome() {
  chromeVisible.value = true
  clearChromeTimer()
  const video = videoRef.value
  if (video && !video.paused && !loading.value && !status.value) {
    chromeTimer = setTimeout(() => {
      chromeVisible.value = false
    }, 1800)
  }
}

function onPointerActivity() {
  showChrome()
}

async function safeReport(
  kind: 'started' | 'progress' | 'stopped',
  position: number,
  isPaused = false,
) {
  const method = playMethod.value
  if (!method) return
  try {
    if (kind === 'started') {
      await reportStarted(activePlan.value, method, position)
      startedReported = true
    }
    else if (kind === 'progress') {
      await reportProgress(activePlan.value, method, position, isPaused)
    }
    else {
      await reportStopped(activePlan.value, method, position)
    }
    lastReportedSec = position
  }
  catch {
    // Best-effort
  }
}

function destroyHls() {
  if (hls) {
    hls.destroy()
    hls = null
  }
}

function waitForVideo(video: HTMLVideoElement, timeoutMs = 25_000): Promise<void> {
  if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
    return Promise.resolve()
  }
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup()
      reject(new Error('Timed out loading media'))
    }, timeoutMs)

    const onReady = () => {
      cleanup()
      resolve()
    }
    const onError = () => {
      cleanup()
      const mediaError = video.error
      const detail = mediaError
        ? `code ${mediaError.code}`
        : 'unknown error'
      reject(new Error(`Media failed to load (${detail})`))
    }
    const cleanup = () => {
      clearTimeout(timer)
      video.removeEventListener('loadeddata', onReady)
      video.removeEventListener('canplay', onReady)
      video.removeEventListener('error', onError)
    }

    video.addEventListener('loadeddata', onReady, { once: true })
    video.addEventListener('canplay', onReady, { once: true })
    video.addEventListener('error', onError, { once: true })
  })
}

async function resetVideoElement(video: HTMLVideoElement) {
  ignoreMediaErrors = true
  destroyHls()
  video.pause()
  video.removeAttribute('src')
  video.load()
  // Empty load() often emits MEDIA_ERR_SRC_NOT_SUPPORTED (code 4); ignore it.
  await new Promise<void>(resolve => {
    requestAnimationFrame(() => resolve())
  })
  ignoreMediaErrors = false
}

async function attachSource(url: string, method: JellyfinPlayMethod, isHls: boolean) {
  const video = videoRef.value
  if (!video) throw new Error('Video element missing')
  if (disposed) throw new PlaybackCancelled()
  const run = ++attachRun
  const ensureCurrent = () => {
    if (disposed || run !== attachRun) throw new PlaybackCancelled()
  }

  playMethod.value = method
  startedReported = false
  await resetVideoElement(video)
  ensureCurrent()

  if (isHls) {
    const canNative = Boolean(video.canPlayType('application/vnd.apple.mpegurl'))
    if (canNative) {
      video.src = url
      await waitForVideo(video)
    }
    else if (Hls.isSupported()) {
      const instance = new Hls({
        enableWorker: true,
        maxBufferLength: 30,
        xhrSetup(xhr) {
          xhr.withCredentials = false
        },
      })
      hls = instance
      await new Promise<void>((resolve, reject) => {
        const onError = (_event: unknown, data: {
          fatal?: boolean
          type?: string
          details?: string
        }) => {
          if (!data.fatal) return
          if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
            instance.startLoad()
            return
          }
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
            instance.recoverMediaError()
            return
          }
          cleanup()
          reject(new Error(`HLS error: ${data.type ?? 'fatal'}${data.details ? ` (${data.details})` : ''}`))
        }
        const onReady = () => {
          cleanup()
          resolve()
        }
        const onDestroying = () => {
          cleanup()
          reject(new PlaybackCancelled())
        }
        const cleanup = () => {
          instance.off(Hls.Events.MANIFEST_PARSED, onReady)
          instance.off(Hls.Events.ERROR, onError)
          instance.off(Hls.Events.DESTROYING, onDestroying)
        }
        instance.on(Hls.Events.MANIFEST_PARSED, onReady)
        instance.on(Hls.Events.ERROR, onError)
        instance.on(Hls.Events.DESTROYING, onDestroying)
        instance.loadSource(url)
        instance.attachMedia(video)
      })
    }
    else {
      throw new Error('HLS is not supported in this browser')
    }
  }
  else {
    video.src = url
    await waitForVideo(video)
  }
  ensureCurrent()

  if (startSeconds.value > 0 && Number.isFinite(startSeconds.value)) {
    try {
      video.currentTime = startSeconds.value
    }
    catch { /* ignore */ }
  }

  video.playbackRate = rate.value
  try {
    await video.play()
  }
  catch {
    // Autoplay may be blocked; the centre play button lets the user start.
  }
  ensureCurrent()
}

async function tryDirect(plan: JellyfinPlaybackPlan) {
  if (!plan.directUrl || !plan.directMethod) throw new Error('No direct stream')
  await attachSource(plan.directUrl, plan.directMethod, false)
}

async function tryHls(plan: JellyfinPlaybackPlan) {
  if (!plan.hlsUrl) throw new Error('No HLS stream')
  await attachSource(plan.hlsUrl, 'Transcode', true)
}

function currentSelection(): StreamSelection {
  return {
    audioStreamIndex: audioIndex.value,
    subtitleStreamIndex: burnedSubtitleIndex.value,
    maxBitrate: maxBitrate.value,
  }
}

async function fallbackToForcedHls() {
  if (fallingBack) throw new Error('HLS fallback already in progress')
  fallingBack = true
  loading.value = true
  showChrome()
  try {
    const forced = await getHlsPlaybackPlan(
      activePlan.value.itemId,
      activePlan.value.startPositionTicks,
      currentSelection(),
    )
    if (disposed) throw new PlaybackCancelled()
    activePlan.value = forced
    await tryHls(forced)
  }
  finally {
    // Keep fallingBack true after success so late direct errors don't re-enter.
  }
}

async function startPlan(plan: JellyfinPlaybackPlan) {
  // Prefer HLS when available — progressive DirectStream/DirectPlay is the usual code-4 path.
  if (plan.hlsUrl && !plan.directUrl) {
    await tryHls(plan)
  }
  else if (plan.directUrl && plan.directMethod === 'DirectPlay') {
    try {
      await tryDirect(plan)
    }
    catch (error) {
      rethrowIfCancelled(error)
      loading.value = true
      showChrome()
      if (plan.hlsUrl) {
        try {
          await tryHls(plan)
        }
        catch (error) {
          rethrowIfCancelled(error)
          await fallbackToForcedHls()
        }
      }
      else {
        await fallbackToForcedHls()
      }
    }
  }
  else if (plan.hlsUrl) {
    await tryHls(plan)
  }
  else if (plan.directUrl) {
    try {
      await tryDirect(plan)
    }
    catch (error) {
      rethrowIfCancelled(error)
      await fallbackToForcedHls()
    }
  }
  else {
    await fallbackToForcedHls()
  }
}

async function boot() {
  await nextTick()
  const video = videoRef.value
  if (!video) {
    emit('error', 'Video element missing')
    return
  }

  loading.value = true
  status.value = ''
  showChrome()
  activePlan.value = props.plan
  fallingBack = false
  audioIndex.value = props.plan.audioStreamIndex ?? defaultAudioIndex.value
  burnedSubtitleIndex.value = props.plan.subtitleStreamIndex ?? null
  maxBitrate.value = props.plan.maxBitrate ?? null

  try {
    await startPlan(props.plan)
    loading.value = false
    status.value = ''
    showChrome()
    const initialText = subtitleStreams.value.find(s => s.index === props.initialSubtitleIndex && s.isTextSubtitle)
    if (initialText && burnedSubtitleIndex.value == null) {
      textSubtitleIndex.value = initialText.index
      await setTextTrack(initialText.index)
    }
  }
  catch (error) {
    if (error instanceof PlaybackCancelled) return
    loading.value = false
    status.value = error instanceof Error ? error.message : 'Playback failed'
    emit('error', status.value)
    chromeVisible.value = true
  }
}

/**
 * Re-request the stream from the current position with a new audio track or
 * burned-in subtitle. Non-default audio and image subtitles need Jellyfin to
 * transcode; returning to defaults goes back to the normal (direct) plan.
 */
async function restartWithSelection() {
  const video = videoRef.value
  if (!video) return
  switching.value = true
  loading.value = true
  status.value = ''
  const position = video.currentTime
  if (startedReported) await safeReport('stopped', position)
  clearProgressTimer()
  const selection = currentSelection()
  const needsTranscode = selection.subtitleStreamIndex != null
    || selection.maxBitrate != null
    || (selection.audioStreamIndex != null && selection.audioStreamIndex !== defaultAudioIndex.value)
  try {
    const ticks = secondsToTicks(position)
    const plan = needsTranscode
      ? await getHlsPlaybackPlan(props.item.id, ticks, selection)
      : await getPlaybackPlan(props.item.id, ticks)
    if (disposed) return
    activePlan.value = plan
    fallingBack = false
    await startPlan(plan)
    loading.value = false
    status.value = ''
    showChrome()
  }
  catch (error) {
    if (error instanceof PlaybackCancelled) return
    loading.value = false
    status.value = error instanceof Error ? error.message : 'Could not switch tracks'
    emit('error', status.value)
  }
  finally {
    switching.value = false
  }
}

async function selectQuality(bitrate: number | null) {
  if (maxBitrate.value === bitrate || switching.value) return
  maxBitrate.value = bitrate
  await restartWithSelection()
}

async function selectAudio(index: number) {
  if (audioIndex.value === index || switching.value) return
  audioIndex.value = index
  await restartWithSelection()
}

async function selectSubtitle(stream: JellyfinMediaStream | null) {
  if (switching.value) return
  const wasBurned = burnedSubtitleIndex.value
  if (!stream) {
    textSubtitleIndex.value = null
    burnedSubtitleIndex.value = null
    setTextTrack(null)
    if (wasBurned != null) await restartWithSelection()
    return
  }
  if (stream.isTextSubtitle) {
    burnedSubtitleIndex.value = null
    textSubtitleIndex.value = stream.index
    await setTextTrack(stream.index)
    if (wasBurned != null) await restartWithSelection()
    return
  }
  textSubtitleIndex.value = null
  setTextTrack(null)
  if (wasBurned === stream.index) return
  burnedSubtitleIndex.value = stream.index
  await restartWithSelection()
}

/** Loads a text subtitle as WebVTT into a same-origin blob <track>. */
async function setTextTrack(index: number | null) {
  if (subtitleTrackSrc.value) URL.revokeObjectURL(subtitleTrackSrc.value)
  subtitleTrackSrc.value = null
  subtitleText.value = ''
  if (index == null) return
  const url = subtitleTrackUrl(props.item.id, mediaSourceId.value, index)
  if (!url) return
  try {
    const response = await fetch(url)
    if (!response.ok) throw new Error(`Subtitle ${response.status}`)
    const blob = new Blob([await response.text()], { type: 'text/vtt' })
    if (textSubtitleIndex.value !== index) return
    subtitleTrackSrc.value = URL.createObjectURL(blob)
    await nextTick()
    const track = videoRef.value?.textTracks[0]
    if (track) {
      // Hidden still fires cuechange; we render the text ourselves.
      track.mode = 'hidden'
      track.oncuechange = () => {
        const cues = track.activeCues
        subtitleText.value = cues
          ? [...cues].map(cue => (cue as VTTCue).text.replace(/<[^>]+>/g, '')).join('\n')
          : ''
      }
    }
  }
  catch {
    textSubtitleIndex.value = null
    status.value = ''
  }
}

function onLoadedMetadata() {
  const video = videoRef.value
  if (!video) return
  duration.value = Number.isFinite(video.duration) ? video.duration : ticksToSeconds(props.item.runTimeTicks ?? 0)
  if (startSeconds.value > 0 && Number.isFinite(startSeconds.value) && video.currentTime < 1) {
    try {
      video.currentTime = startSeconds.value
    }
    catch { /* ignore */ }
  }
}

function onTimeUpdate() {
  const video = videoRef.value
  // While a source attaches the element reports 0 until the resume seek lands.
  if (!video || scrubbing.value || loading.value) return
  currentTime.value = video.currentTime
  if (Number.isFinite(video.duration) && video.duration > 0) duration.value = video.duration
}

function onProgress() {
  const video = videoRef.value
  if (!video || !video.buffered.length) return
  bufferedEnd.value = video.buffered.end(video.buffered.length - 1)
}

function onVolumeChange() {
  const video = videoRef.value
  if (!video) return
  volume.value = video.volume
  muted.value = video.muted
}

async function onPlaying() {
  const video = videoRef.value
  if (!video) return
  paused.value = false
  if (!startedReported) {
    await safeReport('started', video.currentTime || startSeconds.value)
  }
  clearProgressTimer()
  progressTimer = setInterval(() => {
    const el = videoRef.value
    if (!el || el.paused) return
    void safeReport('progress', el.currentTime, false)
  }, 10_000)
  showChrome()
}

async function onPause() {
  paused.value = true
  const video = videoRef.value
  if (!video || !startedReported) return
  clearProgressTimer()
  await safeReport('progress', video.currentTime, true)
  chromeVisible.value = true
  clearChromeTimer()
}

async function onSeeked() {
  const video = videoRef.value
  if (!video || !startedReported) return
  await safeReport('progress', video.currentTime, video.paused)
}

async function onEnded() {
  const video = videoRef.value
  clearProgressTimer()
  if (video && startedReported) await safeReport('stopped', video.currentTime)
  if (props.nextEpisode && prefs.value.autoplayNext) emit('next')
  else emit('ended')
}

async function onVideoError() {
  if (disposed || ignoreMediaErrors || fallingBack || switching.value) return
  if (playMethod.value === 'Transcode') {
    if (!status.value) {
      loading.value = false
      status.value = 'Media failed to load'
      emit('error', status.value)
    }
    return
  }
  try {
    await fallbackToForcedHls()
    loading.value = false
    status.value = ''
    showChrome()
  }
  catch (error) {
    if (error instanceof PlaybackCancelled) return
    loading.value = false
    status.value = error instanceof Error ? error.message : 'Playback failed'
    emit('error', status.value)
    chromeVisible.value = true
  }
}

function togglePlay() {
  const video = videoRef.value
  if (!video) return
  if (video.paused) void video.play()
  else video.pause()
  showChrome()
}

function skip(seconds: number) {
  const video = videoRef.value
  if (!video) return
  const end = video.duration || duration.value || video.currentTime
  video.currentTime = Math.min(Math.max(0, video.currentTime + seconds), end)
  currentTime.value = video.currentTime
  showChrome()
}

function seekToRatio(ratio: number) {
  const video = videoRef.value
  if (!video || !duration.value) return
  const target = Math.min(Math.max(0, ratio), 1) * duration.value
  video.currentTime = target
  currentTime.value = target
}

function skipPast(range: SkipRange) {
  const video = videoRef.value
  if (!video) return
  video.currentTime = range.end
  currentTime.value = range.end
  showChrome()
}

watch(rangeAtPlayhead, (range) => {
  if (!range || !prefs.value.autoSkipIntros || autoSkipped.has(range.start)) return
  if (range.kind !== 'Intro' && range.kind !== 'Recap') return
  autoSkipped.add(range.start)
  skipPast(range)
  skipNotice.value = `Skipped ${range.kind.toLowerCase()}`
  if (skipNoticeTimer) clearTimeout(skipNoticeTimer)
  skipNoticeTimer = setTimeout(() => {
    skipNotice.value = ''
  }, 2500)
})

function clearUpNextTimer() {
  if (upNextTimer) {
    clearInterval(upNextTimer)
    upNextTimer = null
  }
}

// The countdown holds while paused and restarts each time the card reappears.
watch(upNextVisible, (visible) => {
  clearUpNextTimer()
  upNextCountdown.value = UP_NEXT_SECONDS
  if (!visible || !prefs.value.autoplayNext) return
  upNextTimer = setInterval(() => {
    if (paused.value) return
    upNextCountdown.value -= 1
    if (upNextCountdown.value <= 0) {
      clearUpNextTimer()
      emit('next')
    }
  }, 1000)
})

watch(currentTime, (time) => {
  if (upNextDismissed.value && upNextAt.value != null && time < upNextAt.value - 1) upNextDismissed.value = false
})

function dismissUpNext() {
  upNextDismissed.value = true
  showChrome()
}

function seekToTicks(ticks: number) {
  const video = videoRef.value
  if (!video) return
  video.currentTime = ticksToSeconds(ticks)
  currentTime.value = video.currentTime
  panel.value = null
}

function ratioFromEvent(event: PointerEvent) {
  const el = seekRef.value
  if (!el) return 0
  const rect = el.getBoundingClientRect()
  return Math.min(Math.max(0, (event.clientX - rect.left) / rect.width), 1)
}

function onSeekPointerDown(event: PointerEvent) {
  scrubbing.value = true
  ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
  const ratio = ratioFromEvent(event)
  hoverRatio.value = ratio
  currentTime.value = ratio * duration.value
}

function onSeekPointerMove(event: PointerEvent) {
  const ratio = ratioFromEvent(event)
  hoverRatio.value = ratio
  if (scrubbing.value) currentTime.value = ratio * duration.value
  showChrome()
}

function onSeekPointerUp(event: PointerEvent) {
  if (!scrubbing.value) return
  scrubbing.value = false
  seekToRatio(ratioFromEvent(event))
}

function onSeekKeydown(event: KeyboardEvent) {
  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    event.preventDefault()
    event.stopPropagation()
    skip(event.key === 'ArrowLeft' ? -10 : 10)
  }
}

function toggleMute() {
  const video = videoRef.value
  if (!video) return
  video.muted = !video.muted
  if (!video.muted && video.volume === 0) video.volume = 0.5
}

function onVolumeInput(event: Event) {
  const video = videoRef.value
  if (!video) return
  const value = Number((event.target as HTMLInputElement).value)
  video.volume = value
  video.muted = value === 0
}

function setRate(value: number) {
  rate.value = value
  if (videoRef.value) videoRef.value.playbackRate = value
}

const sidePanelRef = ref<HTMLElement | null>(null)
const panelTitle = computed(() => (panel.value === 'settings' ? 'Settings' : panel.value === 'chapters' ? 'Chapters' : 'Episodes'))

/** Index (in item.chapters) of the chapter playing now. */
const currentChapterIndex = computed(() => {
  const list = props.item.chapters ?? []
  let current = -1
  list.forEach((ch, i) => {
    if (ticksToSeconds(ch.startPositionTicks) <= currentTime.value + 0.5) current = i
  })
  return current
})
const bottomBarRef = ref<HTMLElement | null>(null)
/** Distance from the bottom bar's top edge to the bottom of the player, so side panels stop above it. */
const barClearance = ref(160)
let barObserver: ResizeObserver | null = null

function measureBar() {
  const bar = bottomBarRef.value
  const root = rootRef.value
  if (!bar || !root || !bar.offsetHeight) return
  barClearance.value = root.clientHeight - bar.offsetTop
}

function togglePanel(name: Panel) {
  panel.value = panel.value === name ? null : name
  showChrome()
  if (panel.value === 'episodes' || panel.value === 'chapters') {
    void nextTick(() => {
      sidePanelRef.value?.querySelector('[aria-current="true"]')?.scrollIntoView({ block: 'center' })
    })
  }
}

async function togglePictureInPicture() {
  const video = videoRef.value
  if (!video) return
  try {
    if (document.pictureInPictureElement) await document.exitPictureInPicture()
    else await video.requestPictureInPicture()
  }
  catch { /* unsupported */ }
}

function toggleFullscreen() {
  if (document.fullscreenElement) void document.exitFullscreen()
  else void rootRef.value?.requestFullscreen?.()
}

function onFullscreenChange() {
  isFullscreen.value = Boolean(document.fullscreenElement)
}

function onClose() {
  emit('close')
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.preventDefault()
    if (panel.value) {
      panel.value = null
      return
    }
    if (document.fullscreenElement) return
    onClose()
    return
  }
  const target = event.target as HTMLElement | null
  if (target?.tagName === 'INPUT') return
  showChrome()
  const video = videoRef.value
  if (!video) return
  if (event.key === ' ' || event.key === 'k') {
    if (target?.tagName === 'BUTTON' && event.key === ' ') return
    event.preventDefault()
    togglePlay()
  }
  else if (event.key === 'ArrowLeft') {
    event.preventDefault()
    skip(-10)
  }
  else if (event.key === 'ArrowRight') {
    event.preventDefault()
    skip(10)
  }
  else if (event.key === 'f') {
    event.preventDefault()
    toggleFullscreen()
  }
  else if (event.key === 'm') {
    event.preventDefault()
    toggleMute()
  }
}

async function onBeforeUnload() {
  const video = videoRef.value
  if (video && startedReported) await safeReport('stopped', video.currentTime)
}

onMounted(() => {
  void boot()
  window.addEventListener('pagehide', onBeforeUnload)
  window.addEventListener('keydown', onKeydown)
  document.addEventListener('fullscreenchange', onFullscreenChange)
  showChrome()
  barObserver = new ResizeObserver(measureBar)
  if (bottomBarRef.value) barObserver.observe(bottomBarRef.value)
  if (rootRef.value) barObserver.observe(rootRef.value)
})

onBeforeUnmount(() => {
  disposed = true
  attachRun++
  clearProgressTimer()
  clearChromeTimer()
  clearUpNextTimer()
  if (skipNoticeTimer) clearTimeout(skipNoticeTimer)
  const video = videoRef.value
  if (video && startedReported && Math.abs(video.currentTime - lastReportedSec) > 1) {
    void safeReport('stopped', video.currentTime)
  }
  barObserver?.disconnect()
  destroyHls()
  if (video) {
    // A detached <video> can keep playing audio, so stop it and drop the source.
    video.pause()
    video.removeAttribute('src')
    video.load()
  }
  if (subtitleTrackSrc.value) URL.revokeObjectURL(subtitleTrackSrc.value)
  window.removeEventListener('pagehide', onBeforeUnload)
  window.removeEventListener('keydown', onKeydown)
  document.removeEventListener('fullscreenchange', onFullscreenChange)
})
</script>

<template>
  <div
    ref="rootRef"
    class="fixed inset-0 z-50 overflow-hidden bg-black text-ink"
    :class="chromeShown ? 'cursor-default' : 'cursor-none'"
    @mousemove="onPointerActivity"
    @pointerdown="onPointerActivity"
  >
    <video
      ref="videoRef"
      class="absolute inset-0 size-full bg-black object-contain"
      playsinline
      preload="auto"
      @click="togglePlay"
      @dblclick="toggleFullscreen"
      @loadedmetadata="onLoadedMetadata"
      @durationchange="onLoadedMetadata"
      @timeupdate="onTimeUpdate"
      @progress="onProgress"
      @volumechange="onVolumeChange"
      @playing="onPlaying"
      @pause="onPause"
      @seeked="onSeeked"
      @ended="onEnded"
      @error="onVideoError"
    >
      <track
        v-if="subtitleTrackSrc"
        :key="subtitleTrackSrc"
        kind="subtitles"
        :src="subtitleTrackSrc"
        default
      >
    </video>

    <div
      v-if="subtitleText"
      aria-live="off"
      class="pointer-events-none absolute inset-x-4 flex justify-center transition-[bottom] duration-300"
      :class="chromeShown ? 'bottom-[17rem] sm:bottom-40' : 'bottom-10'"
    >
      <p class="max-w-[min(90%,52rem)] whitespace-pre-line rounded-lg bg-black/65 px-3 py-1 text-center text-[clamp(1rem,2.4vw,1.75rem)] font-bold leading-snug text-white">
        {{ subtitleText }}
      </p>
    </div>

    <Transition
      enter-active-class="transition-opacity duration-300"
      leave-active-class="transition-opacity duration-300"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <div v-show="chromeShown" class="pointer-events-none absolute inset-0">
        <div class="absolute inset-x-0 top-0 h-40 bg-gradient-to-b from-black/70 to-transparent" />
        <div class="absolute inset-x-0 bottom-0 h-64 bg-gradient-to-t from-black/80 to-transparent" />

        <!-- Top row -->
        <div class="pointer-events-auto absolute inset-x-4 top-4 flex items-center gap-3 sm:inset-x-8 sm:top-6">
          <button type="button" class="glass grid size-12 place-items-center rounded-full" aria-label="Close player" @click="onClose">
            <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
          <span
            v-if="methodLabel"
            class="glass ml-auto inline-flex h-9 items-center gap-2 rounded-full px-3.5 text-[13px] font-bold text-ink-2"
          >
            <span class="size-[7px] rounded-full" :class="playMethod === 'Transcode' ? 'bg-accent' : 'bg-ok'" />
            {{ methodLabel }}
          </span>
          <button
            type="button"
            class="glass grid size-12 place-items-center rounded-full"
            :class="methodLabel ? '' : 'ml-auto'"
            aria-label="Picture in picture"
            @click="togglePictureInPicture"
          >
            <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2" /><rect x="12" y="12" width="7" height="5" rx="1" fill="currentColor" /></svg>
          </button>
        </div>

        <!-- Centre transport -->
        <div class="pointer-events-auto absolute left-1/2 top-1/2 flex -translate-x-1/2 -translate-y-1/2 items-center gap-8 sm:gap-12">
          <button type="button" class="grid size-16 place-items-center rounded-full transition duration-150 hover:scale-110 hover:bg-white/10 active:scale-95" aria-label="Back 10 seconds" @click="skip(-10)">
            <svg class="size-10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 12a8 8 0 1 0 2.3-5.7" /><path d="M4 4v4h4" /><text x="12" y="15.5" font-size="7" text-anchor="middle" fill="currentColor" stroke="none" font-weight="800">10</text></svg>
          </button>
          <button
            type="button"
            class="glass grid size-[92px] place-items-center rounded-full transition duration-150 enabled:hover:scale-105 enabled:hover:bg-white/15 enabled:active:scale-95"
            :aria-label="loading ? 'Loading' : paused ? 'Play' : 'Pause'"
            :aria-busy="loading"
            :disabled="loading"
            @click="togglePlay"
          >
            <svg v-if="loading" class="size-11 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="12" cy="12" r="9.5" stroke="currentColor" stroke-opacity="0.2" stroke-width="2.4" /><path d="M21.5 12A9.5 9.5 0 0 0 12 2.5" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" /></svg>
            <svg v-else-if="paused" class="ml-1 size-10" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
            <svg v-else class="size-10" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="4.5" width="4" height="15" rx="1.2" /><rect x="14" y="4.5" width="4" height="15" rx="1.2" /></svg>
          </button>
          <button type="button" class="grid size-16 place-items-center rounded-full transition duration-150 hover:scale-110 hover:bg-white/10 active:scale-95" aria-label="Forward 10 seconds" @click="skip(10)">
            <svg class="size-10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.3-5.7" /><path d="M20 4v4h-4" /><text x="12" y="15.5" font-size="7" text-anchor="middle" fill="currentColor" stroke="none" font-weight="800">10</text></svg>
          </button>
        </div>

        <!-- Panels -->
        <!-- Side panel: settings, chapters or episodes, filling the space between the top row and the bar -->
        <section
          v-if="panel === 'settings' || panel === 'chapters' || (panel === 'episodes' && episodes?.length)"
          :aria-label="panelTitle"
          class="glass-strong pointer-events-auto absolute right-4 top-20 flex w-[min(440px,calc(100%-2rem))] flex-col overflow-hidden rounded-[22px] sm:right-8 sm:top-[5.5rem]"
          :style="{ bottom: `${barClearance + 16}px` }"
        >
          <div class="flex items-center justify-between gap-3 px-5 pb-3 pt-4">
            <h2 class="text-xl font-extrabold tracking-[-0.5px]">
              {{ panelTitle }}
            </h2>
            <button
              type="button"
              class="grid size-10 place-items-center rounded-full bg-white/10 hover:bg-white/15"
              :aria-label="`Close ${panelTitle.toLowerCase()}`"
              @click="panel = null"
            >
              <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
            </button>
          </div>
          <div ref="sidePanelRef" class="flex min-h-0 flex-1 flex-col gap-1 scrollbar-subtle overflow-y-auto px-3 pb-3">
            <template v-if="panel === 'settings'">
              <div class="flex flex-col gap-2 px-2 pb-4 pt-1">
                <h3 class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
                  Playback speed
                </h3>
                <div class="flex flex-wrap gap-1.5">
                  <button
                    v-for="value in SPEEDS"
                    :key="value"
                    type="button"
                    class="h-9 rounded-full px-3.5 text-sm font-bold transition"
                    :class="rate === value ? 'bg-ink text-canvas' : 'bg-white/10 hover:bg-white/15'"
                    :aria-pressed="rate === value"
                    @click="setRate(value)"
                  >
                    {{ value === 1 ? 'Normal' : `${value}×` }}
                  </button>
                </div>
              </div>

              <div class="flex flex-col border-t border-white/10 pb-3 pt-4">
                <h3 class="mx-2 mb-1.5 text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
                  Subtitles
                </h3>
                <button
                  type="button"
                  class="flex min-h-11 items-center gap-2.5 rounded-[10px] px-2.5 text-left text-[15px] font-semibold disabled:opacity-50"
                  :class="textSubtitleIndex == null && burnedSubtitleIndex == null ? 'bg-white/10' : 'hover:bg-white/5'"
                  :aria-pressed="textSubtitleIndex == null && burnedSubtitleIndex == null"
                  :disabled="switching"
                  @click="selectSubtitle(null)"
                >
                  <span class="w-4 font-extrabold">{{ textSubtitleIndex == null && burnedSubtitleIndex == null ? '✓' : '' }}</span>
                  Off
                </button>
                <button
                  v-for="stream in subtitleStreams"
                  :key="stream.index"
                  type="button"
                  class="flex min-h-11 items-center gap-2.5 rounded-[10px] px-2.5 text-left text-[15px] font-semibold disabled:opacity-50"
                  :class="textSubtitleIndex === stream.index || burnedSubtitleIndex === stream.index ? 'bg-white/10' : 'hover:bg-white/5'"
                  :aria-pressed="textSubtitleIndex === stream.index || burnedSubtitleIndex === stream.index"
                  :disabled="switching"
                  @click="selectSubtitle(stream)"
                >
                  <span class="w-4 font-extrabold">{{ textSubtitleIndex === stream.index || burnedSubtitleIndex === stream.index ? '✓' : '' }}</span>
                  <span class="min-w-0 flex-1 truncate">{{ streamLabel(stream) }}</span>
                  <span v-if="!stream.isTextSubtitle" class="text-xs font-bold text-muted">burn-in</span>
                </button>
              </div>

              <div class="flex flex-col border-t border-white/10 pb-3 pt-4">
                <h3 class="mx-2 mb-1.5 text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
                  Audio
                </h3>
                <p v-if="!audioStreams.length" class="mx-2 text-sm text-muted">
                  Default track
                </p>
                <button
                  v-for="stream in audioStreams"
                  :key="stream.index"
                  type="button"
                  class="flex min-h-11 items-center gap-2.5 rounded-[10px] px-2.5 text-left text-[15px] font-semibold disabled:opacity-50"
                  :class="audioIndex === stream.index ? 'bg-white/10' : 'hover:bg-white/5'"
                  :aria-pressed="audioIndex === stream.index"
                  :disabled="switching"
                  @click="selectAudio(stream.index)"
                >
                  <span class="w-4 font-extrabold">{{ audioIndex === stream.index ? '✓' : '' }}</span>
                  <span class="min-w-0 flex-1 truncate">{{ streamLabel(stream) }}</span>
                </button>
              </div>

              <div class="flex flex-col border-t border-white/10 pb-3 pt-4">
                <h3 class="mx-2 mb-1.5 text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
                  Quality
                </h3>
                <button
                  type="button"
                  class="flex min-h-11 items-center gap-2.5 rounded-[10px] px-2.5 text-left text-[15px] font-semibold disabled:opacity-50"
                  :class="maxBitrate == null ? 'bg-white/10' : 'hover:bg-white/5'"
                  :aria-pressed="maxBitrate == null"
                  :disabled="switching"
                  @click="selectQuality(null)"
                >
                  <span class="w-4 font-extrabold">{{ maxBitrate == null ? '✓' : '' }}</span>
                  <span class="flex-1">Auto</span>
                  <span class="text-xs font-bold text-muted">Best available</span>
                </button>
                <button
                  v-for="q in qualityOptions"
                  :key="q.bitrate"
                  type="button"
                  class="flex min-h-11 items-center gap-2.5 rounded-[10px] px-2.5 text-left text-[15px] font-semibold disabled:opacity-50"
                  :class="maxBitrate === q.bitrate ? 'bg-white/10' : 'hover:bg-white/5'"
                  :aria-pressed="maxBitrate === q.bitrate"
                  :disabled="switching"
                  @click="selectQuality(q.bitrate)"
                >
                  <span class="w-4 font-extrabold">{{ maxBitrate === q.bitrate ? '✓' : '' }}</span>
                  <span class="flex-1">{{ q.label }}</span>
                  <span class="text-xs font-bold text-muted">{{ q.detail }}</span>
                </button>
              </div>

              <p class="mx-2 border-t border-white/10 pt-3 text-[13px] leading-snug text-muted">
                Other audio tracks, burn-in subtitles and a quality cap switch playback to transcoding.
              </p>
            </template>
            <template v-else-if="panel === 'chapters'">
              <button
                v-for="(ch, i) in item.chapters"
                :key="ch.startPositionTicks"
                type="button"
                class="flex items-center gap-3 rounded-[12px] px-3 py-2.5 text-left"
                :class="i === currentChapterIndex ? 'bg-white/10' : 'hover:bg-white/5'"
                :aria-current="i === currentChapterIndex ? 'true' : undefined"
                @click="seekToTicks(ch.startPositionTicks)"
              >
                <span
                  v-if="hasChapterImages"
                  class="aspect-video w-28 shrink-0 overflow-hidden rounded-[8px] bg-white/5"
                >
                  <img
                    v-if="chapterImages[i]"
                    :src="chapterImages[i]!"
                    alt=""
                    loading="lazy"
                    class="size-full object-cover"
                  >
                </span>
                <span class="flex min-w-0 flex-col gap-0.5">
                  <span class="text-xs font-bold uppercase tracking-[0.4px] text-muted">
                    Chapter {{ i + 1 }} · {{ formatTime(ticksToSeconds(ch.startPositionTicks)) }}
                  </span>
                  <span class="truncate text-[15px] font-extrabold">{{ ch.name || `Chapter ${i + 1}` }}</span>
                </span>
              </button>
            </template>
            <button
              v-for="ep in (panel === 'episodes' ? episodes : [])"
              :key="ep.id"
              type="button"
              class="flex flex-col gap-0.5 rounded-[12px] px-3 py-2.5 text-left"
              :class="ep.id === item.id ? 'bg-white/10' : 'hover:bg-white/5'"
              :aria-current="ep.id === item.id ? 'true' : undefined"
              @click="emit('playEpisode', ep)"
            >
              <span class="text-xs font-bold uppercase tracking-[0.4px] text-muted">Episode {{ ep.indexNumber }}</span>
              <span class="truncate text-[15px] font-extrabold">{{ ep.name }}</span>
            </button>
          </div>
        </section>

        <!-- Bottom bar -->
        <div ref="bottomBarRef" class="glass-strong pointer-events-auto absolute inset-x-4 bottom-4 flex flex-col gap-3.5 rounded-[22px] px-5 py-4 sm:inset-x-8 sm:bottom-7">
          <div class="flex flex-wrap items-center gap-4">
            <div class="flex min-w-0 flex-col gap-0.5">
              <NuxtLink
                v-if="subtitle"
                :to="`/item/${item.id}`"
                class="truncate text-[13px] font-bold text-muted transition hover:text-ink hover:underline hover:underline-offset-2"
              >
                {{ subtitle }}
              </NuxtLink>
              <NuxtLink
                :to="`/item/${item.seriesId ?? item.id}`"
                class="truncate text-xl font-extrabold tracking-[-0.5px] transition hover:text-ink-2 hover:underline hover:underline-offset-4"
              >
                {{ title }}
              </NuxtLink>
            </div>
            <div class="ml-auto flex flex-wrap gap-2">
              <button
                v-if="nextEpisode"
                type="button"
                class="grid size-11 place-items-center rounded-full bg-white/10 transition hover:bg-white/15"
                aria-label="Next episode"
                title="Next episode"
                @click="emit('next')"
              >
                <svg class="size-[18px]" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M5 5v14l10-7z" /><rect x="16" y="5" width="3" height="14" rx="1" /></svg>
              </button>
              <button
                v-if="chapters.length"
                type="button"
                class="grid size-11 place-items-center rounded-full transition"
                :class="panel === 'chapters' ? 'bg-ink text-canvas' : 'bg-white/10 hover:bg-white/15'"
                aria-label="Chapters"
                title="Chapters"
                :aria-expanded="panel === 'chapters'"
                @click="togglePanel('chapters')"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><rect x="3.5" y="3.5" width="7" height="7" rx="1.5" /><rect x="13.5" y="3.5" width="7" height="7" rx="1.5" /><rect x="3.5" y="13.5" width="7" height="7" rx="1.5" /><rect x="13.5" y="13.5" width="7" height="7" rx="1.5" /></svg>
              </button>
              <button
                v-if="episodes?.length"
                type="button"
                class="grid size-11 place-items-center rounded-full transition"
                :class="panel === 'episodes' ? 'bg-ink text-canvas' : 'bg-white/10 hover:bg-white/15'"
                aria-label="Episodes"
                title="Episodes"
                :aria-expanded="panel === 'episodes'"
                @click="togglePanel('episodes')"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6h11M9 12h11M9 18h11" /><circle cx="4.5" cy="6" r="1" fill="currentColor" /><circle cx="4.5" cy="12" r="1" fill="currentColor" /><circle cx="4.5" cy="18" r="1" fill="currentColor" /></svg>
              </button>
              <button
                type="button"
                class="grid size-11 place-items-center rounded-full transition"
                :class="panel === 'settings' ? 'bg-ink text-canvas' : 'bg-white/10 hover:bg-white/15'"
                aria-label="Settings"
                title="Settings"
                :aria-expanded="panel === 'settings'"
                @click="togglePanel('settings')"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h9M17 7h3M4 17h3M11 17h9" /><circle cx="15" cy="7" r="2" /><circle cx="9" cy="17" r="2" /></svg>
              </button>
              <div class="flex h-11 items-center rounded-full bg-white/10">
                <button type="button" class="grid size-11 place-items-center rounded-full hover:bg-white/10" :aria-label="muted ? 'Unmute' : 'Mute'" @click="toggleMute">
                  <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round" aria-hidden="true">
                    <path d="M4 9h4l5-4v14l-5-4H4z" />
                    <path v-if="muted || volume === 0" d="M17 9l4 6M21 9l-4 6" />
                    <path v-else d="M16.5 8.5a5 5 0 0 1 0 7" />
                  </svg>
                </button>
                <label class="hidden sm:block">
                  <span class="sr-only">Volume</span>
                  <input
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    :value="muted ? 0 : volume"
                    class="mr-4 w-24 accent-ink"
                    @input="onVolumeInput"
                  >
                </label>
              </div>
              <button
                type="button"
                class="grid size-11 place-items-center rounded-full bg-white/10 hover:bg-white/15"
                :aria-label="isFullscreen ? 'Exit full screen' : 'Full screen'"
                @click="toggleFullscreen"
              >
                <svg v-if="!isFullscreen" class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5" /></svg>
                <svg v-else class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 4v5H4M20 9h-5V4M15 20v-5h5M4 15h5v5" /></svg>
              </button>
            </div>
          </div>

          <div class="flex items-center gap-3.5 text-[13px] font-bold tabular-nums text-ink-2">
            <span>{{ formatTime(currentTime) }}</span>
            <div
              ref="seekRef"
              role="slider"
              tabindex="0"
              aria-label="Seek"
              :aria-valuemin="0"
              :aria-valuemax="Math.round(duration)"
              :aria-valuenow="Math.round(currentTime)"
              :aria-valuetext="`${formatTime(currentTime)} of ${formatTime(duration)}`"
              class="group/seek relative flex h-6 flex-1 cursor-pointer touch-none items-center"
              @pointerdown="onSeekPointerDown"
              @pointermove="onSeekPointerMove"
              @pointerup="onSeekPointerUp"
              @pointerleave="!scrubbing && (hoverRatio = null)"
              @keydown="onSeekKeydown"
            >
              <div class="relative h-2 w-full overflow-hidden rounded-full bg-white/20 transition-[height] group-hover/seek:h-2.5">
                <div class="absolute inset-y-0 left-0 rounded-full bg-white/30" :style="{ width: `${bufferedRatio * 100}%` }" />
                <div class="absolute inset-y-0 left-0 rounded-full bg-ink" :style="{ width: `${playedRatio * 100}%` }" />
                <span
                  v-for="ch in chapters"
                  :key="ch.startPositionTicks"
                  class="absolute inset-y-0 w-0.5 bg-black/60"
                  :style="{ left: duration ? `${(ticksToSeconds(ch.startPositionTicks) / duration) * 100}%` : '0' }"
                />
              </div>
              <div
                v-if="hoverRatio != null && duration"
                class="pointer-events-none absolute bottom-7 flex -translate-x-1/2 flex-col items-center gap-1.5"
                :style="{ left: hoverPreview ? `clamp(${PREVIEW_WIDTH / 2}px, ${hoverRatio * 100}%, calc(100% - ${PREVIEW_WIDTH / 2}px))` : `${hoverRatio * 100}%` }"
              >
                <div
                  v-if="hoverPreview"
                  class="overflow-hidden rounded-[10px] bg-black bg-no-repeat shadow-[0_8px_24px_rgba(0,0,0,0.5)] ring-2 ring-white/80"
                  :style="{ width: `${PREVIEW_WIDTH}px`, height: `${hoverPreview.height}px`, ...hoverPreview.style }"
                />
                <span class="whitespace-nowrap rounded-lg bg-black/80 px-2.5 py-1 text-xs font-extrabold text-ink">
                  {{ formatTime(hoverTime ?? 0) }}<template v-if="hoverChapter"> · {{ hoverChapter }}</template>
                </span>
              </div>
            </div>
            <span>−{{ formatTime(Math.max(0, duration - currentTime)) }}</span>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Skip button / up-next card: stay up while the controls are hidden, and ride above the bar when they're shown -->
    <Transition
      enter-active-class="transition duration-200"
      leave-active-class="transition duration-200"
      enter-from-class="translate-y-2 opacity-0"
      leave-to-class="translate-y-2 opacity-0"
      mode="out-in"
    >
      <section
        v-if="upNextVisible && nextEpisode"
        key="up-next"
        aria-label="Up next"
        class="glass-strong absolute right-4 z-10 flex w-[min(380px,calc(100%-2rem))] flex-col gap-3 rounded-[22px] p-3.5 transition-[bottom] duration-300 sm:right-8"
        :style="{ bottom: chromeShown ? `${barClearance + 16}px` : '6rem' }"
      >
        <div class="flex items-center gap-3">
          <div class="aspect-video w-28 shrink-0 overflow-hidden rounded-[12px] bg-white/10">
            <img v-if="nextEpisodeImage" :src="nextEpisodeImage" alt="" class="size-full object-cover">
          </div>
          <div class="flex min-w-0 flex-col gap-0.5">
            <span class="text-xs font-extrabold uppercase tracking-[0.6px] text-muted">
              {{ prefs.autoplayNext ? `Next episode in ${upNextCountdown}` : 'Next episode' }}
            </span>
            <span class="line-clamp-2 text-[15px] font-extrabold leading-snug">{{ nextEpisodeLabel }}</span>
          </div>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            class="relative h-11 flex-1 overflow-hidden rounded-full bg-ink text-[15px] font-extrabold text-canvas transition hover:bg-ink/85"
            @click="emit('next')"
          >
            <span
              v-if="prefs.autoplayNext"
              aria-hidden="true"
              class="absolute inset-y-0 left-0 bg-black/15 transition-[width] duration-1000 ease-linear"
              :style="{ width: `${((UP_NEXT_SECONDS - upNextCountdown) / UP_NEXT_SECONDS) * 100}%` }"
            />
            <span class="relative inline-flex items-center gap-2">
              <svg class="size-[16px]" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
              Play now
            </span>
          </button>
          <button
            type="button"
            class="h-11 rounded-full bg-white/10 px-4 text-[15px] font-bold transition hover:bg-white/15"
            @click="dismissUpNext"
          >
            Watch credits
          </button>
        </div>
      </section>
      <button
        v-else-if="activeSkip"
        :key="`skip-${activeSkip.start}`"
        type="button"
        class="glass-strong absolute right-4 z-10 inline-flex h-12 items-center gap-2.5 rounded-full pl-5 pr-6 text-[15px] font-extrabold text-ink transition-[bottom,background-color] duration-300 hover:bg-white/15 sm:right-8"
        :style="{ bottom: chromeShown ? `${barClearance + 16}px` : '6rem' }"
        @click="skipPast(activeSkip)"
      >
        <svg class="size-[18px]" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M5 5v14l10-7z" /><rect x="16" y="5" width="3" height="14" rx="1" /></svg>
        {{ SKIP_LABELS[activeSkip.kind] }}
      </button>
      <p
        v-else-if="skipNotice"
        key="skip-notice"
        role="status"
        class="glass-strong pointer-events-none absolute right-4 z-10 inline-flex h-12 items-center rounded-full px-5 text-[15px] font-bold text-ink-2 transition-[bottom] duration-300 sm:right-8"
        :style="{ bottom: chromeShown ? `${barClearance + 16}px` : '6rem' }"
      >
        {{ skipNotice }}
      </p>
    </Transition>

    <div
      v-if="status"
      class="absolute inset-0 z-20 grid place-items-center bg-black/50"
    >
      <p class="glass-strong rounded-full px-5 py-2.5 text-sm font-bold text-ink">
        {{ status }}
      </p>
    </div>
  </div>
</template>
