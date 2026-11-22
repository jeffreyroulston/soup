<script setup lang="ts">
import { useInfiniteQuery, useQuery } from '@tanstack/vue-query'
import type { SeerrMediaType, SeerrTitle } from '~/types/seerr'

definePageMeta({ middleware: 'auth', layout: 'app' })

const route = useRoute()
const seerr = useSeerrStatus()
const queries = useSeerrQueries()
const api = useSeerr()

const mediaType = computed<SeerrMediaType | null>(() => {
  const type = String(route.params.type)
  return type === 'movie' || type === 'tv' ? type : null
})
const genreId = computed(() => {
  const id = Number(route.params.id)
  return Number.isInteger(id) && id > 0 ? id : null
})
const valid = computed(() => mediaType.value !== null && genreId.value !== null)
const usable = computed(() => seerr.status.value?.configured === true && seerr.status.value.reachable)
const path = computed(() => seerrGenreDiscoverPath(mediaType.value ?? 'movie', genreId.value ?? 0))

/** The genre's name and backdrops come from the (usually cached) genre slider. */
const genresQuery = useQuery(computed(() => ({
  ...queries.genres(mediaType.value ?? 'movie'),
  enabled: valid.value && usable.value,
})))
const genre = computed(() => genresQuery.data.value?.find(entry => entry.id === genreId.value) ?? null)
const banner = computed(() => (genre.value ? tmdbImage(genre.value.backdrops[0], 'backdrop') : null))

const titlesQuery = useInfiniteQuery(computed(() => ({
  queryKey: [...queryKeys.seerr(), 'discover-all', path.value] as const,
  queryFn: ({ pageParam }: { pageParam: number }) => api.discover(path.value, pageParam),
  initialPageParam: 1,
  getNextPageParam: (last: { page: number, totalPages: number }) => (last.page < last.totalPages ? last.page + 1 : undefined),
  enabled: valid.value && usable.value,
  staleTime: 10 * 60_000,
  retry: seerrRetry,
})))

/** TMDB pages can overlap as popularity shifts; keep the first sighting of each title. */
const titles = computed(() => {
  const seen = new Set<string>()
  const list: SeerrTitle[] = []
  for (const page of titlesQuery.data.value?.pages ?? []) {
    for (const title of page.titles) {
      const key = `${title.mediaType}-${title.tmdbId}`
      if (seen.has(key)) continue
      seen.add(key)
      list.push(title)
    }
  }
  return list
})
const loading = computed(() => valid.value && usable.value && titlesQuery.isPending.value)
const loadError = computed(() => (titlesQuery.data.value ? null : titlesQuery.error.value))
const heading = computed(() => genre.value?.name ?? 'Genre')

useHead(() => ({ title: genre.value ? `${genre.value.name} · Explore` : 'Explore' }))
</script>

<template>
  <main class="w-full pb-20">
    <!-- Banner: the genre's tint over one of its backdrops -->
    <section
      class="relative flex min-h-[min(44vh,380px)] w-full items-end overflow-hidden px-4 pb-8 pt-32 sm:px-8 lg:px-12"
      :style="{ '--tint': genreTint(genreId ?? 0) }"
    >
      <img v-if="banner" :src="banner" alt="" class="absolute inset-0 size-full object-cover grayscale">
      <div class="absolute inset-0 bg-[var(--tint)] mix-blend-multiply" />
      <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/40 to-transparent" />
      <div class="relative flex flex-col gap-2">
        <NuxtLink to="/explore" class="text-sm font-extrabold uppercase tracking-[1px] text-ink-2 hover:text-ink">
          ‹ Explore · {{ mediaType === 'tv' ? 'Shows' : 'Movies' }}
        </NuxtLink>
        <h1 class="text-[44px] font-extrabold leading-none tracking-[-1.5px] sm:text-[72px] sm:tracking-[-2.5px]">
          <template v-if="genre || !genresQuery.isPending.value">{{ heading }}</template>
          <span v-else class="inline-block h-[0.8em] w-72 animate-pulse rounded bg-white/15 align-middle" />
        </h1>
      </div>
    </section>

    <SeerrUnavailable v-if="seerr.loaded.value && !usable" :status="seerr.status.value" :error="seerr.error.value" :on-retry="seerr.refetch" />

    <p v-else-if="!valid" class="mt-12 text-center text-muted">
      There's no such genre.
    </p>

    <div v-else-if="loadError" class="mt-6">
      <SeerrUnavailable :status="null" :error="loadError" :on-retry="titlesQuery.refetch" />
    </div>

    <div v-else class="mt-6 flex flex-col gap-8 px-4 sm:px-8 lg:px-12">
      <div class="grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-4 sm:grid-cols-[repeat(auto-fill,minmax(11rem,1fr))] sm:gap-5">
        <template v-if="loading || !seerr.loaded.value">
          <MediaCardSkeleton v-for="n in 18" :key="n" variant="poster" />
        </template>
        <SeerrCard v-for="title in titles" v-else :key="`${title.mediaType}-${title.tmdbId}`" :title="title" />
      </div>
      <p v-if="!loading && seerr.loaded.value && !titles.length" class="text-center text-muted">
        Nothing in this genre right now.
      </p>
      <button
        v-if="titlesQuery.hasNextPage.value"
        type="button"
        class="glass mx-auto h-[46px] rounded-full px-6 text-[15px] font-bold text-ink disabled:opacity-60"
        :disabled="titlesQuery.isFetchingNextPage.value"
        @click="titlesQuery.fetchNextPage()"
      >
        {{ titlesQuery.isFetchingNextPage.value ? 'Loading…' : 'Show more' }}
      </button>
    </div>
  </main>
</template>
