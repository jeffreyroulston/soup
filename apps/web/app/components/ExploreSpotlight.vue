<script setup lang="ts">
import type { SeerrTitle } from '~/types/seerr'

/**
 * A few titles the library doesn't have, one at a time on a big backdrop, so Explore opens
 * on something to discover rather than a chart. Movies request in place; shows go to their
 * page to pick seasons.
 */
const props = defineProps<{
  titles: SeerrTitle[]
  loading?: boolean
}>()

const seerr = useSeerrStatus()

const AUTO_ADVANCE_MS = 8000
const index = ref(0)
const paused = ref(false)
let timer: ReturnType<typeof setInterval> | null = null

const current = computed(() => props.titles[index.value] ?? null)
const backdrop = computed(() => tmdbImage(current.value?.backdropPath, 'backdrop'))
const poster = computed(() => tmdbImage(current.value?.posterPath, 'poster'))
const href = computed(() => (current.value ? seerrTitleRoute(current.value) : '/explore'))

const metaBits = computed(() => {
  const title = current.value
  if (!title) return []
  return [
    mediaTypeLabel(title.mediaType),
    title.year ? String(title.year) : null,
    title.voteAverage ? `★ ${title.voteAverage.toFixed(1)}` : null,
  ].filter((bit): bit is string => Boolean(bit))
})

const requestMutation = useSeerrRequestMutation()
/** Set once the library knows about the title, e.g. right after requesting it here. */
const status = computed(() => availabilityLabel(current.value?.mediaInfo))
const canRequest = computed(() => current.value != null && seerr.canRequest(current.value.mediaType))
const requestError = computed(() => {
  const error = requestMutation.error.value
  return error instanceof Error ? error.message : null
})

function request() {
  const title = current.value
  if (!title || title.mediaType !== 'movie') return
  requestMutation.mutate({ mediaType: 'movie', mediaId: title.tmdbId })
}

function go(step: number) {
  const count = props.titles.length
  if (!count) return
  index.value = (index.value + step + count) % count
  restart()
}

function goTo(i: number) {
  index.value = i
  restart()
}

function restart() {
  if (timer) clearInterval(timer)
  timer = null
  requestMutation.reset()
  if (props.titles.length < 2) return
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
  timer = setInterval(() => {
    if (!paused.value && document.visibilityState === 'visible') {
      index.value = (index.value + 1) % props.titles.length
      requestMutation.reset()
    }
  }, AUTO_ADVANCE_MS)
}

watch(() => props.titles.length, () => {
  if (index.value >= props.titles.length) index.value = 0
  restart()
})

onMounted(restart)
onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <div class="px-4 sm:px-8 lg:px-12">
    <section
      v-if="loading"
      aria-hidden="true"
      class="relative h-[min(62vh,560px)] min-h-[420px] w-full animate-pulse overflow-hidden rounded-panel bg-surface"
    />
    <section
      v-else-if="current"
      aria-roledescription="carousel"
      aria-label="Spotlight"
      class="relative h-[min(62vh,560px)] min-h-[420px] w-full overflow-hidden rounded-panel bg-surface"
      @mouseenter="paused = true"
      @mouseleave="paused = false"
      @focusin="paused = true"
      @focusout="paused = false"
    >
      <Transition
        enter-active-class="transition-opacity duration-700"
        leave-active-class="transition-opacity duration-700 absolute inset-0"
        enter-from-class="opacity-0"
        leave-to-class="opacity-0"
      >
        <div :key="`${current.mediaType}-${current.tmdbId}`" class="absolute inset-0">
          <img v-if="backdrop" :src="backdrop" alt="" class="absolute inset-0 size-full object-cover object-top">
          <img v-else-if="poster" :src="poster" alt="" class="absolute inset-0 size-full scale-110 object-cover opacity-50 blur-2xl">
        </div>
      </Transition>
      <div class="absolute inset-0 bg-gradient-to-t from-canvas/95 via-canvas/50 via-35% to-transparent to-70%" />
      <div class="absolute inset-0 bg-gradient-to-r from-canvas/80 via-canvas/20 via-50% to-transparent" />

      <div class="absolute inset-x-5 bottom-6 flex flex-wrap items-end justify-between gap-6 sm:inset-x-8 sm:bottom-8 lg:inset-x-10 lg:bottom-10">
        <div :key="`${current.mediaType}-${current.tmdbId}`" class="flex max-w-[560px] flex-col gap-3.5">
          <h2 class="text-balance text-[clamp(2.25rem,5vw,4rem)] font-extrabold leading-[0.95] tracking-[-0.04em]">
            <NuxtLink
              :to="href"
              class="underline decoration-transparent decoration-[0.05em] underline-offset-[0.12em] transition-[text-decoration-color] duration-200 hover:decoration-current focus-visible:decoration-current"
            >
              {{ current.title }}
            </NuxtLink>
          </h2>
          <div class="flex flex-wrap items-center gap-x-[18px] gap-y-2 text-[15px] font-semibold text-ink-2">
            <span v-for="bit in metaBits" :key="bit">{{ bit }}</span>
          </div>
          <p v-if="current.overview" class="line-clamp-3 text-[17px] leading-relaxed text-ink-2">
            {{ current.overview }}
          </p>
          <div class="mt-1 flex flex-wrap items-center gap-3">
            <span
              v-if="status"
              class="inline-flex h-[52px] items-center gap-2 rounded-full bg-white/10 px-6 text-[17px] font-extrabold text-ink"
            >
              <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
              {{ status }}
            </span>
            <template v-else-if="canRequest">
              <button
                v-if="current.mediaType === 'movie'"
                type="button"
                class="inline-flex h-[52px] items-center gap-2 rounded-full bg-accent px-7 text-[17px] font-extrabold text-canvas transition hover:bg-accent/90 disabled:opacity-70"
                :disabled="requestMutation.isPending.value"
                @click="request"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
                {{ requestMutation.isPending.value ? 'Requesting…' : 'Request' }}
              </button>
              <NuxtLink
                v-else
                :to="href"
                class="inline-flex h-[52px] items-center gap-2 rounded-full bg-accent px-7 text-[17px] font-extrabold text-canvas transition hover:bg-accent/90"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
                Request seasons
              </NuxtLink>
            </template>
            <NuxtLink :to="href" class="glass inline-flex h-[52px] items-center rounded-full px-6 text-[17px] font-bold text-ink">
              Details
            </NuxtLink>
          </div>
          <p v-if="requestError" role="alert" class="text-[15px] font-semibold text-accent">
            {{ requestError }}
          </p>
        </div>

        <div v-if="titles.length > 1" class="flex flex-col items-end gap-4">
          <div class="hidden gap-2 sm:flex">
            <button type="button" class="glass grid size-11 place-items-center rounded-full text-ink" aria-label="Previous title" @click="go(-1)">
              <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
            </button>
            <button type="button" class="glass grid size-11 place-items-center rounded-full text-ink" aria-label="Next title" @click="go(1)">
              <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>
            </button>
          </div>
          <div class="flex items-center gap-1.5">
            <button
              v-for="(title, i) in titles"
              :key="`${title.mediaType}-${title.tmdbId}`"
              type="button"
              class="h-2 rounded-full transition-all"
              :class="i === index ? 'w-7 bg-ink' : 'w-2 bg-white/35 hover:bg-white/60'"
              :aria-label="`Show ${title.title}`"
              :aria-current="i === index ? 'true' : undefined"
              @click="goTo(i)"
            />
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
