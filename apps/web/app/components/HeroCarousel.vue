<script setup lang="ts">
import type { JellyfinItem } from '~/types/jellyfin'

const props = defineProps<{
  items: JellyfinItem[]
  /** Item ids that came from Continue Watching. */
  resumeIds?: Set<string>
}>()

const { imageUrl } = useJellyfin()
const favoriteMutation = useFavoriteMutation()

const AUTO_ADVANCE_MS = 8000
const index = ref(0)
const paused = ref(false)
let timer: ReturnType<typeof setInterval> | null = null

const current = computed(() => props.items[index.value] ?? null)
const backdrop = computed(() => (current.value ? imageUrl(current.value, 'Backdrop', 1920) : null))

const kicker = computed(() => {
  const item = current.value
  if (!item) return ''
  const lead = props.resumeIds?.has(item.id) ? 'Continue Watching' : 'Recently Added'
  const genre = item.genres?.[0]
  return genre ? `${lead} · ${genre}` : lead
})

const title = computed(() => current.value?.seriesName || current.value?.name || '')

const metaBits = computed(() => {
  const item = current.value
  if (!item) return []
  return [item.genres?.slice(0, 2).join(', '), yearLabel(item), runtimeLabel(item.runTimeTicks)]
    .filter((bit): bit is string => Boolean(bit))
})

const chips = computed(() => {
  const item = current.value
  if (!item) return []
  return [item.officialRating, ...qualityBadges(item)].filter((chip): chip is string => Boolean(chip))
})

const primaryAction = computed(() => {
  const item = current.value
  if (!item) return null
  if (!isPlayable(item)) return { label: 'View', to: `/item/${item.id}` }
  const left = timeLeftLabel(item)
  return {
    label: left && canResume(item) ? `Resume · ${left}` : 'Play',
    to: watchRoute(item),
  }
})

// The mutation patches the cached home rows, so `items` already reflects a toggle.
const isFavorite = computed(() => Boolean(current.value?.isFavorite))

function toggleFavorite() {
  const item = current.value
  if (item) favoriteMutation.mutate({ id: item.id, value: !isFavorite.value })
}

function go(step: number) {
  const count = props.items.length
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
  if (props.items.length < 2) return
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
  timer = setInterval(() => {
    if (!paused.value && document.visibilityState === 'visible') {
      index.value = (index.value + 1) % props.items.length
    }
  }, AUTO_ADVANCE_MS)
}

watch(() => props.items.length, () => {
  if (index.value >= props.items.length) index.value = 0
  restart()
})

onMounted(restart)
onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <section
    v-if="current"
    aria-roledescription="carousel"
    aria-label="Featured"
    class="relative h-[min(88vh,780px)] min-h-[560px] w-full overflow-hidden"
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
      <div :key="current.id" class="absolute inset-0 bg-surface">
        <img
          v-if="backdrop"
          :src="backdrop"
          alt=""
          class="absolute inset-0 size-full object-cover object-top"
        >
      </div>
    </Transition>
    <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/60 via-30% to-transparent to-60%" />
    <div class="absolute inset-0 bg-gradient-to-r from-canvas/70 via-canvas/10 via-45% to-transparent" />

    <div class="absolute inset-x-4 bottom-10 flex flex-wrap items-end justify-between gap-6 sm:inset-x-8 sm:bottom-16 lg:inset-x-12 lg:bottom-[72px]">
      <div :key="current.id" class="flex max-w-[600px] flex-col gap-4">
        <span class="text-sm font-bold text-ink-2">{{ kicker }}</span>
        <h1 class="text-balance font-extrabold tracking-[-0.04em]" :class="heroTitleClass(title)">
          <!-- TitleLink's underline reveal, sized in em to suit the display type -->
          <NuxtLink
            :to="`/item/${current.seriesId || current.id}`"
            class="underline decoration-transparent decoration-[0.05em] underline-offset-[0.12em] transition-[text-decoration-color] duration-200 hover:decoration-current focus-visible:decoration-current"
          >
            {{ title }}
          </NuxtLink>
        </h1>
        <p v-if="current.type === 'Episode'" class="text-lg font-bold text-ink-2">
          <EpisodeLinks :item="current" /><template v-if="episodeCode(current)"> · </template>{{ current.name }}
        </p>
        <div class="flex flex-wrap items-center gap-2 text-[15px] font-semibold text-ink-2">
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
        <p v-if="current.overview" class="line-clamp-3 text-[17px] leading-relaxed text-ink-2">
          {{ current.overview }}
        </p>
        <div class="mt-1 flex items-center gap-3">
          <NuxtLink
            v-if="primaryAction"
            :to="primaryAction.to"
            class="inline-flex h-[52px] items-center gap-2.5 whitespace-nowrap rounded-btn bg-ink px-5 text-[17px] font-extrabold text-canvas transition hover:bg-ink/80 sm:px-[30px]"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
            {{ primaryAction.label }}
          </NuxtLink>
          <NuxtLink
            :to="`/item/${current.id}`"
            class="glass hidden h-[52px] items-center rounded-btn px-6 text-[17px] font-bold text-ink sm:inline-flex"
          >
            Details
          </NuxtLink>
          <button
            type="button"
            class="glass inline-flex h-[52px] items-center gap-2 whitespace-nowrap rounded-btn pl-5 pr-6 text-[17px] font-bold text-ink"
            :aria-pressed="isFavorite"
            @click="toggleFavorite"
          >
            <svg v-if="isFavorite" class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
            <svg v-else class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
            Favourite
          </button>
        </div>
      </div>

      <div v-if="items.length > 1" class="flex flex-col items-end gap-4">
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
            v-for="(item, i) in items"
            :key="item.id"
            type="button"
            class="h-2 rounded-full transition-all"
            :class="i === index ? 'w-7 bg-ink' : 'w-2 bg-white/35 hover:bg-white/60'"
            :aria-label="`Show ${item.seriesName || item.name}`"
            :aria-current="i === index ? 'true' : undefined"
            @click="goTo(i)"
          />
        </div>
      </div>
    </div>
  </section>
</template>
