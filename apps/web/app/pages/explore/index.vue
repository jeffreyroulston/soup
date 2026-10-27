<script setup lang="ts">
import { keepPreviousData, useQuery } from '@tanstack/vue-query'
import type { SeerrSearchResults } from '~/types/seerr'

definePageMeta({ middleware: 'auth', layout: 'app' })

const route = useRoute()
const router = useRouter()
const seerr = useSeerrStatus()
const queries = useSeerrQueries()

const query = ref(typeof route.query.q === 'string' ? route.query.q : '')
/** `query` after the debounce; this is what's actually searched. */
const searchTerm = ref(query.value.trim())
const inputRef = ref<HTMLInputElement | null>(null)
let debounce: ReturnType<typeof setTimeout> | null = null

const usable = computed(() => seerr.status.value?.configured === true && seerr.status.value.reachable)

const searchQuery = useQuery(computed(() => ({
  ...queries.search(searchTerm.value),
  enabled: usable.value && searchTerm.value.length > 0,
  placeholderData: keepPreviousData,
})))
const EMPTY: SeerrSearchResults = { page: 1, totalPages: 0, totalResults: 0, titles: [], people: [] }
const results = computed(() => (searchTerm.value ? searchQuery.data.value ?? EMPTY : EMPTY))
const searching = computed(() => searchQuery.isFetching.value)
const searchError = computed(() => (searchTerm.value && !searchQuery.data.value ? searchQuery.error.value : null))
const hasQuery = computed(() => query.value.trim().length > 0)
const nothingFound = computed(() =>
  hasQuery.value && !searching.value && !searchError.value && !results.value.titles.length && !results.value.people.length)

const ROWS = [
  { key: 'trending', title: 'Trending', path: 'discover/trending' },
  { key: 'movies', title: 'Popular Movies', path: 'discover/movies' },
  { key: 'tv', title: 'Popular Shows', path: 'discover/tv' },
  { key: 'upcoming', title: 'Coming Soon', path: 'discover/movies/upcoming' },
] as const

const rowQueries = ROWS.map(row => useQuery(computed(() => ({
  ...queries.discover(row.path),
  enabled: usable.value && !hasQuery.value,
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

const requestsQuery = useQuery(computed(() => ({
  ...queries.requests('all', 12),
  enabled: usable.value && !hasQuery.value && seerr.user.value != null,
})))
const recentRequests = computed(() => requestsQuery.data.value?.requests ?? [])

function openPerson(name: string) {
  query.value = name
}

watch(query, (term) => {
  if (debounce) clearTimeout(debounce)
  debounce = setTimeout(() => {
    void router.replace({ query: term.trim() ? { q: term } : {} })
    searchTerm.value = term.trim()
  }, 250)
})

watch(() => route.query.q, (q) => {
  const next = typeof q === 'string' ? q : ''
  if (next !== query.value) query.value = next
})

onBeforeUnmount(() => {
  if (debounce) clearTimeout(debounce)
})
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
      <div class="mx-auto mt-8 flex max-w-[920px] flex-col gap-4 px-4 sm:px-8">
        <label class="flex h-16 items-center gap-3.5 rounded-[18px] bg-surface px-5 ring-2 ring-transparent transition focus-within:ring-ink">
          <svg class="size-[22px] shrink-0 text-muted" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true">
            <circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" />
          </svg>
          <span class="sr-only">Search everything on TMDB</span>
          <input
            ref="inputRef"
            v-model="query"
            type="search"
            placeholder="Find a movie or show"
            autocomplete="off"
            class="min-w-0 flex-1 border-0 bg-transparent text-[22px] font-bold text-ink outline-none focus-visible:outline-none! placeholder:text-muted [&::-webkit-search-cancel-button]:hidden"
          >
          <button
            v-if="query"
            type="button"
            class="grid size-8 shrink-0 place-items-center rounded-full bg-[#3A3A3C] text-ink"
            aria-label="Clear search"
            @click="query = ''; inputRef?.focus()"
          >
            <svg class="size-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
        </label>
        <p v-if="!seerr.user.value" class="text-center text-[13px] font-semibold text-muted">
          You can browse, but requesting needs a Seerr account linked to your Jellyfin login. Sign in to Seerr with Jellyfin once and come back.
        </p>
      </div>

      <!-- Search results -->
      <template v-if="hasQuery">
        <div v-if="searchError" class="mt-6">
          <SeerrUnavailable :status="null" :error="searchError" :on-retry="searchQuery.refetch" />
        </div>
        <p v-else-if="nothingFound" class="mt-12 text-center text-muted">
          Nothing matches “{{ query.trim() }}”.
        </p>
        <div
          v-else
          class="mt-10 flex flex-col gap-11 transition-opacity"
          :class="searching ? 'opacity-60' : 'opacity-100'"
        >
          <section v-if="results.titles.length" aria-label="Results" class="flex flex-col gap-3.5 px-4 sm:px-8 lg:px-12">
            <h2 class="text-xl font-extrabold tracking-[-0.5px] sm:text-2xl">
              Movies &amp; Shows
            </h2>
            <div class="grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-4 sm:grid-cols-[repeat(auto-fill,minmax(11rem,1fr))] sm:gap-5">
              <SeerrCard v-for="title in results.titles" :key="`${title.mediaType}-${title.tmdbId}`" :title="title" />
            </div>
          </section>
          <section v-if="results.people.length" aria-label="People" class="flex flex-col gap-3.5">
            <h2 class="px-4 text-xl font-extrabold tracking-[-0.5px] sm:px-8 sm:text-2xl lg:px-12">
              People
            </h2>
            <div class="rail flex gap-7 overflow-x-auto px-4 sm:px-8 lg:px-12">
              <button
                v-for="person in results.people"
                :key="person.tmdbId"
                type="button"
                class="flex w-[112px] shrink-0 flex-col items-center gap-2.5 text-center sm:w-32"
                @click="openPerson(person.name)"
              >
                <span class="relative grid size-[112px] place-items-center overflow-hidden rounded-full bg-surface text-[32px] font-extrabold text-ink-2 sm:size-32">
                  <img
                    v-if="tmdbImage(person.profilePath, 'profile')"
                    :src="tmdbImage(person.profilePath, 'profile')!"
                    :alt="person.name"
                    class="absolute inset-0 size-full object-cover"
                    loading="lazy"
                  >
                  <template v-else>{{ initials(person.name) }}</template>
                </span>
                <span class="text-[15px] font-bold">{{ person.name }}</span>
                <span v-if="person.knownFor.length" class="line-clamp-2 text-[12px] font-semibold text-muted">
                  {{ person.knownFor.map(title => title.title).slice(0, 2).join(', ') }}
                </span>
              </button>
            </div>
          </section>
        </div>
      </template>

      <!-- Discover rows -->
      <div v-else class="mt-10 flex flex-col gap-12">
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
        </template>
      </div>
    </template>
  </main>
</template>
