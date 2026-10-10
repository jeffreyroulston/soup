<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { JellyfinItem } from '~/types/jellyfin'

definePageMeta({ middleware: 'auth', layout: 'app' })

const { imageUrl } = useJellyfin()
const queries = useJellyfinQueries()
const { libraries } = useLibraries()
const homeQuery = useQuery(queries.home())
/** Top Rated and the collection spotlight: below the fold, so they don't hold up the first paint. */
const extrasQuery = useQuery(queries.homeExtras())

const home = computed(() => homeQuery.data.value ?? null)
const extras = computed(() => extrasQuery.data.value ?? null)
const loading = computed(() => homeQuery.isPending.value)
/** Only when there's nothing to show; a failed background refresh keeps the cached rows. */
const errorMessage = computed(() => {
  const error = homeQuery.error.value
  return error && !home.value ? error.message || 'Failed to load home' : ''
})

const resumeIds = computed(() => new Set(home.value?.resume.map(item => item.id) ?? []))

const featured = computed<JellyfinItem[]>(() => {
  if (!home.value) return []
  const seen = new Set<string>()
  const picks: JellyfinItem[] = []
  for (const item of [...home.value.resume, ...home.value.recentlyAddedMovies, ...home.value.recentlyAddedTv]) {
    const key = item.seriesId || item.id
    if (seen.has(key) || !imageUrl(item, 'Backdrop', 1920)) continue
    seen.add(key)
    picks.push(item)
    if (picks.length === 6) break
  }
  return picks
})

const upNext = computed(() => (home.value ? [...home.value.resume, ...home.value.nextUp] : []))

function upNextLead(item: JellyfinItem) {
  return resumeIds.value.has(item.id) ? 'Continue' : 'Next'
}

function upNextDetail(item: JellyfinItem) {
  const left = timeLeftLabel(item)
  if (item.type === 'Episode') return left ? `${item.name} · ${left}` : item.name
  return left ?? runtimeLabel(item.runTimeTicks)
}

const moviesLibrary = computed(() => libraries.value.find(lib => lib.collectionType === 'movies') ?? null)

const spotlightBackdrop = computed(() => {
  const spot = extras.value?.spotlight
  if (!spot) return null
  return imageUrl(spot.collection, 'Backdrop', 1600)
    ?? spot.items.map(item => imageUrl(item, 'Backdrop', 1600)).find(Boolean)
    ?? null
})
</script>

<template>
  <main class="w-full pb-20">
    <div v-if="loading" aria-busy="true" aria-label="Loading home">
      <!-- Same box and bottom anchoring as HeroCarousel -->
      <section class="relative h-[min(88vh,780px)] min-h-[560px] w-full overflow-hidden bg-surface/50">
        <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/60 via-30% to-transparent to-60%" />
        <div class="absolute inset-x-4 bottom-10 flex flex-wrap items-end justify-between gap-6 sm:inset-x-8 sm:bottom-16 lg:inset-x-12 lg:bottom-[72px]">
          <div class="flex w-full max-w-[600px] flex-col gap-4">
            <span class="text-sm font-bold"><span class="inline-block h-[0.8em] w-40 animate-pulse rounded bg-elevated align-middle" /></span>
            <span class="block h-[calc(clamp(2.75rem,7vw,6rem)*0.92)] w-3/4 animate-pulse rounded-btn bg-elevated" />
            <span class="text-[15px] font-semibold"><span class="inline-block h-[0.8em] w-56 animate-pulse rounded bg-elevated align-middle" /></span>
            <span class="flex flex-col text-[17px] leading-relaxed">
              <span><span class="inline-block h-[0.8em] w-full animate-pulse rounded bg-elevated align-middle" /></span>
              <span><span class="inline-block h-[0.8em] w-5/6 animate-pulse rounded bg-elevated align-middle" /></span>
            </span>
            <div class="mt-1 flex items-center gap-3">
              <span class="h-[52px] w-48 animate-pulse rounded-btn bg-elevated" />
              <span class="hidden h-[52px] w-28 animate-pulse rounded-btn bg-elevated sm:block" />
              <span class="size-[52px] animate-pulse rounded-full bg-elevated" />
            </div>
          </div>
        </div>
      </section>

      <div class="flex flex-col gap-12">
        <MediaRow title="Keep Watching" :count="4" wide>
          <template #default="{ slideClass }">
            <div v-for="n in 4" :key="n" :class="slideClass">
              <MediaCardSkeleton variant="landscape" kicker />
            </div>
          </template>
        </MediaRow>
        <MediaRow title="Recently Added Movies" :count="8">
          <template #default="{ slideClass }">
            <div v-for="n in 8" :key="n" :class="slideClass">
              <MediaCardSkeleton />
            </div>
          </template>
        </MediaRow>
      </div>
    </div>
    <p v-else-if="errorMessage" class="px-4 pt-32 font-semibold text-accent sm:px-8 lg:px-12">
      {{ errorMessage }}
    </p>
    <template v-else-if="home">
      <HeroCarousel v-if="featured.length" :items="featured" :resume-ids="resumeIds" />
      <div v-else class="h-28" />

      <div class="flex flex-col gap-12">
        <MediaRow title="Keep Watching" :count="upNext.length" wide>
          <template #default="{ slideClass }">
            <div v-for="item in upNext" :key="item.id" :class="slideClass">
              <MediaCard
                :item="item"
                variant="landscape"
                :kicker="upNextLead(item)"
                :detail="upNextDetail(item)"
                :to="isPlayable(item) ? watchRoute(item) : undefined"
                :play="isPlayable(item)"
              />
            </div>
          </template>
        </MediaRow>

        <section
          v-if="extras?.spotlight"
          aria-label="Collection spotlight"
          class="relative mx-4 flex min-h-[340px] items-center overflow-hidden rounded-panel bg-surface px-6 py-10 sm:mx-8 sm:px-14 lg:mx-12"
        >
          <img
            v-if="spotlightBackdrop"
            :src="spotlightBackdrop"
            alt=""
            class="absolute inset-0 size-full object-cover"
            loading="lazy"
          >
          <div class="absolute inset-0 bg-gradient-to-r from-canvas/90 via-canvas/60 to-transparent" />
          <div class="relative flex max-w-[480px] flex-col gap-3.5">
            <span class="text-sm font-bold text-ink-2">
              Collection · {{ extras.spotlight.items.length }} titles
            </span>
            <h2 class="text-[clamp(2.25rem,4vw,3.4rem)] font-extrabold leading-[0.95] tracking-[-0.04em]">
              {{ extras.spotlight.collection.name }}
            </h2>
            <p v-if="extras.spotlight.collection.overview" class="line-clamp-3 text-base leading-relaxed text-ink-2">
              {{ extras.spotlight.collection.overview }}
            </p>
            <NuxtLink
              :to="`/item/${extras.spotlight.collection.id}`"
              class="inline-flex h-[46px] items-center self-start rounded-btn bg-ink px-6 text-base font-extrabold text-canvas transition hover:bg-ink/80"
            >
              View the collection
            </NuxtLink>
          </div>
        </section>

        <MediaRow
          title="Recently Added Movies"
          :count="home.recentlyAddedMovies.length"
          :see-all-to="moviesLibrary ? `/library/${moviesLibrary.id}` : null"
        >
          <template #default="{ slideClass }">
            <div v-for="item in home.recentlyAddedMovies" :key="item.id" :class="slideClass">
              <MediaCard :item="item" />
            </div>
          </template>
        </MediaRow>

        <MediaRow
          title="Recently Added Shows"
          :count="home.recentlyAddedTv.length"
        >
          <template #default="{ slideClass }">
            <div v-for="item in home.recentlyAddedTv" :key="item.id" :class="slideClass">
              <MediaCard
                :item="item"
                :to="item.seriesId ? `/item/${item.seriesId}` : undefined"
              />
            </div>
          </template>
        </MediaRow>

        <RankList v-if="extras" title="Top Rated" :items="extras.topRated" />

        <p
          v-if="!upNext.length && !home.recentlyAddedMovies.length && !home.recentlyAddedTv.length"
          class="px-4 text-muted sm:px-8 lg:px-12"
        >
          Nothing here yet. Add some media to your Jellyfin libraries.
        </p>
      </div>
    </template>
  </main>
</template>
