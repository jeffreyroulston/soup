<script setup lang="ts">
import { keepPreviousData, useQuery, useQueryClient } from '@tanstack/vue-query'
import type { JellyfinItem, JellyfinPerson } from '~/types/jellyfin'
import type { TrackChoice } from '~/utils/media'

definePageMeta({ middleware: 'auth', layout: 'app' })

const route = useRoute()
const { prefs } = usePlaybackPrefs()
const { imageUrl, personImageUrl } = useJellyfin()
const queries = useJellyfinQueries()
const favoriteMutation = useFavoriteMutation()
const playedMutation = usePlayedMutation()

const itemId = computed(() => String(route.params.id))
const itemQuery = useQuery(computed(() => queries.item(itemId.value)))
// Fetched alongside the item so Related doesn't push the page down later.
const similarQuery = useQuery(computed(() => queries.similar(itemId.value)))

const item = computed(() => itemQuery.data.value ?? null)
const isSeries = computed(() => item.value?.type === 'Series')
const isCollection = computed(() => item.value?.type === 'BoxSet')
const isEpisode = computed(() => item.value?.type === 'Episode')

const queryClient = useQueryClient()

/** An item with this id in any cached response (a season's episodes, a home row…), or null. */
function findCached(value: unknown, id: string, depth = 0): JellyfinItem | null {
  if (!value || typeof value !== 'object' || depth > 5) return null
  if (Array.isArray(value)) {
    for (const entry of value) {
      const found = findCached(entry, id, depth + 1)
      if (found) return found
    }
    return null
  }
  const record = value as Record<string, unknown>
  if (record.id === id && typeof record.type === 'string') return record as JellyfinItem
  for (const entry of Object.values(record)) {
    const found = findCached(entry, id, depth + 1)
    if (found) return found
  }
  return null
}

/**
 * Shapes the skeleton before the item arrives: the page was usually opened from a list that
 * already knows the type, so an episode doesn't flash the full-bleed title hero first.
 */
const skeletonIsEpisode = computed(() => {
  if (item.value) return isEpisode.value
  const id = itemId.value
  return queryClient.getQueriesData({ queryKey: queryKeys.all })
    .some(([, data]) => findCached(data, id)?.type === 'Episode')
})

// Seasons have no page of their own; show the series with that season selected.
watch(item, (value) => {
  if (value?.type === 'Season' && value.seriesId) navigateTo(itemRoute(value), { replace: true })
}, { immediate: true })

const seasonsQuery = useQuery(computed(() => ({ ...queries.seasons(itemId.value), enabled: isSeries.value })))
const nextUpQuery = useQuery(computed(() => ({ ...queries.seriesNextUp(itemId.value), enabled: isSeries.value })))
const collectionQuery = useQuery(computed(() => ({
  ...queries.libraryItems(itemId.value, 'ProductionYear'),
  enabled: isCollection.value,
})))

const extrasQuery = useQuery(computed(() => ({
  ...queries.extras({
    id: itemId.value,
    localTrailerCount: item.value?.localTrailerCount,
    specialFeatureCount: item.value?.specialFeatureCount,
  }),
  enabled: Boolean(item.value?.localTrailerCount || item.value?.specialFeatureCount),
})))

const seasons = computed(() => seasonsQuery.data.value ?? [])
const nextUp = computed(() => nextUpQuery.data.value ?? null)
const similar = computed(() => similarQuery.data.value ?? [])
const collectionItems = computed(() => collectionQuery.data.value ?? [])
const extras = computed(() => extrasQuery.data.value ?? [])

/** A local trailer plays in Soup's player; otherwise the first remote (YouTube) one. */
const trailer = computed(() => {
  const local = extras.value.find(extra => extra.extraType === 'Trailer')
  if (local) return { kind: 'local' as const, item: local }
  const remote = item.value?.remoteTrailers?.[0]
  return remote ? { kind: 'remote' as const, url: remote.url } : null
})
/** The YouTube player shown over the page, or null. */
const trailerEmbed = ref<string | null>(null)

/** A season picked on this page; until then the linked, next-up or first season. */
const pickedSeasonId = ref<string | null>(null)
const requestedSeason = computed(() => seasons.value.find(season => season.id === route.query.season) ?? null)
const selectedSeasonId = computed(() => {
  if (pickedSeasonId.value) return pickedSeasonId.value
  if (requestedSeason.value) return requestedSeason.value.id
  // Wait for Next Up so the page doesn't open on season 1 and then jump.
  if (nextUpQuery.isPending.value) return null
  const list = seasons.value
  return (list.find(season => season.id === nextUp.value?.seasonId) ?? list[0])?.id ?? null
})

const episodesQuery = useQuery(computed(() => ({
  ...queries.episodes(itemId.value, selectedSeasonId.value),
  enabled: isSeries.value && selectedSeasonId.value != null,
  // Keep the previous season on screen (dimmed) while the next one loads.
  placeholderData: keepPreviousData,
})))
const episodes = computed(() => episodesQuery.data.value ?? [])
const loadingEpisodes = computed(() => episodesQuery.isPlaceholderData.value)
/** Server-wide failures show in the offline banner; anything else gets a short note. */
const episodesError = computed(() => {
  const error = episodesQuery.error.value
  if (!error || OFFLINE_KINDS.includes(classifyError(error))) return ''
  return 'Couldn\'t load these episodes.'
})
const watchedEpisodes = computed(() => episodes.value.filter(ep => ep.played).length)

// An episode page links to its neighbours in the season and carries a small card for the show.
// Both lists are usually cached already by the series page the episode was opened from.
const seriesQuery = useQuery(computed(() => ({
  ...queries.item(item.value?.seriesId ?? ''),
  enabled: isEpisode.value && Boolean(item.value?.seriesId),
})))
const seasonEpisodesQuery = useQuery(computed(() => ({
  ...queries.episodes(item.value?.seriesId ?? '', item.value?.seasonId ?? null),
  enabled: isEpisode.value && Boolean(item.value?.seriesId && item.value?.seasonId),
})))
const series = computed(() => (isEpisode.value ? seriesQuery.data.value ?? null : null))
const adjacentEpisodes = computed(() => {
  const list = isEpisode.value ? seasonEpisodesQuery.data.value ?? [] : []
  const index = list.findIndex(ep => ep.id === itemId.value)
  if (index < 0) return { previous: null, next: null }
  return { previous: list[index - 1] ?? null, next: list[index + 1] ?? null }
})

/** Skeleton until everything that shapes the layout above the fold has arrived. */
const loading = computed(() => {
  if (itemQuery.isPending.value) return true
  // Episodes don't show Related, so they don't wait for it.
  if (!isEpisode.value && similarQuery.isPending.value) return true
  if (isSeries.value) {
    if (seasonsQuery.isPending.value || nextUpQuery.isPending.value) return true
    if (selectedSeasonId.value && episodesQuery.isPending.value) return true
  }
  return isCollection.value && collectionQuery.isPending.value
})

/** Only when there's nothing to show; a failed background refresh keeps the page. */
const loadError = computed(() => (item.value ? null : itemQuery.error.value))

const moreOpen = ref(false)
const actionError = ref('')
/** Tracks picked here are handed to the player; null subtitle is off. */
const selectedAudio = ref<number | null>(null)
const selectedSubtitle = ref<number | null>(null)
/** Quality cap in bits/s for the player; null is Auto. */
const selectedQuality = ref<number | null>(null)

// Per-title UI state resets on navigation, not when a refetch replaces the same title's data.
watch(itemId, () => {
  trailerEmbed.value = null
  pickedSeasonId.value = null
  moreOpen.value = false
  actionError.value = ''
  logoFailed.value = false
})

// Pickers open on the tracks Settings prefers, falling back to the file's defaults.
watch(() => item.value?.id, () => {
  const value = item.value
  selectedAudio.value = value
    ? (preferredAudioStream(value, prefs.value.audioLanguage) ?? defaultAudioStream(value))?.index ?? null
    : null
  selectedSubtitle.value = value ? preferredSubtitleStream(value, prefs.value.subtitleLanguage)?.index ?? null : null
  selectedQuality.value = prefs.value.maxBitrate
}, { immediate: true })

// A link to a season (?season=) scrolls to the episodes once they're on screen.
watch(loading, async (isLoading) => {
  if (isLoading || !requestedSeason.value) return
  await nextTick()
  document.getElementById('episodes')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}, { immediate: true })

const backdrop = computed(() => (item.value ? imageUrl(item.value, 'Backdrop', 1920) : null))
/** An episode leads with its own still; the show's backdrop only when it has none. */
const still = computed(() => (isEpisode.value && item.value
  ? imageUrl(item.value, 'Primary', 1280) ?? backdrop.value
  : null))

/**
 * Title art in place of the text title. Episodes keep the text: their heading is the
 * episode's name, and the show's logo would read as the show.
 */
const logoFailed = ref(false)
const logo = computed(() => {
  const value = item.value
  if (!value || logoFailed.value || value.type === 'Episode') return null
  return imageUrl(value, 'Logo', 960)
})

/** The More menu closes on a click outside it or Escape. */
const moreRef = ref<HTMLElement | null>(null)
function onMorePointerDown(event: PointerEvent) {
  if (moreOpen.value && event.target instanceof Node && !moreRef.value?.contains(event.target)) {
    moreOpen.value = false
  }
}
function onMoreKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') moreOpen.value = false
}
onMounted(() => {
  window.addEventListener('pointerdown', onMorePointerDown, true)
  window.addEventListener('keydown', onMoreKeydown)
})
onBeforeUnmount(() => {
  window.removeEventListener('pointerdown', onMorePointerDown, true)
  window.removeEventListener('keydown', onMoreKeydown)
})

/** What the big button plays: the item itself, or the series' next-up episode. */
const playTarget = computed<JellyfinItem | null>(() => {
  if (!item.value) return null
  if (isPlayable(item.value)) return item.value
  if (isSeries.value) return nextUp.value ?? episodes.value[0] ?? null
  return null
})

const playLabel = computed(() => {
  const target = playTarget.value
  if (!target) return null
  const code = target.id !== item.value?.id ? episodeCode(target) : null
  if (canResume(target)) return code ? `Resume ${code}` : 'Resume'
  return code ? `Play ${code}` : 'Play'
})

const progressPercent = computed(() => {
  const target = playTarget.value
  return target && isInProgress(target) ? Math.min(100, target.playedPercentage ?? 0) : 0
})

const title = computed(() => item.value?.name ?? '')

/** Air dates are stored as UTC midnight; formatting them in local time can land on the day before. */
function airDate(value: JellyfinItem, month: 'short' | 'long'): string | null {
  if (!value.premiereDate) return null
  const date = new Date(value.premiereDate)
  if (Number.isNaN(date.getTime())) return null
  return date.toLocaleDateString(undefined, { day: 'numeric', month, year: 'numeric', timeZone: 'UTC' })
}

/** "Season 1 · Episode 4" above an episode's title. */
const episodeLabel = computed(() => {
  const value = item.value
  if (!value || !isEpisode.value) return null
  return [
    value.parentIndexNumber != null ? `Season ${value.parentIndexNumber}` : null,
    value.indexNumber != null ? `Episode ${value.indexNumber}` : null,
  ].filter(Boolean).join(' · ') || null
})

const metaBits = computed(() => {
  const value = item.value
  if (!value) return []
  if (isEpisode.value) {
    const aired = airDate(value, 'short')
    return [
      aired ? `Aired ${aired}` : null,
      runtimeLabel(value.runTimeTicks),
      value.communityRating ? `★ ${value.communityRating.toFixed(1)}` : null,
    ].filter((bit): bit is string => Boolean(bit))
  }
  return [
    value.genres?.slice(0, 2).join(', '),
    yearLabel(value),
    value.communityRating ? `★ ${value.communityRating.toFixed(1)}` : null,
    runtimeLabel(value.runTimeTicks),
  ].filter((bit): bit is string => Boolean(bit))
})

const chips = computed(() => {
  const value = item.value
  if (!value) return []
  const source = playTarget.value?.mediaStreams?.length ? playTarget.value : value
  return [value.officialRating, ...qualityBadges(source)].filter((chip): chip is string => Boolean(chip))
})

/** Track pickers only apply when the page's own item is what Play starts. */
const trackStreams = computed(() => {
  const value = item.value
  if (!value || playTarget.value?.id !== value.id) return { audio: [], subtitles: [] }
  const streams = value.mediaStreams ?? []
  return {
    audio: streams.filter(s => s.type === 'Audio'),
    subtitles: streams.filter(s => s.type === 'Subtitle'),
  }
})

const trackChoice = computed<TrackChoice>(() => {
  const value = item.value
  if (!value || playTarget.value?.id !== value.id) return {}
  // Both are explicit, so the player doesn't swap in the preferred tracks.
  return {
    audioStreamIndex: selectedAudio.value,
    subtitleStreamIndex: selectedSubtitle.value,
    maxBitrate: selectedQuality.value,
  }
})

/** Auto plus the caps that would lower the file's quality, as in the player; none when Play starts something else. */
const qualityOptions = computed(() => {
  const value = item.value
  if (!value || playTarget.value?.id !== value.id) return []
  const video = value.mediaStreams?.find(s => s.type === 'Video')
  if (!video) return []
  const source = resolutionClass(video)
  return [
    { value: null, label: source ? `Auto · ${resolutionLabel(source)}` : 'Auto' },
    ...qualityCapsFor(value).map(q => ({ value: q.bitrate, label: `${q.label} · ${q.detail}` })),
  ]
})

// An episode's people are mostly the show's regulars; the show card lists those instead.
const cast = computed<JellyfinPerson[]>(() => (isEpisode.value ? [] : (item.value?.people ?? []).slice(0, 20)))

/** Who directed and wrote this episode. */
const episodeCredits = computed(() => {
  const people = isEpisode.value ? item.value?.people ?? [] : []
  const names = (type: string) => [...new Set(people.filter(p => p.type === type).map(p => p.name))].join(', ')
  return [
    { label: 'Director', value: names('Director') },
    { label: 'Writer', value: names('Writer') },
  ].filter(entry => entry.value)
})

const seriesPoster = computed(() => (series.value ? imageUrl(series.value, 'Primary', 320) : null))
const seriesMeta = computed(() => {
  const value = series.value
  if (!value) return ''
  return ['Series', yearLabel(value), value.genres?.slice(0, 2).join(', ')].filter(Boolean).join(' · ')
})
const seriesCast = computed(() => (series.value?.people ?? []).filter(p => p.type === 'Actor').slice(0, 3))

type InfoEntry = {
  label: string
  value?: string
  links?: { label: string, href: string }[]
}

function providerLinks(
  ids: Record<string, string> | undefined,
  itemType: string,
): { label: string, href: string }[] {
  if (!ids) return []
  const links: { label: string, href: string }[] = []
  const imdb = ids.Imdb || ids.IMDB
  if (imdb) links.push({ label: 'IMDb', href: `https://www.imdb.com/title/${imdb}/` })
  const tmdb = ids.Tmdb || ids.TmdbId || ids.TMDb
  if (tmdb) {
    const kind = itemType === 'Movie' ? 'movie' : 'tv'
    links.push({ label: 'TMDB', href: `https://www.themoviedb.org/${kind}/${tmdb}` })
  }
  const tvdb = ids.Tvdb || ids.TvdbId || ids.TVDB
  if (tvdb && (itemType === 'Series' || itemType === 'Season' || itemType === 'Episode')) {
    links.push({ label: 'TVDB', href: `https://www.thetvdb.com/?tab=series&id=${tvdb}` })
  }
  return links
}

const information = computed((): InfoEntry[] => {
  const value = item.value
  if (!value) return []
  const original = value.originalTitle?.trim()
  const showOriginal = original
    && original.localeCompare(value.name.trim(), undefined, { sensitivity: 'accent' }) !== 0
  const links = providerLinks(value.providerIds, value.type)
  if (value.type === 'Episode') {
    const streams = value.mediaStreams ?? []
    const video = streams.find(s => s.type === 'Video')
    const height = resolutionClass(video)
    const entries: InfoEntry[] = [
      { label: 'Aired', value: airDate(value, 'long') || undefined },
      { label: 'Runtime', value: runtimeLabel(value.runTimeTicks) || undefined },
      {
        label: 'Video',
        value: video
          ? [height ? resolutionLabel(height) : null, video.codec?.toUpperCase()].filter(Boolean).join(' · ') || undefined
          : undefined,
      },
      { label: 'Bitrate', value: value.sourceBitrate ? bitrateLabel(value.sourceBitrate) : undefined },
      { label: 'Audio', value: streams.filter(s => s.type === 'Audio').map(streamLabel).join('\n') || undefined },
      { label: 'Subtitles', value: streams.filter(s => s.type === 'Subtitle').map(streamLabel).join(', ') || undefined },
      { label: 'File', value: value.path || undefined },
      { label: 'Links', links: links.length ? links : undefined },
    ]
    return entries.filter(entry => Boolean(entry.value) || Boolean(entry.links?.length))
  }
  const entries: InfoEntry[] = [
    { label: 'Original title', value: showOriginal ? original : undefined },
    { label: 'Studio', value: value.studios?.join(', ') || undefined },
    { label: 'Network', value: value.networks?.join(', ') || undefined },
    { label: 'Released', value: yearLabel(value) || undefined },
    { label: 'Status', value: value.status || undefined },
    { label: 'Genres', value: value.genres?.join(', ') || undefined },
    { label: 'Country', value: value.productionLocations?.join(', ') || undefined },
    { label: 'Tags', value: value.tags?.join(', ') || undefined },
    { label: 'Rated', value: value.officialRating || undefined },
    {
      label: 'Critics',
      value: value.criticRating != null ? `${Math.round(value.criticRating)}%` : undefined,
    },
    { label: 'Runtime', value: runtimeLabel(value.runTimeTicks) || undefined },
    { label: 'Bitrate', value: value.sourceBitrate ? bitrateLabel(value.sourceBitrate) : undefined },
    { label: 'Links', links: links.length ? links : undefined },
  ]
  return entries.filter(entry => Boolean(entry.value) || Boolean(entry.links?.length))
})

// Both toggles patch the cached item first, so these flip immediately.
const favorite = computed(() => Boolean(item.value?.isFavorite))
/** A multi-season series' Watched button covers the selected season; More marks every episode. */
const seasonScoped = computed(() => isSeries.value && seasons.value.length > 1)
const selectedSeason = computed(() => seasons.value.find(season => season.id === selectedSeasonId.value) ?? null)
const watchTarget = computed(() => seasonScoped.value ? selectedSeason.value : item.value)
const watched = computed(() => Boolean(watchTarget.value?.played))
const allWatched = computed(() => Boolean(item.value?.played))

function toggleFavorite() {
  if (!item.value) return
  actionError.value = ''
  favoriteMutation.mutate({ id: item.value.id, value: !favorite.value }, {
    onError: () => { actionError.value = 'Could not update favourites' },
  })
}

function setWatched(target: JellyfinItem | null | undefined, value: boolean) {
  if (!target) return
  actionError.value = ''
  playedMutation.mutate({ id: target.id, value }, {
    onError: () => { actionError.value = 'Could not update watched state' },
  })
}

function toggleWatched() {
  setWatched(watchTarget.value, !watched.value)
}

function toggleAllWatched() {
  moreOpen.value = false
  setWatched(item.value, !allWatched.value)
}

function play(fromStart = false) {
  moreOpen.value = false
  if (!playTarget.value) return
  return navigateTo(watchRoute(playTarget.value, fromStart, trackChoice.value))
}

function playTrailer() {
  const value = trailer.value
  if (!value) return
  if (value.kind === 'local') {
    void navigateTo(watchRoute(value.item, true))
    return
  }
  const embed = youTubeEmbedUrl(value.url)
  if (embed) trailerEmbed.value = embed
  else window.open(value.url, '_blank', 'noopener,noreferrer')
}

function onTrailerKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') trailerEmbed.value = null
}

watch(trailerEmbed, (open) => {
  if (open) window.addEventListener('keydown', onTrailerKeydown)
  else window.removeEventListener('keydown', onTrailerKeydown)
})

onBeforeUnmount(() => window.removeEventListener('keydown', onTrailerKeydown))

function episodeKicker(ep: JellyfinItem) {
  const parts = [ep.indexNumber != null ? `Episode ${ep.indexNumber}` : null]
  parts.push(timeLeftLabel(ep) ?? runtimeLabel(ep.runTimeTicks))
  return parts.filter(Boolean).join(', ')
}

function selectSeason(seasonId: string) {
  pickedSeasonId.value = seasonId
}

/** The episode rail scrolls natively; the arrows page it on wider screens. */
const episodeRail = ref<HTMLElement | null>(null)
const railCanPrev = ref(false)
const railCanNext = ref(false)

function syncRail() {
  const el = episodeRail.value
  if (!el) return
  railCanPrev.value = el.scrollLeft > 4
  railCanNext.value = el.scrollLeft + el.clientWidth < el.scrollWidth - 4
}

function scrollRail(direction: 1 | -1) {
  const el = episodeRail.value
  el?.scrollBy({ left: direction * el.clientWidth * 0.8, behavior: 'smooth' })
}

watch(selectedSeasonId, () => episodeRail.value?.scrollTo({ left: 0 }))
watch([episodes, episodeRail], () => nextTick(syncRail), { immediate: true })
onMounted(() => window.addEventListener('resize', syncRail))
onBeforeUnmount(() => window.removeEventListener('resize', syncRail))
</script>

<template>
  <main class="w-full pb-20">
    <!-- Episode skeleton: same grid as the episode hero below -->
    <div v-if="loading && skeletonIsEpisode" aria-busy="true" aria-label="Loading episode">
      <section class="w-full px-4 pb-6 pt-24 sm:px-8 sm:pt-28 lg:px-12">
        <div class="grid gap-6 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] lg:grid-rows-[auto_1fr] lg:gap-x-12 lg:gap-y-3.5">
          <span class="block aspect-video w-full animate-pulse rounded-[18px] bg-surface lg:col-start-1 lg:row-start-1" />
          <div class="flex min-w-0 flex-col gap-4 lg:col-start-2 lg:row-span-2 lg:row-start-1">
            <span class="text-sm"><span class="inline-block h-[0.8em] w-40 animate-pulse rounded bg-elevated align-middle" /></span>
            <span class="block h-[calc(clamp(2.25rem,4vw,3.5rem)*0.9)] w-3/4 animate-pulse rounded-btn bg-elevated" />
            <span class="text-[15px]"><span class="inline-block h-[0.8em] w-44 animate-pulse rounded bg-elevated align-middle" /></span>
            <div class="grid grid-cols-3 gap-2 sm:flex sm:items-center sm:gap-3">
              <span class="col-span-full h-[52px] animate-pulse rounded-btn bg-elevated sm:w-44" />
              <span class="h-[60px] animate-pulse rounded-btn bg-elevated sm:size-[52px] sm:rounded-full" />
              <span class="h-[60px] animate-pulse rounded-btn bg-elevated sm:size-[52px] sm:rounded-full" />
              <span class="h-[60px] animate-pulse rounded-btn bg-elevated sm:size-[52px] sm:rounded-full" />
            </div>
            <div class="flex flex-wrap gap-2">
              <span class="h-11 w-32 animate-pulse rounded-full bg-surface" />
              <span class="h-11 w-36 animate-pulse rounded-full bg-surface" />
              <span class="h-11 w-32 animate-pulse rounded-full bg-surface" />
            </div>
            <span class="flex flex-col text-[17px] leading-relaxed">
              <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
              <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
              <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
              <span><span class="inline-block h-[0.8em] w-1/2 animate-pulse rounded bg-elevated align-middle" /></span>
            </span>
          </div>
          <div class="grid grid-cols-2 gap-3 self-start lg:col-start-1 lg:row-start-2">
            <span class="h-[65px] animate-pulse rounded-[14px] bg-surface" />
            <span class="h-[65px] animate-pulse rounded-[14px] bg-surface" />
          </div>
        </div>
      </section>
      <div class="px-4 pt-6 sm:px-8 lg:px-12">
        <span class="block h-[186px] animate-pulse rounded-[18px] border border-elevated bg-surface/60" />
      </div>
    </div>
    <div v-else-if="loading" aria-busy="true" aria-label="Loading title">
      <!-- Same box, padding and order as the hero below: title, meta, actions -->
      <section class="relative min-h-[min(88vh,720px)] w-full overflow-hidden bg-surface/50">
        <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/75 via-40% to-transparent to-75%" />
        <div class="relative flex min-h-[min(88vh,720px)] flex-wrap items-end justify-between gap-8 px-4 pb-6 pt-32 sm:px-8 lg:px-12">
          <div class="flex w-full max-w-[820px] flex-col gap-4">
            <span class="block h-[calc(clamp(2.75rem,7.5vw,6.5rem)*0.9)] w-2/3 animate-pulse rounded-btn bg-elevated" />
            <span class="text-[15px] font-semibold"><span class="inline-block h-[0.8em] w-52 animate-pulse rounded bg-elevated align-middle" /></span>
            <!-- Phones: Play full width over three tiles. Wider: Play, two labelled pills, More. -->
            <div class="grid grid-cols-3 gap-2 sm:flex sm:items-center sm:gap-3">
              <span class="col-span-full h-[52px] animate-pulse rounded-btn bg-elevated sm:w-48" />
              <span class="h-[60px] animate-pulse rounded-btn bg-elevated sm:h-[52px] sm:w-44 sm:rounded-full" />
              <span class="h-[60px] animate-pulse rounded-btn bg-elevated sm:h-[52px] sm:w-48 sm:rounded-full" />
              <span class="h-[60px] animate-pulse rounded-btn bg-elevated sm:size-[52px] sm:rounded-full" />
            </div>
          </div>
        </div>
      </section>
      <div class="flex flex-col gap-12">
        <!-- Pickers and overview sit under the hero, as on the loaded page -->
        <div class="flex flex-col gap-4 px-4 sm:px-8 lg:px-12">
          <div class="flex flex-wrap gap-2">
            <span class="h-11 w-36 animate-pulse rounded-full bg-surface" />
            <span class="h-11 w-36 animate-pulse rounded-full bg-surface" />
            <span class="h-11 w-32 animate-pulse rounded-full bg-surface" />
          </div>
          <span class="flex max-w-[760px] flex-col text-[17px] leading-relaxed">
            <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
            <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
            <span><span class="inline-block h-[0.8em] w-2/3 animate-pulse rounded bg-elevated align-middle" /></span>
          </span>
        </div>
        <!-- Cast & Crew comes before Related on the loaded page -->
        <section aria-hidden="true" class="flex flex-col gap-3.5">
          <span class="mx-4 block h-7 w-40 animate-pulse rounded bg-elevated sm:mx-8 lg:mx-12" />
          <div class="flex gap-7 overflow-hidden px-4 sm:px-8 lg:px-12">
            <div v-for="n in 8" :key="n" class="flex w-[112px] shrink-0 flex-col items-center gap-2.5 sm:w-32">
              <span class="size-[112px] animate-pulse rounded-full bg-surface sm:size-32" />
              <span class="h-3.5 w-20 animate-pulse rounded bg-elevated" />
              <span class="h-3 w-14 animate-pulse rounded bg-surface" />
            </div>
          </div>
        </section>
      </div>
    </div>
    <ErrorState v-else-if="loadError" class="pt-32" :error="loadError" :on-retry="itemQuery.refetch" />
    <template v-else-if="item">
      <!-- Hero: a title gets its full-bleed backdrop; an episode leads with its own still and keeps the show small -->
      <!-- No overflow-hidden: the More menu drops below the hero's bottom edge -->
      <section
        :aria-label="title"
        class="relative w-full"
        :class="isEpisode ? 'px-4 pb-6 pt-24 sm:px-8 sm:pt-28 lg:px-12' : 'min-h-[min(88vh,720px)]'"
      >
        <template v-if="!isEpisode">
          <div class="absolute inset-0 bg-surface">
            <img v-if="backdrop" :src="backdrop" alt="" class="absolute inset-0 size-full object-cover object-top">
          </div>
          <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/75 via-40% to-transparent to-75%" />
        </template>

        <!-- Episodes, wide: still with prev/next under it on the left, details on the right. Phones: one column. -->
        <div
          :class="isEpisode
            ? 'grid gap-6 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] lg:grid-rows-[auto_1fr] lg:gap-x-12 lg:gap-y-3.5'
            : 'relative flex min-h-[min(88vh,720px)] flex-wrap items-end justify-between gap-8 px-4 pb-6 pt-32 sm:px-8 lg:px-12'"
        >
          <button
            v-if="isEpisode"
            type="button"
            class="group relative block aspect-video w-full overflow-hidden rounded-[18px] bg-surface shadow-[0_30px_60px_rgba(0,0,0,0.45)] ring-1 ring-white/10 lg:col-start-1 lg:row-start-1"
            :aria-label="`${playLabel ?? 'Play'} ${title}`"
            :disabled="!playTarget"
            @click="play(false)"
          >
            <img v-if="still" :src="still" alt="" class="absolute inset-0 size-full object-cover">
            <span class="glass absolute left-1/2 top-1/2 grid size-16 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full transition duration-200 group-hover:scale-105 sm:size-[76px]">
              <svg class="ml-1 size-7" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
            </span>
            <span v-if="progressPercent > 0" class="absolute inset-x-4 bottom-4 h-[5px] overflow-hidden rounded-full bg-white/30" aria-hidden="true">
              <span class="block h-full rounded-full bg-accent" :style="{ width: `${progressPercent}%` }" />
            </span>
          </button>

          <div class="flex flex-col gap-4" :class="isEpisode ? 'min-w-0 lg:col-start-2 lg:row-span-2 lg:row-start-1' : 'max-w-[820px]'">
            <span v-if="episodeLabel" class="text-sm font-extrabold uppercase tracking-[1px] text-accent">{{ episodeLabel }}</span>
            <h1 v-if="logo" class="leading-none">
              <img
                :src="logo"
                :alt="title"
                class="max-h-[clamp(5.5rem,15vw,11rem)] w-auto max-w-[min(100%,30rem)] lg:max-h-[clamp(10rem,16vw,15rem)] lg:max-w-[min(100%,36rem)] object-contain object-left drop-shadow-[0_6px_24px_rgba(0,0,0,0.5)]"
                @error="logoFailed = true"
              >
            </h1>
            <h1
              v-else
              class="text-balance font-extrabold"
              :class="isEpisode ? ['break-words tracking-[-0.03em]', episodeTitleClass(title)] : ['tracking-[-0.04em]', heroTitleClass(title)]"
            >
              {{ title }}
            </h1>
            <div class="flex flex-wrap items-center gap-x-[18px] gap-y-2 text-[15px] font-semibold text-ink-2">
              <span v-for="bit in metaBits" :key="bit">{{ bit }}</span>
              <span
                v-for="chip in chips"
                :key="chip"
                class="rounded bg-white/20 px-1.5 py-px text-xs font-extrabold text-ink"
              >{{ chip }}</span>
            </div>
            <!-- Phones: Play full width, then the rest as equal tiles. Wider: one row. -->
            <div
              class="grid gap-2 sm:flex sm:flex-wrap sm:items-center sm:gap-3"
              :class="playTarget && canResume(playTarget) ? 'grid-cols-3' : 'grid-cols-2'"
            >
              <PlayButton
                v-if="playLabel"
                class="col-span-full justify-center sm:justify-start"
                :label="playLabel"
                :detail="playTarget && canResume(playTarget) ? timeLeftLabel(playTarget) : null"
                :progress="progressPercent"
                @click="play(false)"
              />
              <!-- Episodes keep this and Watched as round icon buttons on wider screens, so the row fits beside the still -->
              <button
                v-if="playTarget && canResume(playTarget)"
                type="button"
                class="glass flex h-[60px] flex-col items-center justify-center gap-1 rounded-btn text-xs font-bold text-ink"
                :class="isEpisode
                  ? 'sm:size-[52px] sm:rounded-full'
                  : 'sm:h-[52px] sm:flex-row sm:gap-2 sm:rounded-full sm:pl-4 sm:pr-5 sm:text-[15px] sm:font-extrabold'"
                :aria-label="isEpisode ? 'Play from start' : undefined"
                @click="play(true)"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 1 0 3-6.7M3 4v5h5" /></svg>
                <span :class="isEpisode ? 'sm:hidden' : undefined" :aria-hidden="isEpisode ? 'true' : undefined">Play from start</span>
              </button>
              <button
                type="button"
                class="flex h-[60px] flex-col items-center justify-center gap-1 rounded-btn text-xs font-bold"
                :class="[
                  watched ? 'bg-ink text-canvas transition hover:bg-ink/80' : 'glass text-ink',
                  isEpisode
                    ? 'sm:size-[52px] sm:rounded-full'
                    : 'sm:h-[52px] sm:flex-row sm:gap-2 sm:rounded-full sm:pl-4 sm:pr-5 sm:text-[15px] sm:font-extrabold',
                ]"
                :aria-pressed="watched"
                :aria-label="isEpisode ? 'Watched' : seasonScoped && selectedSeason ? `${selectedSeason.name} watched` : undefined"
                @click="toggleWatched"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
                <span :class="isEpisode ? 'sm:hidden' : undefined" :aria-hidden="isEpisode ? 'true' : undefined">{{ watched ? 'Watched' : 'Mark as watched' }}</span>
              </button>
              <div ref="moreRef" class="relative">
                <button
                  type="button"
                  class="flex h-[60px] w-full flex-col items-center justify-center gap-1 rounded-btn text-xs font-bold sm:size-[52px] sm:rounded-full"
                  :class="moreOpen ? 'bg-ink text-canvas' : 'glass text-ink'"
                  aria-label="More actions"
                  aria-haspopup="menu"
                  :aria-expanded="moreOpen"
                  @click="moreOpen = !moreOpen"
                >
                  <svg class="size-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="2" /><circle cx="12" cy="12" r="2" /><circle cx="19" cy="12" r="2" /></svg>
                  <span class="sm:hidden" aria-hidden="true">More</span>
                </button>
                <div
                  v-if="moreOpen"
                  role="menu"
                  class="glass-strong absolute right-0 top-[calc(100%+10px)] z-20 flex min-w-[260px] flex-col whitespace-nowrap rounded-[18px] p-2 shadow-[0_20px_40px_rgba(0,0,0,0.5)] sm:left-0 sm:right-auto"
                >
                  <button
                    type="button"
                    role="menuitemcheckbox"
                    :aria-checked="favorite"
                    class="flex h-11 w-full items-center gap-3 rounded-[10px] px-3 text-left text-[15px] font-semibold hover:bg-white/10"
                    @click="toggleFavorite(); moreOpen = false"
                  >
                    <svg class="size-[18px]" :class="favorite ? 'text-accent' : 'text-ink'" viewBox="0 0 24 24" :fill="favorite ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" aria-hidden="true"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" /></svg>
                    {{ favorite ? 'Remove from Favourites' : 'Add to Favourites' }}
                  </button>
                  <button
                    v-if="seasonScoped"
                    type="button"
                    role="menuitemcheckbox"
                    :aria-checked="allWatched"
                    class="flex h-11 w-full items-center gap-3 rounded-[10px] px-3 text-left text-[15px] font-semibold hover:bg-white/10"
                    @click="toggleAllWatched"
                  >
                    <svg class="size-[18px]" :class="allWatched ? 'text-accent' : 'text-ink'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
                    {{ allWatched ? 'Mark all episodes as unwatched' : 'Mark all episodes as watched' }}
                  </button>
                  <button
                    v-if="trailer"
                    type="button"
                    role="menuitem"
                    class="flex h-11 w-full items-center gap-3 rounded-[10px] px-3 text-left text-[15px] font-semibold hover:bg-white/10"
                    @click="moreOpen = false; playTrailer()"
                  >
                    <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4" /></svg>
                    Trailer
                  </button>
                  <NuxtLink
                    v-if="item.type === 'Episode' && item.seriesId"
                    :to="`/item/${item.seriesId}`"
                    role="menuitem"
                    class="flex h-11 w-full items-center gap-3 rounded-[10px] px-3 text-[15px] font-semibold hover:bg-white/10"
                  >
                    <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>
                    Go to series
                  </NuxtLink>
                </div>
              </div>
            </div>
            <p v-if="actionError" class="text-sm font-semibold text-accent">
              {{ actionError }}
            </p>
            <template v-if="isEpisode">
              <TrackPickers
                v-model:audio="selectedAudio"
                v-model:subtitle="selectedSubtitle"
                v-model:quality="selectedQuality"
                :audio-streams="trackStreams.audio"
                :subtitle-streams="trackStreams.subtitles"
                :quality-options="qualityOptions"
              />
              <OverviewText
                v-if="item.overview"
                :id="`overview-${item.id}`"
                :key="item.id"
                :text="item.overview"
                :lines="4"
              />
              <dl
                v-if="episodeCredits.length"
                class="m-0 mt-1 grid grid-cols-[auto_minmax(0,1fr)] gap-x-[18px] gap-y-2 border-t border-elevated pt-4 text-sm leading-normal"
              >
                <template v-for="credit in episodeCredits" :key="credit.label">
                  <dt class="font-extrabold">
                    {{ credit.label }}
                  </dt>
                  <dd class="m-0 text-muted">
                    {{ credit.value }}
                  </dd>
                </template>
              </dl>
            </template>
          </div>

          <nav
            v-if="adjacentEpisodes.previous || adjacentEpisodes.next"
            aria-label="Previous and next episode"
            class="grid grid-cols-2 gap-3 self-start lg:col-start-1 lg:row-start-2"
          >
            <NuxtLink
              v-if="adjacentEpisodes.previous"
              :to="`/item/${adjacentEpisodes.previous.id}`"
              class="flex min-w-0 items-center gap-3 rounded-[14px] bg-surface p-2.5 transition hover:bg-elevated"
            >
              <svg class="size-[18px] shrink-0 text-muted" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
              <span class="relative hidden aspect-video w-20 shrink-0 overflow-hidden rounded-lg bg-elevated sm:block">
                <img v-if="imageUrl(adjacentEpisodes.previous, 'Primary', 240)" :src="imageUrl(adjacentEpisodes.previous, 'Primary', 240)!" alt="" class="absolute inset-0 size-full object-cover" loading="lazy">
              </span>
              <span class="flex min-w-0 flex-col gap-0.5">
                <span class="text-xs font-extrabold uppercase tracking-[0.5px] text-muted">Previous<template v-if="adjacentEpisodes.previous.indexNumber != null"> · E{{ adjacentEpisodes.previous.indexNumber }}</template></span>
                <span class="truncate text-[15px] font-extrabold">{{ adjacentEpisodes.previous.name }}</span>
              </span>
            </NuxtLink>
            <NuxtLink
              v-if="adjacentEpisodes.next"
              :to="`/item/${adjacentEpisodes.next.id}`"
              class="col-start-2 flex min-w-0 items-center justify-end gap-3 rounded-[14px] bg-surface p-2.5 text-right transition hover:bg-elevated"
            >
              <span class="flex min-w-0 flex-col gap-0.5">
                <span class="text-xs font-extrabold uppercase tracking-[0.5px] text-muted">Next<template v-if="adjacentEpisodes.next.indexNumber != null"> · E{{ adjacentEpisodes.next.indexNumber }}</template></span>
                <span class="truncate text-[15px] font-extrabold">{{ adjacentEpisodes.next.name }}</span>
              </span>
              <span class="relative hidden aspect-video w-20 shrink-0 overflow-hidden rounded-lg bg-elevated sm:block">
                <img v-if="imageUrl(adjacentEpisodes.next, 'Primary', 240)" :src="imageUrl(adjacentEpisodes.next, 'Primary', 240)!" alt="" class="absolute inset-0 size-full object-cover" loading="lazy">
              </span>
              <svg class="size-[18px] shrink-0 text-muted" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>
            </NuxtLink>
          </nav>
        </div>
      </section>

      <div class="flex flex-col gap-12">
        <!-- Track pickers and overview sit under the hero, so a long overview never pushes the title up -->
        <div
          v-if="!isEpisode && (trackStreams.audio.length || trackStreams.subtitles.length || item.overview || episodesError)"
          class="flex flex-col gap-4 px-4 sm:px-8 lg:px-12"
        >
          <TrackPickers
            v-model:audio="selectedAudio"
            v-model:subtitle="selectedSubtitle"
            v-model:quality="selectedQuality"
            :audio-streams="trackStreams.audio"
            :subtitle-streams="trackStreams.subtitles"
            :quality-options="qualityOptions"
          />
          <OverviewText
            v-if="item.overview"
            :id="`overview-${item.id}`"
            :key="item.id"
            class="max-w-[760px]"
            :text="item.overview"
          />
          <p v-if="episodesError" class="text-sm font-semibold text-accent">
            {{ episodesError }}
          </p>
        </div>

        <!-- The show an episode belongs to, kept small -->
        <aside
          v-if="series"
          aria-label="About the show"
          class="mx-4 flex flex-wrap items-center gap-x-10 gap-y-6 rounded-[18px] border border-elevated bg-surface/60 p-5 sm:mx-8 lg:mx-12"
        >
          <div class="flex min-w-0 flex-[1_1_420px] items-center gap-[18px]">
            <span class="relative h-36 w-24 shrink-0 overflow-hidden rounded-[10px] bg-elevated ring-1 ring-white/10">
              <img v-if="seriesPoster" :src="seriesPoster" alt="" class="absolute inset-0 size-full object-cover" loading="lazy">
            </span>
            <div class="flex min-w-0 flex-col gap-1.5">
              <span class="text-[13px] font-extrabold uppercase tracking-[0.5px] text-muted">From the show</span>
              <span class="text-[22px] font-extrabold tracking-[-0.4px]">{{ series.name }}</span>
              <span v-if="seriesMeta" class="text-sm font-semibold text-muted">{{ seriesMeta }}</span>
              <p v-if="series.overview" class="mt-1 line-clamp-3 max-w-[520px] text-sm leading-normal text-ink-2">
                {{ series.overview }}
              </p>
            </div>
          </div>
          <ul v-if="seriesCast.length" class="m-0 flex min-w-0 flex-[1_1_300px] list-none flex-wrap gap-x-6 gap-y-3.5 p-0">
            <li v-for="person in seriesCast" :key="person.id">
              <NuxtLink :to="{ path: '/search', query: { q: person.name, person: person.id } }" class="flex items-center gap-3">
                <span class="relative grid size-10 shrink-0 place-items-center overflow-hidden rounded-full bg-elevated text-sm font-extrabold text-ink-2">
                  <img
                    v-if="personImageUrl(person, 96)"
                    :src="personImageUrl(person, 96)!"
                    alt=""
                    class="absolute inset-0 size-full object-cover"
                    loading="lazy"
                  >
                  <template v-else>{{ initials(person.name) }}</template>
                </span>
                <span class="flex flex-col">
                  <span class="text-sm font-bold">{{ person.name }}</span>
                  <span v-if="person.role" class="text-[13px] text-muted">{{ person.role }}</span>
                </span>
              </NuxtLink>
            </li>
          </ul>
          <NuxtLink
            :to="itemRoute(series)"
            class="inline-flex h-11 shrink-0 items-center gap-2 rounded-full bg-elevated px-5 text-[15px] font-extrabold transition hover:bg-white/15"
          >
            Go to show
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>
          </NuxtLink>
        </aside>

        <!-- Episodes -->
        <section v-if="isSeries && seasons.length" id="episodes" aria-label="Episodes" class="flex scroll-mt-24 flex-col gap-4">
          <div class="flex flex-wrap items-center gap-2 px-4 sm:px-8 lg:px-12">
            <button
              v-for="season in seasons"
              :key="season.id"
              type="button"
              class="inline-flex h-[38px] items-center gap-1.5 rounded-full px-[18px] text-[15px] font-bold transition"
              :class="selectedSeasonId === season.id ? 'bg-ink text-canvas' : 'bg-surface text-ink-2 hover:bg-elevated'"
              :aria-pressed="selectedSeasonId === season.id"
              @click="selectSeason(season.id)"
            >
              <svg v-if="season.played" class="-ml-0.5 size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
              {{ season.name }}
              <span v-if="season.played" class="sr-only">(watched)</span>
            </button>
            <span v-if="episodes.length" class="ml-auto text-sm font-semibold text-muted">
              {{ watchedEpisodes }} of {{ episodes.length }} watched
            </span>
            <div v-if="episodes.length" class="hidden gap-2 sm:flex">
              <button
                type="button"
                class="glass grid size-9 place-items-center rounded-full text-ink disabled:opacity-30"
                :disabled="!railCanPrev"
                aria-label="Scroll back"
                @click="scrollRail(-1)"
              >
                <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
              </button>
              <button
                type="button"
                class="glass grid size-9 place-items-center rounded-full text-ink disabled:opacity-30"
                :disabled="!railCanNext"
                aria-label="Scroll forward"
                @click="scrollRail(1)"
              >
                <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>
              </button>
            </div>
          </div>
          <p v-if="!loadingEpisodes && !episodes.length" class="px-4 text-sm text-muted sm:px-8 lg:px-12">
            No episodes are available for this season.
          </p>
          <div
            v-else
            ref="episodeRail"
            class="rail flex snap-x scroll-px-4 gap-5 overflow-x-auto px-4 py-3 transition-opacity sm:scroll-px-8 sm:px-8 lg:scroll-px-12 lg:px-12"
            :class="loadingEpisodes ? 'opacity-50' : 'opacity-100'"
            @scroll.passive="syncRail"
          >
            <div
              v-for="ep in episodes"
              :key="ep.id"
              class="flex w-[min(80vw,340px)] shrink-0 snap-start flex-col gap-3"
            >
              <NuxtLink :to="watchRoute(ep)" class="group relative block" :aria-label="`Play ${ep.name}`">
                <MediaCard
                  :item="ep"
                  variant="landscape"
                  :highlighted="ep.id === nextUp?.id"
                  bare
                />
                <span class="pointer-events-none absolute inset-0 grid place-items-center opacity-0 transition duration-200 group-hover:opacity-100 group-focus-visible:opacity-100">
                  <span class="glass grid size-14 place-items-center rounded-full">
                    <svg class="ml-0.5 size-6" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
                  </span>
                </span>
              </NuxtLink>
              <div class="flex flex-col gap-1">
                <span class="text-[13px] font-bold uppercase tracking-[0.5px] text-muted">{{ episodeKicker(ep) }}</span>
                <TitleLink :to="`/item/${ep.id}`" class="text-[17px] font-extrabold">
                  {{ ep.name }}
                </TitleLink>
                <span v-if="ep.overview" class="line-clamp-2 text-sm leading-snug text-muted">{{ ep.overview }}</span>
              </div>
            </div>
          </div>
        </section>

        <!-- Collection contents -->
        <section v-if="isCollection && collectionItems.length" aria-label="In this collection" class="flex flex-col gap-4 px-4 sm:px-8 lg:px-12">
          <h2 class="text-xl font-extrabold tracking-[-0.5px] sm:text-2xl">
            In This Collection
          </h2>
          <div class="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-x-5 gap-y-8 sm:grid-cols-[repeat(auto-fill,minmax(176px,1fr))]">
            <MediaCard v-for="child in collectionItems" :key="child.id" :item="child" />
          </div>
        </section>

        <!-- Trailers and special features -->
        <MediaRow v-if="extras.length" title="Extras" :count="extras.length" wide>
          <template #default="{ slideClass }">
            <div v-for="extra in extras" :key="extra.id" :class="slideClass">
              <MediaCard
                :item="extra"
                variant="landscape"
                :kicker="extraLabel(extra)"
                :detail="runtimeLabel(extra.runTimeTicks)"
                :to="watchRoute(extra, true)"
                :title-to="watchRoute(extra, true)"
                play
              />
            </div>
          </template>
        </MediaRow>

        <!-- Cast & crew -->
        <section v-if="cast.length" aria-label="Cast and crew" class="flex flex-col gap-3.5">
          <h2 class="px-4 text-xl font-extrabold tracking-[-0.5px] sm:px-8 sm:text-2xl lg:px-12">
            Cast &amp; Crew
          </h2>
          <div class="rail flex gap-7 overflow-x-auto px-4 sm:px-8 lg:px-12">
            <NuxtLink
              v-for="person in cast"
              :key="`${person.id}-${person.role}`"
              :to="{ path: '/search', query: { q: person.name, person: person.id } }"
              class="flex w-[112px] shrink-0 flex-col items-center gap-2.5 text-center sm:w-32"
            >
              <span class="relative grid size-[112px] place-items-center overflow-hidden rounded-full bg-surface text-[32px] font-extrabold text-ink-2 sm:size-32">
                <img
                  v-if="personImageUrl(person)"
                  :src="personImageUrl(person)!"
                  :alt="person.name"
                  class="absolute inset-0 size-full object-cover"
                  loading="lazy"
                >
                <template v-else>{{ initials(person.name) }}</template>
              </span>
              <span class="flex flex-col gap-0.5">
                <span class="text-[15px] font-bold">{{ person.name }}</span>
                <span class="text-[13px] text-muted">{{ person.role || person.type }}</span>
              </span>
            </NuxtLink>
          </div>
        </section>

        <!-- Information -->
        <section
          v-if="information.length"
          aria-label="Information"
          class="mx-4 flex flex-col gap-5 border-t border-elevated pt-8 sm:mx-8 lg:mx-12"
        >
          <h2 class="text-xl font-extrabold tracking-[-0.5px] sm:text-2xl">
            Information
          </h2>
          <dl class="m-0 grid grid-cols-[repeat(auto-fill,minmax(240px,1fr))] gap-x-10 gap-y-6">
            <div v-for="entry in information" :key="entry.label" class="flex min-w-0 flex-col gap-1.5">
              <dt class="text-sm font-extrabold">
                {{ entry.label }}
              </dt>
              <dd
                v-if="entry.links?.length"
                class="m-0 flex flex-wrap gap-x-3 gap-y-1 text-sm leading-normal"
              >
                <a
                  v-for="link in entry.links"
                  :key="link.href"
                  :href="link.href"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="font-semibold text-muted underline-offset-2 hover:text-ink hover:underline"
                >
                  {{ link.label }}
                </a>
              </dd>
              <dd
                v-else
                class="m-0 whitespace-pre-line break-words text-sm leading-normal text-muted"
              >
                {{ entry.value }}
              </dd>
            </div>
          </dl>
        </section>

        <!-- Related -->
        <MediaRow v-if="!isEpisode" title="Related" :count="similar.length">
          <template #default="{ slideClass }">
            <div v-for="rel in similar" :key="rel.id" :class="slideClass">
              <MediaCard :item="rel" />
            </div>
          </template>
        </MediaRow>
      </div>
    </template>

    <Teleport to="body">
      <Transition
        enter-active-class="transition duration-200"
        leave-active-class="transition duration-150"
        enter-from-class="opacity-0"
        leave-to-class="opacity-0"
      >
        <div
          v-if="trailerEmbed"
          role="dialog"
          aria-modal="true"
          :aria-label="`${title} trailer`"
          class="fixed inset-0 z-50 grid place-items-center bg-black/85 p-4 backdrop-blur-sm sm:p-10"
          @click.self="trailerEmbed = null"
        >
          <button
            type="button"
            class="glass absolute right-4 top-4 grid size-12 place-items-center rounded-full sm:right-8 sm:top-6"
            aria-label="Close trailer"
            @click="trailerEmbed = null"
          >
            <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
          <iframe
            :src="trailerEmbed"
            :title="`${title} trailer`"
            class="aspect-video w-full max-w-6xl rounded-[18px] bg-black shadow-[0_40px_80px_rgba(0,0,0,0.6)]"
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
            allowfullscreen
          />
        </div>
      </Transition>
    </Teleport>
  </main>
</template>
