import type {
  JellyfinChapter,
  JellyfinItem,
  JellyfinMediaSegment,
  JellyfinMediaStream,
} from '~/types/jellyfin'
import { ticksToSeconds } from './jellyfinHttp'

const TICKS_PER_MINUTE = 10_000_000 * 60

/** "1 hr 34 min", "26 min". */
export function runtimeLabel(ticks?: number | null): string | null {
  if (!ticks) return null
  const total = Math.max(1, Math.round(ticks / TICKS_PER_MINUTE))
  const hours = Math.floor(total / 60)
  const minutes = total % 60
  if (!hours) return `${minutes} min`
  return minutes ? `${hours} hr ${minutes} min` : `${hours} hr`
}

/** Minutes remaining for a partially watched item, or null. */
export function minutesLeft(item: JellyfinItem): number | null {
  const position = item.playbackPositionTicks ?? 0
  if (!item.runTimeTicks || position < 100_000_000) return null
  return Math.max(1, Math.round((item.runTimeTicks - position) / TICKS_PER_MINUTE))
}

export function timeLeftLabel(item: JellyfinItem): string | null {
  const left = minutesLeft(item)
  if (left == null) return null
  if (left < 60) return `${left} min left`
  const hours = Math.floor(left / 60)
  const minutes = left % 60
  return minutes ? `${hours} hr ${minutes} min left` : `${hours} hr left`
}

/** "Season 1, Episode 4" for episodes. */
export function episodeCode(item: JellyfinItem): string | null {
  if (item.type !== 'Episode') return null
  const s = item.parentIndexNumber
  const e = item.indexNumber
  if (s != null && e != null) return `Season ${s}, Episode ${e}`
  if (e != null) return `Episode ${e}`
  return null
}

export function isPlayable(item: JellyfinItem): boolean {
  return item.type === 'Movie' || item.type === 'Episode' || item.type === 'Video' || item.type === 'Trailer'
}

export function canResume(item: JellyfinItem): boolean {
  return isPlayable(item) && (item.playbackPositionTicks ?? 0) >= 100_000_000
}

/**
 * Tracks picked before playback. Undefined means "use the playback preferences";
 * null audio is the default track and null subtitles is explicitly off.
 */
export type TrackChoice = {
  audioStreamIndex?: number | null
  subtitleStreamIndex?: number | null
}

/** Route to the player, resuming unless `fromStart`. */
export function watchRoute(item: JellyfinItem, fromStart = false, tracks: TrackChoice = {}) {
  const resume = !fromStart && canResume(item)
  const query: Record<string, string> = { ticks: resume ? String(item.playbackPositionTicks) : '0' }
  if (tracks.audioStreamIndex != null) query.audio = String(tracks.audioStreamIndex)
  if (tracks.subtitleStreamIndex === null) query.sub = 'off'
  else if (tracks.subtitleStreamIndex != null) query.sub = String(tracks.subtitleStreamIndex)
  return { path: `/watch/${item.id}`, query }
}

/** Track picks from a /watch query; undefined for each one that is absent or invalid. */
export function trackChoiceFromQuery(query: Record<string, unknown>): TrackChoice {
  const parse = (value: unknown) => {
    const n = typeof value === 'string' && value !== '' ? Number(value) : Number.NaN
    return Number.isInteger(n) && n >= 0 ? n : undefined
  }
  return {
    audioStreamIndex: parse(query.audio),
    subtitleStreamIndex: query.sub === 'off' ? null : parse(query.sub),
  }
}

/** ISO 639-2 codes Jellyfin may use for the same language (bibliographic and terminology forms). */
const LANGUAGE_ALIASES: Record<string, string[]> = {
  fre: ['fre', 'fra'],
  ger: ['ger', 'deu'],
  dut: ['dut', 'nld'],
  chi: ['chi', 'zho'],
  nor: ['nor', 'nob', 'nno'],
}

export function matchesLanguage(stream: JellyfinMediaStream, language: string): boolean {
  const code = stream.language?.toLowerCase()
  return Boolean(code) && (LANGUAGE_ALIASES[language] ?? [language]).includes(code!)
}

/** The audio track in `language`, preferring the file's default when several match. */
export function preferredAudioStream(item: JellyfinItem, language: string | null): JellyfinMediaStream | null {
  if (!language) return null
  const matches = (item.mediaStreams ?? []).filter(s => s.type === 'Audio' && matchesLanguage(s, language))
  return matches.find(s => s.isDefault) ?? matches[0] ?? null
}

/** The subtitle track in `language`, preferring text tracks (no burn-in needed). */
export function preferredSubtitleStream(item: JellyfinItem, language: string | null): JellyfinMediaStream | null {
  if (!language) return null
  const matches = (item.mediaStreams ?? []).filter(s => s.type === 'Subtitle' && matchesLanguage(s, language))
  return matches.find(s => s.isTextSubtitle && s.isDefault)
    ?? matches.find(s => s.isTextSubtitle)
    ?? matches[0]
    ?? null
}

/** Quality caps offered in the player and Settings; Jellyfin picks the resolution to fit the bitrate. */
export const QUALITY_CAPS: { bitrate: number, height: number, label: string, detail: string }[] = [
  { bitrate: 20_000_000, height: 1080, label: '1080p', detail: '20 Mbps' },
  { bitrate: 10_000_000, height: 1080, label: '1080p', detail: '10 Mbps' },
  { bitrate: 6_000_000, height: 720, label: '720p', detail: '6 Mbps' },
  { bitrate: 3_000_000, height: 480, label: '480p', detail: '3 Mbps' },
  { bitrate: 1_000_000, height: 360, label: '360p', detail: '1 Mbps' },
]

export function streamLabel(stream: JellyfinMediaStream): string {
  return stream.displayTitle || stream.language || stream.codec || `Track ${stream.index}`
}

/** The track Jellyfin plays when none is requested. */
export function defaultAudioStream(item: JellyfinItem): JellyfinMediaStream | null {
  const audio = (item.mediaStreams ?? []).filter(s => s.type === 'Audio')
  return audio.find(s => s.isDefault) ?? audio[0] ?? null
}

const EXTRA_LABELS: Record<string, string> = {
  Trailer: 'Trailer',
  BehindTheScenes: 'Behind the Scenes',
  DeletedScene: 'Deleted Scene',
  Interview: 'Interview',
  Featurette: 'Featurette',
  Clip: 'Clip',
  Scene: 'Scene',
  Short: 'Short',
  Sample: 'Sample',
  ThemeVideo: 'Theme Video',
}

/** "Deleted Scene", "Behind the Scenes"…; "Extra" when Jellyfin doesn't say. */
export function extraLabel(item: JellyfinItem): string {
  return (item.extraType && EXTRA_LABELS[item.extraType]) || 'Extra'
}

/** A YouTube trailer's embeddable player URL, or null for other hosts. */
export function youTubeEmbedUrl(url: string): string | null {
  const match = /(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/)|youtu\.be\/)([\w-]{11})/.exec(url)
  return match ? `https://www.youtube-nocookie.com/embed/${match[1]}?autoplay=1&rel=0` : null
}

export function isInProgress(item: JellyfinItem): boolean {
  return !item.played && (item.playedPercentage ?? 0) > 0
}

/**
 * Nominal resolution class (2160/1080/720/576/480) for a video stream. Widescreen films are
 * often cropped (e.g. 1280×536 or 1920×800), so the class comes from width as well as height.
 */
export function resolutionClass(stream: Pick<JellyfinMediaStream, 'width' | 'height'> | null | undefined): number | null {
  const width = stream?.width ?? 0
  const height = stream?.height ?? 0
  if (!width && !height) return null
  if (width >= 3200 || height >= 1800) return 2160
  if (width >= 1800 || height >= 1000) return 1080
  if (width >= 1200 || height >= 700) return 720
  if (width >= 960 || height >= 560) return 576
  return 480
}

export function resolutionLabel(height: number): string {
  return height >= 2160 ? '4K' : `${height}p`
}

/** HD/4K/CC chips derived from media streams. */
export function qualityBadges(item: JellyfinItem): string[] {
  const streams = item.mediaStreams ?? []
  const badges: string[] = []
  const video = streams.find(s => s.type === 'Video')
  if (video?.width) {
    if (video.width >= 3200) badges.push('4K')
    else if (video.width >= 1200) badges.push('HD')
    else badges.push('SD')
  }
  if (streams.some(s => s.type === 'Subtitle')) badges.push('CC')
  return badges
}

export function yearLabel(item: JellyfinItem): string | null {
  if (item.type === 'Series' && item.productionYear) {
    const end = item.endDate ? new Date(item.endDate).getFullYear() : null
    if (end && end !== item.productionYear) return `${item.productionYear} – ${end}`
  }
  return item.productionYear ? String(item.productionYear) : null
}

/** The title used for A–Z grouping: Jellyfin's SortName, minus leading articles. */
export function sortTitle(item: JellyfinItem): string {
  const base = (item.sortName || item.name).trim()
  return base.replace(/^(the|a|an)\s+/i, '')
}

export function sortLetter(item: JellyfinItem): string {
  const ch = sortTitle(item).charAt(0).toUpperCase()
  return /[A-Z]/.test(ch) ? ch : '#'
}

export type GenreCount = { name: string, count: number }

/** Genre tallies for a set of items, most common first. */
export function countGenres(items: Pick<JellyfinItem, 'genres'>[]): GenreCount[] {
  const counts = new Map<string, number>()
  for (const item of items) {
    for (const name of item.genres ?? []) counts.set(name, (counts.get(name) ?? 0) + 1)
  }
  return [...counts.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
}

export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map(part => part.charAt(0).toUpperCase())
    .join('')
}

/** Hero title size stepped down by length so long names don't run to five lines. */
export function heroTitleClass(title: string): string {
  const length = title.length
  if (length <= 18) return 'text-[clamp(2.75rem,7.5vw,6.5rem)] leading-[0.9]'
  if (length <= 30) return 'text-[clamp(2.5rem,6vw,5.25rem)] leading-[0.92]'
  if (length <= 48) return 'text-[clamp(2.25rem,4.75vw,4rem)] leading-[0.95]'
  return 'text-[clamp(2rem,3.75vw,3.25rem)] leading-[1]'
}

export type SkipKind = 'Intro' | 'Recap' | 'Preview' | 'Commercial' | 'Outro'

/** A stretch of the video the player offers to skip, in seconds. */
export type SkipRange = { start: number, end: number, kind: SkipKind, source: 'segment' | 'chapter' }

export const SKIP_LABELS: Record<SkipKind, string> = {
  Intro: 'Skip intro',
  Recap: 'Skip recap',
  Preview: 'Skip preview',
  Commercial: 'Skip ad',
  Outro: 'Skip credits',
}

/**
 * Chapter titles that mean "opening titles". Matched against the whole name (minus a
 * leading number) because disc chapters are often scene names like "The Opening Move".
 */
const INTRO_CHAPTER = /^(?:intro(?:duction)?|opening(?: (?:credits|titles|theme|sequence))?|op|theme(?: song)?|title sequence|main titles)$/i
const CREDITS_CHAPTER = /^(?:(?:end(?:ing)?|closing) (?:credits|titles)|credits|ending|outro|ed)$/i

/** Chapter-marked intros outside this range are more likely mislabelled scenes. */
const MIN_INTRO_SECONDS = 5
const MAX_INTRO_SECONDS = 180
const MAX_CREDITS_SECONDS = 15 * 60

function chapterTitle(chapter: JellyfinChapter): string {
  return chapter.name.trim().replace(/^\d+\s*[.:\-–]\s*/, '')
}

/** A chapter named like `pattern`, running to the next chapter (or `fileEnd`). */
function chapterRange(
  sorted: readonly JellyfinChapter[],
  pattern: RegExp,
  fileEnd: number | null,
): { start: number, end: number } | null {
  const index = sorted.findIndex(ch => pattern.test(chapterTitle(ch)))
  const chapter = sorted[index]
  if (!chapter) return null
  const next = sorted[index + 1]
  const end = next ? ticksToSeconds(next.startPositionTicks) : fileEnd
  if (end == null) return null
  return { start: ticksToSeconds(chapter.startPositionTicks), end }
}

/**
 * Everything the player can offer to skip: Jellyfin's media segments when the server
 * has them, else chapters named like an intro or end credits. `durationSeconds` lets a
 * final credits chapter run to the end of the file.
 */
export function skipRanges(
  segments: readonly JellyfinMediaSegment[],
  chapters: readonly JellyfinChapter[],
  durationSeconds: number | null = null,
): SkipRange[] {
  const ranges: SkipRange[] = segments
    .filter(s => s.endTicks > s.startTicks)
    .map(s => ({
      start: ticksToSeconds(s.startTicks),
      end: ticksToSeconds(s.endTicks),
      kind: s.type,
      source: 'segment' as const,
    }))
  const sorted = [...chapters].sort((a, b) => a.startPositionTicks - b.startPositionTicks)
  if (!ranges.some(r => r.kind === 'Intro')) {
    // An intro chapter must be followed by another, or it is the whole file.
    const intro = chapterRange(sorted, INTRO_CHAPTER, null)
    const length = intro ? intro.end - intro.start : 0
    if (intro && length >= MIN_INTRO_SECONDS && length <= MAX_INTRO_SECONDS) {
      ranges.push({ ...intro, kind: 'Intro', source: 'chapter' })
    }
  }
  if (!ranges.some(r => r.kind === 'Outro')) {
    const duration = durationSeconds && durationSeconds > 0 ? durationSeconds : null
    const credits = chapterRange(sorted, CREDITS_CHAPTER, duration)
    const length = credits ? credits.end - credits.start : 0
    // Credits sit in the back half; earlier matches are scene names.
    const late = credits && duration ? credits.start >= duration / 2 : false
    if (credits && late && length >= MIN_INTRO_SECONDS && length <= MAX_CREDITS_SECONDS) {
      ranges.push({ ...credits, kind: 'Outro', source: 'chapter' })
    }
  }
  return ranges.sort((a, b) => a.start - b.start)
}
