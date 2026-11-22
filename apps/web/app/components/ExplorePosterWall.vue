<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { SeerrTitle } from '~/types/seerr'

/**
 * "Hidden gems": well-rated films with few votes, as a tilted wall of drifting posters (the
 * sign-in backdrop's look, but every poster is a title). A different TMDB page each day keeps
 * the batch fresh. "Surprise me" (or a poster) pulls one title forward in place, so skipping
 * to another is one click rather than a page and back.
 */
const queries = useSeerrQueries()
const router = useRouter()
const seerr = useSeerrStatus()

/** Seerr discover filters: liked, but not widely seen. */
const PARAMS = {
  sortBy: 'popularity.desc',
  voteAverageGte: '7.4',
  voteCountGte: '150',
  voteCountLte: '2500',
}
const PAGES = 5
const ROW_COUNT = 3
const TILES_PER_ROW = 12

const DAY = Math.floor(Date.now() / 86_400_000)
const page = ref(1 + (DAY % PAGES))

// Two pages (~40 titles) so each row can have its own posters.
const gemsQuery = useQuery(computed(() => queries.discover('discover/movies', page.value, PARAMS)))
const moreQuery = useQuery(computed(() => queries.discover('discover/movies', page.value + 1, PARAMS)))

// A short last page (or a server with fewer results) falls back to the first.
watch(() => gemsQuery.data.value, (data) => {
  if (data && !data.titles.length && page.value > 1) page.value = 1
})

const keyOf = (title: SeerrTitle) => `${title.mediaType}-${title.tmdbId}`

/** Both pages, first sighting of each title (TMDB pages can overlap as popularity shifts). */
const allTitles = computed(() => {
  const seenKeys = new Set<string>()
  return [...(gemsQuery.data.value?.titles ?? []), ...(moreQuery.data.value?.titles ?? [])].filter((title) => {
    const key = keyOf(title)
    if (seenKeys.has(key)) return false
    seenKeys.add(key)
    return true
  })
})

/** Titles the library doesn't have yet, unless that leaves too few to fill a wall. */
const titles = computed(() => {
  const all = allTitles.value.filter(title => title.posterPath)
  const fresh = all.filter(title => !availabilityLabel(title.mediaInfo))
  return fresh.length >= 18 ? fresh : all
})

/**
 * Titles are dealt round-robin into the rows, so no poster shows up in two rows; a row
 * repeats only its own titles if there aren't enough to fill it.
 */
const rows = computed(() => {
  const list = titles.value
  if (!list.length) return []
  return Array.from({ length: ROW_COUNT }, (_, r) => {
    let own = list.filter((_, i) => i % ROW_COUNT === r)
    if (!own.length) own = list
    const tiles: SeerrTitle[] = Array.from({ length: Math.max(TILES_PER_ROW, own.length) }, (_, i) => own[i % own.length]!)
    // Tiles render twice so translating by -50% loops seamlessly; the copy is hidden from AT.
    return { tiles: [...tiles, ...tiles], half: tiles.length, reverse: r % 2 === 1, duration: 110 + r * 20 }
  })
})

/** The title pulled forward, by key: its data follows the query, so a request here shows. */
const pickKey = ref<string | null>(null)
const pick = computed(() => {
  if (!pickKey.value) return null
  return allTitles.value.find(title => keyOf(title) === pickKey.value) ?? null
})
/** Titles already offered this session, so "Another" doesn't come back round to them early. */
const seen = useState<string[]>('explore-gems-seen', () => [])
/** Bumped on every pick, so the same title picked twice still replays the reveal. */
const revealCount = ref(0)

const surpriseButton = ref<HTMLButtonElement | null>(null)
const revealPanel = ref<HTMLElement | null>(null)

function show(title: SeerrTitle) {
  const key = keyOf(title)
  pickKey.value = key
  seen.value = [...seen.value.filter(entry => entry !== key), key]
  revealCount.value++
  requestMutation.reset()
  void nextTick(() => revealPanel.value?.focus())
}

function surprise() {
  const list = titles.value
  if (!list.length) return
  const offered = new Set(seen.value)
  let pool = list.filter(title => !offered.has(keyOf(title)))
  // Everything's been offered: start over, just not with the one on screen.
  if (!pool.length) {
    seen.value = pickKey.value ? [pickKey.value] : []
    pool = list.filter(title => keyOf(title) !== pickKey.value)
  }
  if (!pool.length) pool = list
  show(pool[Math.floor(Math.random() * pool.length)]!)
}

function close() {
  pickKey.value = null
  void nextTick(() => surpriseButton.value?.focus())
}

/** A wall poster reveals in place; modified clicks still open the page in a new tab. */
function onPoster(event: MouseEvent, title: SeerrTitle) {
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return
  event.preventDefault()
  show(title)
}

const pickHref = computed(() => (pick.value ? seerrTitleRoute(pick.value) : '/explore'))
const pickMeta = computed(() => {
  const title = pick.value
  if (!title) return []
  return [
    title.year ? String(title.year) : null,
    title.voteAverage ? `★ ${title.voteAverage.toFixed(1)}` : null,
    title.voteCount ? `${title.voteCount.toLocaleString()} votes` : null,
  ].filter((bit): bit is string => Boolean(bit))
})

const requestMutation = useSeerrRequestMutation()
const pickStatus = computed(() => availabilityLabel(pick.value?.mediaInfo))
const canRequest = computed(() => pick.value != null && seerr.canRequest(pick.value.mediaType))
const requestError = computed(() => {
  const error = requestMutation.error.value
  return error instanceof Error ? error.message : null
})

function request() {
  const title = pick.value
  if (!title || title.mediaType !== 'movie') return
  requestMutation.mutate({ mediaType: 'movie', mediaId: title.tmdbId })
}

/** While a title is out: → or Space for another, Enter for its page, Esc to put it back. */
function onKey(event: KeyboardEvent) {
  if (!pick.value || event.defaultPrevented || event.altKey || event.metaKey || event.ctrlKey) return
  const target = event.target
  const onControl = target instanceof Element && target.closest('button, a, input, textarea, select') != null
  if (event.key === 'Escape') {
    event.preventDefault()
    close()
  }
  else if (event.key === 'ArrowRight' || (event.key === ' ' && !onControl)) {
    event.preventDefault()
    surprise()
  }
  else if (event.key === 'Enter' && !onControl) {
    event.preventDefault()
    void router.push(pickHref.value)
  }
}

onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <section
    v-if="gemsQuery.isPending.value || rows.length"
    aria-label="Hidden gems"
    class="wall relative h-[520px] w-full overflow-hidden bg-canvas sm:h-[540px]"
    :class="{ 'wall--revealing': pick }"
  >
    <div v-if="gemsQuery.isPending.value" class="absolute inset-0 animate-pulse bg-surface/50" />
    <div
      v-else
      class="absolute -inset-x-24 -inset-y-16 flex -rotate-6 flex-col justify-center gap-4 transition duration-500"
      :class="pick ? 'scale-[1.02] opacity-40 blur-[3px]' : ''"
      :inert="pick != null || undefined"
    >
      <div
        v-for="(row, r) in rows"
        :key="r"
        class="wall-row flex w-max gap-4"
        :class="{ 'wall-row--reverse': row.reverse }"
        :style="{ animationDuration: `${row.duration}s` }"
      >
        <NuxtLink
          v-for="(title, i) in row.tiles"
          :key="i"
          :to="seerrTitleRoute(title)"
          :aria-label="title.title"
          :aria-hidden="i >= row.half || undefined"
          :tabindex="i >= row.half ? -1 : undefined"
          @click="onPoster($event, title)"
          class="block w-32 shrink-0 overflow-hidden rounded-card bg-surface opacity-75 shadow-[0_0_0_1px_rgba(255,255,255,0.06)] transition duration-300 hover:scale-105 hover:opacity-100 focus-visible:opacity-100 sm:w-40"
        >
          <img :src="tmdbImage(title.posterPath, 'poster')!" alt="" draggable="false" class="aspect-[2/3] w-full object-cover" loading="lazy">
        </NuxtLink>
      </div>
    </div>

    <!-- Copy sits on a wash: from the bottom on phones, from the left on wider screens -->
    <div class="pointer-events-none absolute inset-0 bg-gradient-to-t from-canvas via-canvas/80 via-35% to-transparent to-70% sm:bg-gradient-to-r sm:via-canvas/75 sm:via-30% sm:to-55%" />
    <div class="pointer-events-none absolute inset-x-0 top-0 h-16 bg-gradient-to-b from-canvas to-transparent" />
    <div class="pointer-events-none absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-canvas to-transparent" />

    <!-- Clicking the dimmed wall puts the title back -->
    <button v-if="pick" type="button" class="absolute inset-0 cursor-default" tabindex="-1" aria-hidden="true" @click="close" />

    <div
      v-show="!pick"
      class="absolute inset-x-4 bottom-8 flex max-w-[420px] flex-col gap-3 sm:inset-x-8 sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 lg:left-12"
    >
      <span class="text-sm font-extrabold uppercase tracking-[1px] text-accent">Hidden gems</span>
      <h2 class="text-[36px] font-extrabold leading-[0.95] tracking-[-1.5px] sm:text-[52px] sm:tracking-[-2px]">
        Loved by few
      </h2>
      <p class="text-[17px] leading-relaxed text-ink-2">
        Highly rated films most people haven't found yet.
      </p>
      <button
        ref="surpriseButton"
        type="button"
        class="mt-1 inline-flex h-[52px] w-fit items-center gap-2 rounded-full bg-ink px-7 text-[17px] font-extrabold text-canvas transition hover:bg-ink/85 disabled:opacity-60"
        :disabled="!titles.length"
        @click="surprise"
      >
        <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5" /></svg>
        Surprise me
      </button>
    </div>

    <!-- The reveal: one title pulled off the wall -->
    <div
      v-if="pick"
      ref="revealPanel"
      tabindex="-1"
      role="region"
      :aria-label="`Hidden gem: ${pick.title}`"
      aria-live="polite"
      class="pointer-events-none absolute inset-0 flex items-center justify-center px-4 outline-none sm:px-8 lg:px-12"
    >
      <!-- Grid so the actions can span the full width beside a small poster on phones -->
      <div
        :key="revealCount"
        class="reveal pointer-events-auto grid w-full max-w-[760px] grid-cols-[6.5rem_minmax(0,1fr)] items-center gap-x-4 gap-y-4 sm:grid-cols-[13rem_minmax(0,1fr)] sm:gap-x-8 sm:gap-y-3"
      >
        <NuxtLink
          :to="pickHref"
          class="reveal-poster block w-full overflow-hidden rounded-card bg-surface shadow-[0_24px_60px_rgba(0,0,0,0.7)] ring-1 ring-white/10 sm:row-span-2"
          :aria-label="`Open ${pick.title}`"
        >
          <img :src="tmdbImage(pick.posterPath, 'poster')!" :alt="pick.title" class="aspect-[2/3] w-full object-cover">
        </NuxtLink>

        <div class="flex min-w-0 flex-col gap-2 sm:gap-3 sm:self-end">
          <span class="text-sm font-extrabold uppercase tracking-[1px] text-accent">Hidden gem</span>
          <h2 class="text-balance text-[26px] font-extrabold leading-[1] tracking-[-1px] sm:text-[44px] sm:tracking-[-1.5px]">
            <TitleLink :to="pickHref">{{ pick.title }}</TitleLink>
          </h2>
          <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-[13px] font-semibold text-ink-2 sm:text-[15px]">
            <span v-for="bit in pickMeta" :key="bit">{{ bit }}</span>
          </div>
          <p v-if="pick.overview" class="line-clamp-3 text-[14px] leading-snug text-ink-2 sm:text-[17px] sm:leading-relaxed">
            {{ pick.overview }}
          </p>
        </div>

        <div class="col-span-2 flex min-w-0 flex-col gap-2.5 sm:col-span-1 sm:col-start-2 sm:gap-3 sm:self-start">
          <div class="flex flex-wrap items-center gap-2.5 sm:gap-3">
            <span
              v-if="pickStatus"
              class="inline-flex h-11 items-center gap-2 rounded-full bg-white/10 px-5 text-[15px] font-extrabold text-ink sm:h-[52px] sm:text-[17px]"
            >
              <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
              {{ pickStatus }}
            </span>
            <button
              v-else-if="canRequest && pick.mediaType === 'movie'"
              type="button"
              class="inline-flex h-11 items-center gap-2 rounded-full bg-accent px-5 text-[15px] font-extrabold text-canvas transition hover:bg-accent/90 disabled:opacity-70 sm:h-[52px] sm:px-7 sm:text-[17px]"
              :disabled="requestMutation.isPending.value"
              @click="request"
            >
              <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
              {{ requestMutation.isPending.value ? 'Requesting…' : 'Request' }}
            </button>
            <button
              type="button"
              class="inline-flex h-11 items-center gap-2 rounded-full bg-ink px-5 text-[15px] font-extrabold text-canvas transition hover:bg-ink/85 sm:h-[52px] sm:px-6 sm:text-[17px]"
              @click="surprise"
            >
              <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5" /></svg>
              Another
            </button>
            <NuxtLink :to="pickHref" class="glass inline-flex h-11 items-center rounded-full px-5 text-[15px] font-bold text-ink sm:h-[52px] sm:px-6 sm:text-[17px]">
              Details
            </NuxtLink>
          </div>
          <p v-if="requestError" role="alert" class="text-[13px] font-semibold text-accent">
            {{ requestError }}
          </p>
          <p class="hidden flex-wrap items-center gap-x-5 gap-y-2 text-[13px] font-semibold text-muted sm:flex">
            <span class="inline-flex items-center gap-2">
              <kbd class="keycap" aria-label="Right arrow">
                <svg class="size-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6" /></svg>
              </kbd>
              another
            </span>
            <span class="inline-flex items-center gap-2"><kbd class="keycap">Enter</kbd> open</span>
            <span class="inline-flex items-center gap-2"><kbd class="keycap">Esc</kbd> back to the wall</span>
          </p>
        </div>
      </div>

      <button
        type="button"
        class="glass pointer-events-auto absolute right-4 top-4 grid size-10 place-items-center rounded-full text-ink sm:right-8 sm:top-6 lg:right-12"
        aria-label="Back to the wall"
        @click="close"
      >
        <svg class="size-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
      </button>
    </div>
  </section>
</template>

<style scoped>
.wall-row {
  /* gap-4 between the two copies keeps the loop seam spacing consistent */
  padding-right: 1rem;
  animation: wall-marquee linear infinite;
}

.wall-row--reverse {
  animation-direction: reverse;
}

.wall:hover .wall-row,
.wall:focus-within .wall-row,
.wall--revealing .wall-row {
  animation-play-state: paused;
}

/* A keyboard key: raised cap with a darker bottom edge */
.keycap {
  display: inline-grid;
  place-items: center;
  min-width: 1.625rem;
  height: 1.625rem;
  padding: 0 0.45rem;
  border-radius: 0.4rem;
  border: 1px solid rgb(255 255 255 / 0.14);
  background: rgb(255 255 255 / 0.08);
  box-shadow: inset 0 -2px 0 rgb(0 0 0 / 0.35);
  color: var(--color-ink);
  font: inherit;
  font-size: 11px;
  font-weight: 800;
  line-height: 1;
}

/* The pick lifts off the wall: poster swings up from the wall's tilt, copy fades in after */
.reveal-poster {
  animation: reveal-poster 450ms cubic-bezier(0.2, 0.9, 0.3, 1.2) both;
}

.reveal > div {
  animation: reveal-copy 350ms ease-out 120ms both;
}

@keyframes reveal-poster {
  from {
    opacity: 0;
    transform: translateY(24px) rotate(-8deg) scale(0.85);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

@keyframes reveal-copy {
  from {
    opacity: 0;
    transform: translateX(-8px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

@keyframes wall-marquee {
  from {
    transform: translateX(0);
  }
  to {
    transform: translateX(-50%);
  }
}

@media (prefers-reduced-motion: reduce) {
  .wall-row,
  .reveal-poster,
  .reveal > div {
    animation: none;
  }
}
</style>
