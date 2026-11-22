<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { SeerrTitle } from '~/types/seerr'

definePageMeta({ middleware: 'auth', layout: 'app' })

const seerr = useSeerrStatus()
const queries = useSeerrQueries()

const usable = computed(() => seerr.status.value?.configured === true && seerr.status.value.reachable)

const ROWS = [
  { key: 'trending', title: 'Trending', path: 'discover/trending' },
  { key: 'movies', title: 'Popular Movies', path: 'discover/movies' },
  { key: 'tv', title: 'Popular Shows', path: 'discover/tv' },
  { key: 'upcoming', title: 'Coming Soon', path: 'discover/movies/upcoming' },
] as const

const rowQueries = ROWS.map(row => useQuery(computed(() => ({
  ...queries.discover(row.path),
  enabled: usable.value,
}))))

const rows = computed(() => ROWS.map((row, index) => {
  const q = rowQueries[index]!
  return {
    ...row,
    titles: q.data.value?.titles ?? [],
    loading: q.isPending.value,
    error: q.error.value,
  }
}))

/**
 * Spotlight: trending titles the library doesn't have and nobody's asked for, in an order that
 * reshuffles daily. Picked once per visit, so requesting one doesn't yank it off the screen.
 */
const SPOTLIGHT_SIZE = 5
const spotlightPicks = ref<SeerrTitle[] | null>(null)
watch(() => rowQueries[0]!.data.value?.titles, (titles) => {
  if (spotlightPicks.value || !titles?.length) return
  const fresh = titles.filter(title => !availabilityLabel(title.mediaInfo) && (title.backdropPath || title.posterPath))
  const seed = new Date().toISOString().slice(0, 10)
  spotlightPicks.value = fresh
    .map(title => ({ title, rank: dailyRank(`${seed}:${title.mediaType}-${title.tmdbId}`) }))
    .sort((a, b) => a.rank - b.rank)
    .slice(0, SPOTLIGHT_SIZE)
    .map(entry => entry.title)
}, { immediate: true })
/** The picks with their latest library status, so a request here shows as requested. */
const spotlight = computed(() => {
  const latest = rowQueries[0]!.data.value?.titles ?? []
  return (spotlightPicks.value ?? []).map(pick =>
    latest.find(title => title.mediaType === pick.mediaType && title.tmdbId === pick.tmdbId) ?? pick)
})

/** A stable pseudo-random rank for a string (FNV-1a), so the day's order holds across reloads. */
function dailyRank(key: string): number {
  let hash = 0x811C9DC5
  for (let i = 0; i < key.length; i++) {
    hash ^= key.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return hash >>> 0
}

const requestsQuery = useQuery(computed(() => ({
  ...queries.requests('all', 12),
  enabled: usable.value && seerr.user.value != null,
})))
const recentRequests = computed(() => requestsQuery.data.value?.requests ?? [])
</script>

<template>
  <main class="w-full pb-20 pt-24 sm:pt-28">
    <ExploreHeader />

    <template v-if="!seerr.loaded.value">
      <div class="mt-10 flex flex-col gap-12" aria-busy="true">
        <MediaRow v-for="n in 2" :key="n" loading />
      </div>
    </template>

    <SeerrUnavailable v-else-if="!usable" :status="seerr.status.value" :error="seerr.error.value" :on-retry="seerr.refetch" />

    <template v-else>
      <p v-if="!seerr.user.value" class="mx-auto mt-8 max-w-[920px] px-4 text-center text-[13px] font-semibold text-muted sm:px-8">
        You can browse, but requesting needs a Seerr account linked to your Jellyfin login. Sign in to Seerr with Jellyfin once and come back.
      </p>

      <div class="mt-10 flex flex-col gap-12">
        <ExploreSpotlight
          v-if="spotlight.length || rowQueries[0]!.isPending.value"
          :titles="spotlight"
          :loading="!spotlight.length"
        />

        <MediaRow
          v-if="recentRequests.length"
          title="Your Requests"
          :count="recentRequests.length"
          see-all-to="/explore/requests"
          wide
        >
          <template #default="{ slideClass }">
            <div v-for="request in recentRequests" :key="request.id" :class="slideClass">
              <SeerrRequestCard :request="request" />
            </div>
          </template>
        </MediaRow>

        <template v-for="row in rows" :key="row.key">
          <MediaRow v-if="!row.error" :title="row.title" :count="row.titles.length" :loading="row.loading">
            <template #default="{ slideClass }">
              <div v-for="title in row.titles" :key="`${title.mediaType}-${title.tmdbId}`" :class="slideClass">
                <SeerrCard :title="title" />
              </div>
            </template>
          </MediaRow>
          <!-- Genre tiles break up the poster rows, just below Trending -->
          <ExploreGenres v-if="row.key === 'trending'" />
          <!-- Poster wall after the show rows, before Coming Soon -->
          <ExplorePosterWall v-if="row.key === 'tv'" />
        </template>
      </div>
    </template>
  </main>
</template>
