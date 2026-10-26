<script setup lang="ts">
import { useQueryClient } from '@tanstack/vue-query'
import type { JellyfinItem, JellyfinPlaybackPlan } from '~/types/jellyfin'

definePageMeta({
  middleware: 'auth',
  layout: false,
  key: route => route.fullPath,
})

const route = useRoute()
const router = useRouter()
const queryClient = useQueryClient()
const queries = useJellyfinQueries()
const { getPlaybackPlan, getHlsPlaybackPlan } = usePlayback()
const { prefs } = usePlaybackPrefs()

const itemId = computed(() => String(route.params.id))
const item = ref<JellyfinItem | null>(null)
const plan = ref<JellyfinPlaybackPlan | null>(null)
const episodes = ref<JellyfinItem[]>([])
const errorMessage = ref('')
const loading = ref(true)
const tracks = trackChoiceFromQuery(route.query)
const initialSubtitleIndex = ref<number | null>(null)

const title = computed(() => item.value?.seriesName || item.value?.name || '')

const subtitle = computed(() => {
  const value = item.value
  if (!value || value.type !== 'Episode') return ''
  const code = episodeCode(value)
  return code ? `${code} · ${value.name}` : value.name
})

const nextEpisode = computed(() => {
  const index = episodes.value.findIndex(ep => ep.id === itemId.value)
  return index >= 0 ? episodes.value[index + 1] ?? null : null
})

/**
 * Starts with the tracks and quality picked on the detail page, else the ones Settings prefers.
 * A non-default audio track, an image subtitle or a quality cap needs Jellyfin to
 * transcode; text subtitles load in the player.
 */
async function loadPlan(value: JellyfinItem, startTicks: number): Promise<JellyfinPlaybackPlan> {
  const streams = value.mediaStreams ?? []
  const audio = tracks.audioStreamIndex !== undefined
    ? streams.find(s => s.type === 'Audio' && s.index === tracks.audioStreamIndex)
    : preferredAudioStream(value, prefs.value.audioLanguage)
  const subtitle = tracks.subtitleStreamIndex !== undefined
    ? streams.find(s => s.type === 'Subtitle' && s.index === tracks.subtitleStreamIndex)
    : preferredSubtitleStream(value, prefs.value.subtitleLanguage)
  initialSubtitleIndex.value = subtitle?.isTextSubtitle ? subtitle.index : null
  const audioIndex = audio && audio.index !== defaultAudioStream(value)?.index ? audio.index : null
  const burnedIndex = subtitle && !subtitle.isTextSubtitle ? subtitle.index : null
  const maxBitrate = tracks.maxBitrate !== undefined ? tracks.maxBitrate : prefs.value.maxBitrate
  if (audioIndex == null && burnedIndex == null && maxBitrate == null) return getPlaybackPlan(value.id, startTicks)
  try {
    return await getHlsPlaybackPlan(value.id, startTicks, {
      audioStreamIndex: audioIndex,
      subtitleStreamIndex: burnedIndex,
      maxBitrate,
    })
  }
  catch {
    // Fall back to the default tracks rather than failing playback outright.
    return getPlaybackPlan(value.id, startTicks)
  }
}

onMounted(async () => {
  try {
    // From the cache when the title page just loaded it.
    item.value = await queryClient.fetchQuery(queries.item(itemId.value))
    const queryTicks = Number(route.query.ticks ?? 0)
    const resumeTicks = Number.isFinite(queryTicks) && queryTicks > 0
      ? queryTicks
      : (route.query.ticks === '0' ? 0 : (item.value.playbackPositionTicks ?? 0))
    const startTicks = resumeTicks >= 100_000_000 ? resumeTicks : 0
    const [loadedPlan, seasonEpisodes] = await Promise.all([
      loadPlan(item.value, startTicks),
      item.value.type === 'Episode' && item.value.seriesId
        ? queryClient.fetchQuery(queries.episodes(item.value.seriesId, item.value.seasonId ?? null))
            .catch((): JellyfinItem[] => [])
        : Promise.resolve([]),
    ])
    plan.value = loadedPlan
    episodes.value = seasonEpisodes
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : 'Could not start playback'
  }
  finally {
    loading.value = false
  }
})

// Progress, Continue Watching and Next Up all moved; refresh whatever the next page shows.
onBeforeUnmount(() => {
  void queryClient.invalidateQueries({ queryKey: queryKeys.all })
})

// The player fullscreens the page so the next episode stays fullscreen; leaving playback ends it.
onBeforeRouteLeave((to) => {
  if (!to.path.startsWith('/watch/') && document.fullscreenElement) void document.exitFullscreen()
})

function detailPath() {
  const value = item.value
  return value?.type === 'Episode' && value.seriesId ? `/item/${value.seriesId}` : `/item/${itemId.value}`
}

function onClose() {
  // A trailer or special feature returns to the title it was opened from.
  if (item.value?.extraType && window.history.state?.back) {
    router.back()
    return
  }
  void router.push(detailPath())
}

function playEpisode(episode: JellyfinItem) {
  void router.replace(watchRoute(episode, episode.played))
}

function onNext() {
  if (nextEpisode.value) playEpisode(nextEpisode.value)
  else onClose()
}
</script>

<template>
  <div class="fixed inset-0 z-40 bg-black">
    <div
      v-if="loading"
      class="flex h-full items-center justify-center"
    >
      <p class="glass-strong rounded-full px-5 py-2.5 text-sm font-bold text-ink">
        Preparing playback…
      </p>
    </div>
    <div
      v-else-if="errorMessage && !plan"
      class="flex h-full flex-col items-center justify-center gap-4 px-6 text-center"
    >
      <p class="font-semibold text-accent">
        {{ errorMessage }}
      </p>
      <button
        type="button"
        class="h-11 rounded-full bg-white/10 px-5 text-sm font-bold text-ink hover:bg-white/15"
        @click="onClose"
      >
        Back
      </button>
    </div>
    <VideoPlayer
      v-else-if="plan && item"
      :plan="plan"
      :item="item"
      :title="title"
      :subtitle="subtitle"
      :episodes="episodes"
      :next-episode="nextEpisode"
      :initial-subtitle-index="initialSubtitleIndex"
      @ended="onClose"
      @close="onClose"
      @next="onNext"
      @play-episode="playEpisode"
      @error="(message) => { errorMessage = message }"
    />
  </div>
</template>
