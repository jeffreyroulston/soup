<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { LibrarySort } from '~/composables/useJellyfin'
import { countGenres } from '~/utils/media'

definePageMeta({ middleware: 'auth', layout: 'app' })

type Filter = 'all' | 'unwatched' | 'inProgress' | 'favorites'

const LETTERS = '#ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')
const GENRE_TINTS = ['#2541C8', '#3A0F2A', '#16353A', '#5A3B22', '#1F1A2E', '#2E5E3B', '#8A2A1E', '#3A3F48']
const SORTS: { value: LibrarySort, label: string }[] = [
  { value: 'SortName', label: 'Title' },
  { value: 'DateCreated', label: 'Recently Added' },
  { value: 'ProductionYear', label: 'Year' },
  { value: 'CommunityRating', label: 'Rating' },
]
const FILTERS: { value: Filter, label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'unwatched', label: 'Unwatched' },
  { value: 'inProgress', label: 'In Progress' },
  { value: 'favorites', label: 'Favourites' },
]

const route = useRoute()
const queries = useJellyfinQueries()
const { libraries, loaded: librariesLoaded } = useLibraries()

const sortBy = ref<LibrarySort>('SortName')
const filter = ref<Filter>('all')
const genre = ref<string | null>(null)
const activeLetter = ref<string | null>(null)
/** Last letter whose section starts on screen; the highlight spans activeLetter → this. */
const lastVisibleLetter = ref<string | null>(null)
const indexRef = ref<HTMLElement | null>(null)
const letterRefs: HTMLElement[] = []
/** Highlight pill geometry, relative to the strip. */
const highlight = ref<{ top: number, height: number, size: number } | null>(null)
/** A–Z strip height: from its on-screen top down to 24px above the viewport bottom. */
const indexHeight = ref<number | null>(null)

const libraryId = computed(() => String(route.params.id))
const knownLibrary = computed(() => libraries.value.find(lib => lib.id === libraryId.value) ?? null)
/** `boxsets` for Jellyfin's Collections view; wait for the library list so it's known. */
const collectionType = computed(() => knownLibrary.value?.collectionType ?? null)

const itemsQuery = useQuery(computed(() => ({
  ...queries.libraryItems(libraryId.value, sortBy.value, collectionType.value),
  enabled: librariesLoaded.value,
  // A new sort keeps the current grid on screen (dimmed); a new library starts empty.
  placeholderData: <T>(previous: T | undefined, previousQuery?: { queryKey: readonly unknown[] }) =>
    previousQuery?.queryKey[2] === libraryId.value ? previous : undefined,
})))
/** Fast count and genre queries; their results show before the full list arrives. */
const totalQuery = useQuery(computed(() => ({
  ...queries.libraryTotal(libraryId.value, collectionType.value),
  enabled: librariesLoaded.value,
})))
const genresQuery = useQuery(computed(() => ({
  ...queries.libraryGenres(libraryId.value, collectionType.value),
  enabled: librariesLoaded.value,
})))

// Only when the nav's library list doesn't have it (e.g. a collection folder opened directly).
const nameQuery = useQuery(computed(() => ({ ...queries.item(libraryId.value), enabled: !knownLibrary.value })))

const items = computed(() => itemsQuery.data.value ?? [])
const loading = computed(() => itemsQuery.isPending.value || itemsQuery.isPlaceholderData.value)
const total = computed(() => totalQuery.data.value ?? null)
const genreCounts = computed(() => genresQuery.data.value ?? (genresQuery.isError.value ? [] : null))
const libraryName = computed(() =>
  knownLibrary.value?.name ?? nameQuery.data.value?.name ?? (nameQuery.isError.value ? 'Library' : ''))
/** Only when there's nothing to show; a failed background refresh keeps the grid. */
const loadError = computed(() => (items.value.length ? null : itemsQuery.error.value))

const genres = computed(() => {
  const counts = items.value.length ? countGenres(items.value) : (genreCounts.value ?? [])
  return counts
    .slice(0, 12)
    .map((g, i) => ({ ...g, tint: GENRE_TINTS[i % GENRE_TINTS.length] }))
})

/** Genre tiles are known once either the genre query or the full list has loaded. */
const genresKnown = computed(() => items.value.length > 0 || genreCounts.value !== null || !loading.value)

/** Placeholder cards: the real count once known (capped; nothing below the fold can shift). */
const skeletonCount = computed(() => (total.value == null ? 18 : Math.min(total.value, 48)))

const countLabel = computed(() => {
  const noun = (n: number) => {
    const word = collectionType.value === 'boxsets' ? 'collection' : 'title'
    return n === 1 ? word : `${word}s`
  }
  if (!loading.value || items.value.length) {
    return visible.value.length === items.value.length
      ? `${items.value.length} ${noun(items.value.length)}`
      : `${visible.value.length} of ${items.value.length} ${noun(items.value.length)}`
  }
  return total.value == null ? null : `${total.value} ${noun(total.value)}`
})

const visible = computed(() => items.value.filter((item) => {
  if (genre.value && !item.genres?.includes(genre.value)) return false
  if (filter.value === 'unwatched') return !item.played
  if (filter.value === 'inProgress') return isInProgress(item)
  if (filter.value === 'favorites') return Boolean(item.isFavorite)
  return true
}))

// Shown while loading too, so the grid keeps the same width when items arrive.
const showIndex = computed(() => sortBy.value === 'SortName' && (loading.value || visible.value.length > 0))

/** First visible item for each letter, keyed by item id. */
const anchors = computed(() => {
  const byItem = new Map<string, string>()
  if (!showIndex.value) return byItem
  const seen = new Set<string>()
  for (const item of visible.value) {
    const letter = sortLetter(item)
    if (!seen.has(letter)) {
      seen.add(letter)
      byItem.set(item.id, letter)
    }
  }
  return byItem
})

const presentLetters = computed(() => new Set(anchors.value.values()))

const stagger = useStaggeredList(visible)

async function jumpTo(letter: string) {
  // The letter's first card may be in a chunk that hasn't rendered yet.
  if (!stagger.complete.value) {
    stagger.renderAll()
    await nextTick()
  }
  const el = document.getElementById(anchorId(letter))
  if (!el) return
  activeLetter.value = letter
  lastVisibleLetter.value = letter
  syncHighlight()
  el.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

function anchorId(letter: string) {
  return `letter-${letter === '#' ? 'num' : letter}`
}

/** Content above this (px from the viewport top) is hidden behind the top bar. */
const VISIBLE_TOP = 80

let frame = 0
function syncActiveLetter() {
  frame = 0
  syncIndexHeight()
  if (!showIndex.value) return
  const sections: { letter: string, el: HTMLElement }[] = []
  for (const letter of LETTERS) {
    if (!presentLetters.value.has(letter)) continue
    const el = document.getElementById(anchorId(letter))
    if (el) sections.push({ letter, el })
  }
  let current: string | null = null
  let last: string | null = null
  for (const [i, { letter, el }] of sections.entries()) {
    // Sections can share a grid row, so a letter is in view while its last card (the one
    // before the next letter's anchor) still shows below the top bar.
    const end = sections[i + 1]?.el.previousElementSibling ?? null
    const inView = !end || end.getBoundingClientRect().bottom > VISIBLE_TOP
    if (!current && inView) current = letter
    if (el.getBoundingClientRect().top < window.innerHeight) last = letter
  }
  activeLetter.value = current ?? [...presentLetters.value][0] ?? null
  lastVisibleLetter.value = last
  syncHighlight()
}

/** Indexes into LETTERS covered by the highlight, or null when there's nothing to show. */
const highlightRange = computed(() => {
  if (loading.value || !activeLetter.value) return null
  const start = LETTERS.indexOf(activeLetter.value)
  const end = lastVisibleLetter.value ? LETTERS.indexOf(lastVisibleLetter.value) : start
  return { start, end: Math.max(start, end) }
})

function inHighlight(letter: string) {
  const range = highlightRange.value
  if (!range) return false
  const i = LETTERS.indexOf(letter)
  return i >= range.start && i <= range.end
}

function syncHighlight() {
  const nav = indexRef.value
  const range = highlightRange.value
  const first = range && letterRefs[range.start]
  const last = range && letterRefs[range.end]
  if (!nav || !first || !last) {
    highlight.value = null
    return
  }
  const navTop = nav.getBoundingClientRect().top + nav.clientTop
  const a = first.getBoundingClientRect()
  const b = last.getBoundingClientRect()
  // Same size as a single letter's circle, so one letter in view is a perfect circle.
  const size = Math.min(a.height, 28)
  const top = a.top - navTop + (a.height - size) / 2
  const bottom = b.top - navTop + (b.height + size) / 2
  highlight.value = { top, height: bottom - top, size }
}

const INDEX_BOTTOM_GAP = 24
const INDEX_MIN_HEIGHT = 384
const INDEX_MAX_HEIGHT = 1024

function syncIndexHeight() {
  const nav = indexRef.value
  if (!nav) return
  const available = window.innerHeight - nav.getBoundingClientRect().top - INDEX_BOTTOM_GAP
  indexHeight.value = Math.round(Math.min(INDEX_MAX_HEIGHT, Math.max(INDEX_MIN_HEIGHT, available)))
}

function onScroll() {
  if (!frame) frame = requestAnimationFrame(syncActiveLetter)
}

watch(libraryId, () => {
  genre.value = null
  filter.value = 'all'
})

watch([libraryId, filter, genre], async () => {
  stagger.reset()
  await nextTick()
  syncActiveLetter()
})

watch(loading, async (isLoading) => {
  if (isLoading) return
  await nextTick()
  syncActiveLetter()
})

watch(showIndex, async () => {
  await nextTick()
  syncIndexHeight()
  syncHighlight()
})

watch(indexHeight, async () => {
  await nextTick()
  syncHighlight()
})

onMounted(() => {
  window.addEventListener('scroll', onScroll, { passive: true })
  window.addEventListener('resize', onScroll, { passive: true })
  syncIndexHeight()
})
onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScroll)
  window.removeEventListener('resize', onScroll)
  if (frame) cancelAnimationFrame(frame)
})
</script>

<template>
  <main class="w-full pb-20 pt-24 sm:pt-28">
    <div class="flex flex-wrap items-end justify-between gap-5 px-4 sm:px-8 lg:px-12">
      <div class="flex flex-col gap-1.5">
        <h1 class="text-[clamp(2.5rem,5vw,4rem)] font-extrabold leading-none tracking-[-0.04em]">
          {{ libraryName || 'Library' }}
        </h1>
        <span class="text-[15px] font-semibold text-muted">
          <template v-if="countLabel">{{ countLabel }}</template>
          <span v-else class="inline-block h-[0.8em] w-20 animate-pulse rounded bg-surface align-middle" />
        </span>
      </div>
      <div class="flex flex-wrap items-center gap-2.5">
        <div role="group" aria-label="Show" class="rail flex max-w-full gap-0.5 overflow-x-auto rounded-full bg-surface p-1">
          <button
            v-for="option in FILTERS"
            :key="option.value"
            type="button"
            class="h-9 shrink-0 whitespace-nowrap rounded-full px-4 text-sm font-bold transition"
            :class="filter === option.value ? 'bg-ink text-canvas' : 'text-ink-2 hover:text-ink'"
            :aria-pressed="filter === option.value"
            @click="filter = option.value"
          >
            {{ option.label }}
          </button>
        </div>
        <SelectMenu v-model="sortBy" label="Sort" prefix="Sort" tone="surface" :options="SORTS" />
      </div>
    </div>

    <div v-if="genres.length" class="rail mt-6 flex gap-3 overflow-x-auto px-4 sm:px-8 lg:px-12">
      <button
        v-for="g in genres"
        :key="g.name"
        type="button"
        class="flex h-[76px] w-[168px] shrink-0 flex-col justify-between rounded-card px-4 py-3.5 text-left text-white transition"
        :class="genre === g.name ? 'ring-2 ring-ink ring-offset-2 ring-offset-canvas' : 'opacity-90 hover:opacity-100'"
        :style="{ backgroundColor: g.tint }"
        :aria-pressed="genre === g.name"
        @click="genre = genre === g.name ? null : g.name"
      >
        <span class="truncate text-base font-extrabold">{{ g.name }}</span>
        <span class="text-xs font-bold opacity-80">{{ g.count }}</span>
      </button>
    </div>
    <div v-else-if="!genresKnown" aria-hidden="true" class="rail mt-6 flex gap-3 overflow-hidden px-4 sm:px-8 lg:px-12">
      <span v-for="n in 8" :key="n" class="h-[76px] w-[168px] shrink-0 animate-pulse rounded-card bg-surface" />
    </div>

    <div class="flex gap-6 px-4 pt-9 sm:px-8 lg:pl-12 lg:pr-5">
      <div class="min-w-0 flex-1">
        <div
          v-if="loading && !items.length"
          class="grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-x-5 gap-y-8 sm:grid-cols-[repeat(auto-fill,minmax(176px,1fr))]"
        >
          <div v-for="n in skeletonCount" :key="n">
            <MediaCardSkeleton />
          </div>
        </div>
        <ErrorState v-else-if="loadError" compact :error="loadError" :on-retry="itemsQuery.refetch" />
        <p v-else-if="!visible.length" class="text-muted">
          {{ items.length ? 'Nothing matches these filters.' : 'This library is empty.' }}
        </p>
        <div
          v-else
          class="grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-x-5 gap-y-8 transition-opacity sm:grid-cols-[repeat(auto-fill,minmax(176px,1fr))]"
          :class="loading ? 'opacity-50' : 'opacity-100'"
        >
          <div
            v-for="item in stagger.rendered.value"
            :id="anchors.has(item.id) ? anchorId(anchors.get(item.id)!) : undefined"
            :key="item.id"
            class="scroll-mt-28"
          >
            <MediaCard :item="item" />
          </div>
        </div>
      </div>

      <nav
        v-if="showIndex"
        aria-label="Jump to letter"
        ref="indexRef"
        class="glass sticky top-24 hidden h-[calc(100dvh-7.5rem)] max-h-[64rem] min-h-[24rem] w-9 shrink-0 flex-col items-center self-start rounded-full py-3 md:flex"
        :style="indexHeight ? { height: `${indexHeight}px` } : undefined"
      >
        <!-- Pill behind the letters, stretched over every section currently in view -->
        <span
          v-if="highlight"
          aria-hidden="true"
          class="pointer-events-none absolute left-1/2 -translate-x-1/2 rounded-full bg-ink transition-[top,height] duration-200 ease-out"
          :style="{ top: `${highlight.top}px`, height: `${highlight.height}px`, width: `${highlight.size}px` }"
        />
        <!-- Each letter takes an equal share of the full-height strip -->
        <button
          v-for="(letter, i) in LETTERS"
          :key="letter"
          :ref="el => { letterRefs[i] = el as HTMLElement }"
          type="button"
          class="group relative flex min-h-0 w-full flex-1 items-center justify-center disabled:cursor-default"
          :disabled="loading || !presentLetters.has(letter)"
          :aria-current="activeLetter === letter ? 'true' : undefined"
          :aria-label="`Jump to ${letter === '#' ? 'numbers' : letter}`"
          @click="jumpTo(letter)"
        >
          <span
            class="grid aspect-square h-full max-h-[28px] place-items-center rounded-full text-[13px] font-extrabold leading-none transition"
            :class="inHighlight(letter)
              ? presentLetters.has(letter) ? 'text-canvas' : 'text-canvas/40'
              : !loading && presentLetters.has(letter) ? 'text-ink group-hover:bg-white/15' : 'text-[#48484A]'"
          >
            {{ letter }}
          </span>
        </button>
      </nav>
    </div>
  </main>
</template>
