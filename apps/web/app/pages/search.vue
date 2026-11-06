<script setup lang="ts">
import { keepPreviousData, useQuery } from '@tanstack/vue-query'
import type { JellyfinSearchResults } from '~/types/jellyfin'
import { SEERR_MEDIA_STATUS } from '~/types/seerr'

definePageMeta({ middleware: 'auth', layout: 'app' })

type Scope = 'all' | 'movies' | 'shows' | 'people'

const SCOPES: { value: Scope, label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'movies', label: 'Movies' },
  { value: 'shows', label: 'Shows' },
  { value: 'people', label: 'People' },
]

const route = useRoute()
const router = useRouter()
const { personImageUrl } = useJellyfin()
const queries = useJellyfinQueries()

const query = ref(typeof route.query.q === 'string' ? route.query.q : '')
/** `query` after the debounce; this is what's actually searched. */
const searchTerm = ref(query.value.trim())
const scope = ref<Scope>('all')
const inputRef = ref<HTMLInputElement | null>(null)
let debounce: ReturnType<typeof setTimeout> | null = null

const searchQuery = useQuery(computed(() => ({
  ...queries.search(searchTerm.value),
  enabled: searchTerm.value.length > 0,
  // Keep the last results on screen (dimmed) while the next term loads.
  placeholderData: keepPreviousData,
})))
const EMPTY: JellyfinSearchResults = { items: [], people: [] }
const results = computed(() => (searchTerm.value ? searchQuery.data.value ?? EMPTY : EMPTY))
const searching = computed(() => searchQuery.isFetching.value)
/** Kept results stay visible (dimmed) when a later term fails; the banner covers that. */
const loadError = computed(() => (searchTerm.value && !searchQuery.data.value ? searchQuery.error.value : null))

/** TMDB matches via Seerr, for titles the library doesn't have yet. Quietly absent without Seerr. */
const seerr = useSeerrStatus()
const seerrQueries = useSeerrQueries()
const seerrUsable = computed(() => seerr.status.value?.configured === true && seerr.status.value.reachable)
const seerrQuery = useQuery(computed(() => ({
  ...seerrQueries.search(searchTerm.value),
  enabled: seerrUsable.value && searchTerm.value.length > 0,
  placeholderData: keepPreviousData,
})))
/** Anything already (even partly) in the library shows up in the Jellyfin results instead. */
const requestable = computed(() => (searchTerm.value && seerrUsable.value ? seerrQuery.data.value?.titles ?? [] : [])
  .filter(title => title.mediaInfo?.status !== SEERR_MEDIA_STATUS.AVAILABLE
    && title.mediaInfo?.status !== SEERR_MEDIA_STATUS.PARTIALLY_AVAILABLE))
const seerrTitles = computed(() => {
  if (scope.value === 'movies') return requestable.value.filter(title => title.mediaType === 'movie')
  if (scope.value === 'shows') return requestable.value.filter(title => title.mediaType === 'tv')
  if (scope.value === 'people') return []
  return requestable.value
})

const personId = computed(() => (typeof route.query.person === 'string' ? route.query.person : null))
const personQuery = useQuery(computed(() => ({
  ...queries.personItems(personId.value ?? ''),
  enabled: personId.value != null,
})))
const personItems = computed(() => (personId.value ? personQuery.data.value ?? [] : []))
const loadingPerson = computed(() => personId.value != null && personQuery.isPending.value)

const movies = computed(() => results.value.items.filter(item => item.type === 'Movie'))
const shows = computed(() => results.value.items.filter(item => item.type === 'Series'))
const episodes = computed(() => results.value.items.filter(item => item.type === 'Episode'))

const titles = computed(() => {
  if (scope.value === 'movies') return movies.value
  if (scope.value === 'shows') return shows.value
  if (scope.value === 'people') return []
  return [...movies.value, ...shows.value]
})

const topResults = computed(() => (scope.value === 'all' ? titles.value.slice(0, 3) : []))
const showEpisodes = computed(() => scope.value === 'all' || scope.value === 'shows')
const showPeople = computed(() => scope.value === 'all' || scope.value === 'people')
const hasQuery = computed(() => query.value.trim().length > 0)
const nothingFound = computed(() =>
  hasQuery.value && !searching.value && !loadError.value
  && !results.value.items.length && !results.value.people.length
  && !personItems.value.length && !loadingPerson.value
  && !requestable.value.length && !seerrQuery.isFetching.value,
)

function openPerson(id: string, name: string) {
  void router.push({ query: { q: name, person: id } })
}

watch(query, (term) => {
  if (debounce) clearTimeout(debounce)
  debounce = setTimeout(() => {
    const keepPerson = personId.value && term === route.query.q
    void router.replace({
      query: term.trim() ? { q: term, ...(keepPerson ? { person: personId.value! } : {}) } : {},
    })
    searchTerm.value = term.trim()
  }, 250)
})

watch(() => route.query.q, (q) => {
  const next = typeof q === 'string' ? q : ''
  if (next !== query.value) {
    query.value = next
  }
})

onMounted(() => {
  inputRef.value?.focus()
})
onBeforeUnmount(() => {
  if (debounce) clearTimeout(debounce)
})
</script>

<template>
  <main class="w-full pb-20 pt-24 sm:pt-28">
    <div class="mx-auto flex max-w-[920px] flex-col gap-4 px-4 sm:px-8">
      <label class="flex h-16 items-center gap-3.5 rounded-[18px] bg-surface px-5 ring-2 ring-transparent transition focus-within:ring-ink">
        <svg class="size-[22px] shrink-0 text-muted" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true">
          <circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" />
        </svg>
        <span class="sr-only">Search movies, shows and people</span>
        <input
          ref="inputRef"
          v-model="query"
          type="search"
          placeholder="Movies, shows, people"
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
      <div v-if="hasQuery" role="group" aria-label="Search in" class="flex flex-wrap justify-center gap-2">
        <button
          v-for="option in SCOPES"
          :key="option.value"
          type="button"
          class="h-[38px] rounded-full px-[18px] text-sm font-bold transition"
          :class="scope === option.value ? 'bg-ink text-canvas' : 'bg-surface text-ink-2 hover:bg-elevated'"
          :aria-pressed="scope === option.value"
          @click="scope = option.value"
        >
          {{ option.label }}
        </button>
      </div>
    </div>

    <ErrorState v-if="hasQuery && loadError" compact class="mt-6" :error="loadError" :on-retry="searchQuery.refetch" />
    <p v-else-if="nothingFound" class="mt-12 text-center text-muted">
      Nothing matches “{{ query.trim() }}”.
    </p>

    <div
      v-else-if="hasQuery"
      class="mt-11 flex flex-col gap-11 transition-opacity"
      :class="searching ? 'opacity-60' : 'opacity-100'"
    >
      <MediaRow
        v-if="personId"
        :title="`Featuring ${query.trim()}`"
        :count="personItems.length"
      >
        <template #default="{ slideClass }">
          <div v-for="item in personItems" :key="item.id" :class="slideClass">
            <MediaCard :item="item" />
          </div>
        </template>
      </MediaRow>
      <MediaRow title="Top Results" :count="topResults.length" wide>
        <template #default="{ slideClass }">
          <div v-for="item in topResults" :key="item.id" :class="slideClass">
            <MediaCard
              :item="item"
              variant="landscape"
              :kicker="[item.type === 'Series' ? 'Series' : 'Movie', item.productionYear].filter(Boolean).join(', ')"
              :caption="item.name"
            />
          </div>
        </template>
      </MediaRow>

      <MediaRow :title="scope === 'shows' ? 'Shows' : scope === 'movies' ? 'Movies' : 'Movies & Shows'" :count="titles.length">
        <template #default="{ slideClass }">
          <div v-for="item in titles" :key="item.id" :class="slideClass">
            <MediaCard
              :item="item"
              :detail="[item.type === 'Series' ? 'Series' : 'Movie', item.productionYear].filter(Boolean).join(', ')"
            />
          </div>
        </template>
      </MediaRow>

      <MediaRow v-if="showEpisodes" title="Episodes" :count="episodes.length" wide>
        <template #default="{ slideClass }">
          <div v-for="item in episodes" :key="item.id" :class="slideClass">
            <MediaCard
              :item="item"
              variant="landscape"
              :caption="item.name"
            />
          </div>
        </template>
      </MediaRow>

      <MediaRow v-if="seerrTitles.length" title="Not in Your Library" :count="seerrTitles.length">
        <template #default="{ slideClass }">
          <div v-for="title in seerrTitles" :key="`${title.mediaType}-${title.tmdbId}`" :class="slideClass">
            <SeerrCard :title="title" />
          </div>
        </template>
      </MediaRow>

      <section v-if="showPeople && results.people.length" aria-label="Cast and crew" class="flex flex-col gap-3.5">
        <h2 class="px-4 text-xl font-extrabold tracking-[-0.5px] sm:px-8 sm:text-2xl lg:px-12">
          Cast &amp; Crew
        </h2>
        <div class="rail flex gap-7 overflow-x-auto px-4 sm:px-8 lg:px-12">
          <button
            v-for="person in results.people"
            :key="person.id"
            type="button"
            class="flex w-[112px] shrink-0 flex-col items-center gap-2.5 text-center sm:w-32"
            @click="openPerson(person.id, person.name)"
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
            <span class="text-[15px] font-bold">{{ person.name }}</span>
          </button>
        </div>
      </section>
    </div>
  </main>
</template>
