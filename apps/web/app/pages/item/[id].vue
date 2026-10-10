<script setup lang="ts">
import { keepPreviousData, useQuery } from '@tanstack/vue-query'
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
const episodesError = computed(() => episodesQuery.error.value?.message ?? '')
const watchedEpisodes = computed(() => episodes.value.filter(ep => ep.played).length)

/** Skeleton until everything that shapes the layout above the fold has arrived. */
const loading = computed(() => {
  if (itemQuery.isPending.value || similarQuery.isPending.value) return true
  if (isSeries.value) {
    if (seasonsQuery.isPending.value || nextUpQuery.isPending.value) return true
    if (selectedSeasonId.value && episodesQuery.isPending.value) return true
  }
  return isCollection.value && collectionQuery.isPending.value
})

const errorMessage = computed(() => {
  const error = itemQuery.error.value
  return error && !item.value ? error.message || 'Failed to load item' : ''
})

const moreOpen = ref(false)
const actionError = ref('')
/** Tracks picked here are handed to the player; null subtitle is off. */
const selectedAudio = ref<number | null>(null)
const selectedSubtitle = ref<number | null>(null)

// Per-title UI state resets on navigation, not when a refetch replaces the same title's data.
watch(itemId, () => {
  trailerEmbed.value = null
  pickedSeasonId.value = null
  moreOpen.value = false
  actionError.value = ''
})
// Pickers open on the tracks Settings prefers, falling back to the file's defaults.
watch(() => item.value?.id, () => {
  const value = item.value
  selectedAudio.value = value
    ? (preferredAudioStream(value, prefs.value.audioLanguage) ?? defaultAudioStream(value))?.index ?? null
    : null
  selectedSubtitle.value = value ? preferredSubtitleStream(value, prefs.value.subtitleLanguage)?.index ?? null : null
}, { immediate: true })

// A link to a season (?season=) scrolls to the episodes once they're on screen.
watch(loading, async (isLoading) => {
  if (isLoading || !requestedSeason.value) return
  await nextTick()
  document.getElementById('episodes')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}, { immediate: true })

const backdrop = computed(() => (item.value ? imageUrl(item.value, 'Backdrop', 1920) : null))

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

const kicker = computed(() => {
  const value = item.value
  if (!value) return ''
  if (isSeries.value) {
    const parts = ['Series']
    if (seasons.value.length) parts.push(`${seasons.value.length} Season${seasons.value.length === 1 ? '' : 's'}`)
    if (value.childCount) parts.push(`${value.childCount} Episodes`)
    return parts.join(' · ')
  }
  if (isCollection.value) return `Collection · ${collectionItems.value.length} titles`
  return value.type === 'Movie' ? 'Movie' : value.type
})

const title = computed(() => item.value?.name ?? '')

/** Series page with this episode's season selected. */
const seasonRoute = computed(() => {
  const value = item.value
  if (!value?.seriesId || !value.seasonId) return null
  return { path: `/item/${value.seriesId}`, query: { season: value.seasonId } }
})

const metaBits = computed(() => {
  const value = item.value
  if (!value) return []
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
  }
})

const cast = computed<JellyfinPerson[]>(() => (item.value?.people ?? []).slice(0, 20))

const information = computed(() => {
  const value = item.value
  if (!value) return []
  const streams = (playTarget.value?.mediaStreams?.length ? playTarget.value : value).mediaStreams ?? []
  const audio = streams.filter(s => s.type === 'Audio').map(s => s.displayTitle || s.language || s.codec)
  const subs = streams.filter(s => s.type === 'Subtitle').map(s => s.displayTitle || s.language || s.codec)
  const video = streams.find(s => s.type === 'Video')
  return [
    { label: 'Studio', value: value.studios?.join(', ') },
    { label: 'Released', value: yearLabel(value) },
    { label: 'Genres', value: value.genres?.join(', ') },
    { label: 'Rated', value: value.officialRating },
    { label: 'Runtime', value: runtimeLabel(value.runTimeTicks) },
    { label: 'Audio', value: audio.filter(Boolean).join('\n') },
    { label: 'Subtitles', value: subs.filter(Boolean).join(', ') },
    { label: 'Video', value: video?.displayTitle },
    { label: 'File', value: value.path },
  ].filter((entry): entry is { label: string, value: string } => Boolean(entry.value))
})

// Both toggles patch the cached item first, so these flip immediately.
const favorite = computed(() => Boolean(item.value?.isFavorite))
const watched = computed(() => Boolean(item.value?.played))

function toggleFavorite() {
  if (!item.value) return
  actionError.value = ''
  favoriteMutation.mutate({ id: item.value.id, value: !favorite.value }, {
    onError: () => { actionError.value = 'Could not update favourites' },
  })
}

function toggleWatched() {
  if (!item.value) return
  actionError.value = ''
  playedMutation.mutate({ id: item.value.id, value: !watched.value }, {
    onError: () => { actionError.value = 'Could not update watched state' },
  })
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
  return parts.filter(Boolean).join(' · ')
}

function selectSeason(seasonId: string) {
  pickedSeasonId.value = seasonId
}
</script>

<template>
  <main class="w-full pb-20">
    <div v-if="loading" aria-busy="true" aria-label="Loading title">
      <!-- Same box, padding and columns as the hero below -->
      <section class="relative min-h-[min(88vh,720px)] w-full overflow-hidden bg-surface/50">
        <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/55 via-35% to-transparent to-65%" />
        <div class="relative flex min-h-[min(88vh,720px)] flex-wrap items-end justify-between gap-8 px-4 pb-14 pt-32 sm:px-8 lg:px-12">
          <div class="flex w-full max-w-[820px] flex-col gap-4">
            <span class="text-sm font-bold"><span class="inline-block h-[0.8em] w-36 animate-pulse rounded bg-elevated align-middle" /></span>
            <span class="block h-[calc(clamp(2.75rem,7.5vw,6.5rem)*0.9)] w-2/3 animate-pulse rounded-btn bg-elevated" />
            <div class="flex items-center gap-3">
              <span class="h-[52px] w-44 animate-pulse rounded-btn bg-elevated" />
              <span class="size-[52px] animate-pulse rounded-full bg-elevated" />
              <span class="size-[52px] animate-pulse rounded-full bg-elevated" />
            </div>
          </div>
          <div class="flex w-full max-w-[420px] flex-col gap-3">
            <span class="flex flex-col text-base leading-relaxed">
              <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
              <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
              <span><span class="inline-block h-[0.8em] w-2/3 animate-pulse rounded bg-elevated align-middle" /></span>
            </span>
            <span class="text-sm font-semibold"><span class="inline-block h-[0.8em] w-52 animate-pulse rounded bg-elevated align-middle" /></span>
          </div>
        </div>
      </section>
      <div class="flex flex-col gap-12 pt-2">
        <MediaRow title="Related" :count="8">
          <template #default="{ slideClass }">
            <div v-for="n in 8" :key="n" :class="slideClass">
              <MediaCardSkeleton />
            </div>
          </template>
        </MediaRow>
      </div>
    </div>
    <p v-else-if="errorMessage && !item" class="px-4 pt-32 font-semibold text-accent sm:px-8 lg:px-12">
      {{ errorMessage }}
    </p>
    <template v-else-if="item">
      <!-- Hero -->
      <section :aria-label="title" class="relative min-h-[min(88vh,720px)] w-full overflow-hidden">
        <div class="absolute inset-0 bg-surface">
          <img v-if="backdrop" :src="backdrop" alt="" class="absolute inset-0 size-full object-cover object-top">
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/55 via-35% to-transparent to-65%" />
        <div class="absolute inset-0 bg-gradient-to-r from-canvas/70 via-transparent via-50% to-transparent" />

        <div class="relative flex min-h-[min(88vh,720px)] flex-wrap items-end justify-between gap-8 px-4 pb-14 pt-32 sm:px-8 lg:px-12">
          <div class="flex max-w-[820px] flex-col gap-4">
            <template v-if="item.type === 'Episode'">
              <div class="flex flex-col gap-1.5">
                <TitleLink
                  v-if="item.seriesId"
                  :to="`/item/${item.seriesId}`"
                  class="text-xl font-extrabold tracking-[-0.3px] text-ink sm:text-2xl"
                >
                  {{ item.seriesName }}
                </TitleLink>
                <span v-else-if="item.seriesName" class="text-xl font-extrabold tracking-[-0.3px] sm:text-2xl">{{ item.seriesName }}</span>
                <span class="flex items-center gap-2 text-[15px] font-bold text-ink-2">
                  <template v-if="item.parentIndexNumber != null">
                    <NuxtLink
                      v-if="seasonRoute"
                      :to="seasonRoute"
                      class="underline decoration-ink-2/40 underline-offset-4 transition hover:text-ink hover:decoration-ink"
                    >
                      Season {{ item.parentIndexNumber }}
                    </NuxtLink>
                    <span v-else>Season {{ item.parentIndexNumber }}</span>
                  </template>
                  <span v-if="item.parentIndexNumber != null && item.indexNumber != null" aria-hidden="true">·</span>
                  <span v-if="item.indexNumber != null">Episode {{ item.indexNumber }}</span>
                </span>
              </div>
            </template>
            <span v-else class="text-sm font-bold text-ink-2">{{ kicker }}</span>
            <h1 class="text-balance font-extrabold tracking-[-0.04em]" :class="heroTitleClass(title)">
              {{ title }}
            </h1>
            <div class="flex flex-wrap items-center gap-3">
              <button
                v-if="playLabel"
                type="button"
                class="inline-flex h-[52px] items-center gap-2.5 rounded-btn bg-ink px-[30px] text-[17px] font-extrabold text-canvas transition hover:bg-ink/80"
                @click="play(false)"
              >
                <svg class="size-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
                {{ playLabel }}
              </button>
              <button
                v-if="trailer"
                type="button"
                class="glass inline-flex h-[52px] items-center gap-2.5 rounded-btn px-6 text-[17px] font-extrabold text-ink transition hover:bg-white/15"
                @click="playTrailer"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4" /></svg>
                Trailer
              </button>
              <button
                type="button"
                class="glass grid size-[52px] place-items-center rounded-full text-ink"
                :aria-label="favorite ? 'Remove from favourites' : 'Add to favourites'"
                :aria-pressed="favorite"
                @click="toggleFavorite"
              >
                <svg class="size-5" viewBox="0 0 24 24" :fill="favorite ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" aria-hidden="true"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" /></svg>
              </button>
              <button
                type="button"
                class="grid size-[52px] place-items-center rounded-full"
                :class="watched ? 'bg-ink text-canvas transition hover:bg-ink/80' : 'glass text-ink'"
                :aria-label="watched ? 'Mark as unwatched' : 'Mark as watched'"
                :aria-pressed="watched"
                @click="toggleWatched"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
              </button>
              <div v-if="playTarget && canResume(playTarget)" class="relative">
                <button
                  type="button"
                  class="glass grid size-[52px] place-items-center rounded-full text-ink"
                  aria-label="More actions"
                  aria-haspopup="menu"
                  :aria-expanded="moreOpen"
                  @click="moreOpen = !moreOpen"
                >
                  <svg class="size-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="2" /><circle cx="12" cy="12" r="2" /><circle cx="19" cy="12" r="2" /></svg>
                </button>
                <div v-if="moreOpen" role="menu" class="glass-strong absolute left-0 top-[calc(100%+10px)] z-10 w-56 rounded-[18px] p-2">
                  <button
                    type="button"
                    role="menuitem"
                    class="flex h-11 w-full items-center rounded-[10px] px-3 text-left text-[15px] font-semibold hover:bg-white/10"
                    @click="play(true)"
                  >
                    Play from start
                  </button>
                </div>
              </div>
            </div>
            <div
              v-if="trackStreams.audio.length > 1 || trackStreams.subtitles.length"
              class="flex flex-wrap items-center gap-2"
            >
              <SelectMenu
                v-if="trackStreams.audio.length > 1"
                v-model="selectedAudio"
                label="Audio"
                :options="trackStreams.audio.map(stream => ({ value: stream.index, label: streamLabel(stream) }))"
              >
                <template #icon>
                  <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4z" /><path d="M15.5 8.5a5 5 0 0 1 0 7" /><path d="M18.5 5.5a9 9 0 0 1 0 13" /></svg>
                </template>
              </SelectMenu>
              <SelectMenu
                v-if="trackStreams.subtitles.length"
                v-model="selectedSubtitle"
                label="Subtitles"
                :options="[
                  { value: null, label: 'Subtitles off' },
                  ...trackStreams.subtitles.map(stream => ({ value: stream.index, label: streamLabel(stream) })),
                ]"
              >
                <template #icon>
                  <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3" /><path d="M7 15h4M14 15h3M7 11h2M12 11h5" /></svg>
                </template>
              </SelectMenu>
            </div>
            <div v-if="progressPercent" class="flex w-80 max-w-full items-center gap-3 text-sm font-semibold text-ink-2">
              <span class="h-1 flex-1 overflow-hidden rounded-full bg-white/30">
                <span class="block h-full rounded-full bg-accent" :style="{ width: `${progressPercent}%` }" />
              </span>
              {{ timeLeftLabel(playTarget!) }}
            </div>
            <p v-if="actionError || episodesError" class="text-sm font-semibold text-accent">
              {{ actionError || episodesError }}
            </p>
          </div>

          <div class="flex max-w-[420px] flex-col gap-3">
            <p v-if="item.overview" class="line-clamp-6 text-base leading-relaxed text-ink-2">
              {{ item.overview }}
            </p>
            <div class="flex flex-wrap items-center gap-2 text-sm font-semibold text-muted">
              <template v-for="(bit, i) in metaBits" :key="bit">
                <span v-if="i" aria-hidden="true">·</span>
                <span>{{ bit }}</span>
              </template>
              <span
                v-for="chip in chips"
                :key="chip"
                class="rounded bg-white/20 px-1.5 py-px text-xs font-extrabold text-ink"
              >{{ chip }}</span>
            </div>
          </div>
        </div>
      </section>

      <div class="flex flex-col gap-12 pt-2">
        <!-- Episodes -->
        <section v-if="isSeries && seasons.length" id="episodes" aria-label="Episodes" class="flex scroll-mt-24 flex-col gap-4">
          <div class="flex flex-wrap items-center gap-2 px-4 sm:px-8 lg:px-12">
            <button
              v-for="season in seasons"
              :key="season.id"
              type="button"
              class="h-[38px] rounded-full px-[18px] text-[15px] font-bold transition"
              :class="selectedSeasonId === season.id ? 'bg-ink text-canvas' : 'bg-surface text-ink-2 hover:bg-elevated'"
              :aria-pressed="selectedSeasonId === season.id"
              @click="selectSeason(season.id)"
            >
              {{ season.name }}
            </button>
            <span v-if="episodes.length" class="ml-auto text-sm font-semibold text-muted">
              {{ watchedEpisodes }} of {{ episodes.length }} watched
            </span>
          </div>
          <p v-if="!loadingEpisodes && !episodes.length" class="px-4 text-sm text-muted sm:px-8 lg:px-12">
            No episodes are available for this season.
          </p>
          <div
            v-else
            class="rail flex snap-x scroll-px-4 gap-5 overflow-x-auto px-4 py-3 transition-opacity sm:scroll-px-8 sm:px-8 lg:scroll-px-12 lg:px-12"
            :class="loadingEpisodes ? 'opacity-50' : 'opacity-100'"
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
              <dd class="m-0 whitespace-pre-line break-words text-sm leading-normal text-muted">
                {{ entry.value }}
              </dd>
            </div>
          </dl>
        </section>

        <!-- Related -->
        <MediaRow title="Related" :count="similar.length">
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
