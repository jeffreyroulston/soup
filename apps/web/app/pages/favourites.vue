<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { LibrarySort } from '~/composables/useJellyfin'
import type { JellyfinItem } from '~/types/jellyfin'

definePageMeta({ middleware: 'auth', layout: 'app' })

type Kind = 'all' | 'movies' | 'shows' | 'episodes'

const KINDS: { value: Kind, label: string, types: string[] }[] = [
  { value: 'all', label: 'All', types: [] },
  { value: 'movies', label: 'Movies', types: ['Movie'] },
  { value: 'shows', label: 'Shows', types: ['Series'] },
  { value: 'episodes', label: 'Episodes', types: ['Episode'] },
]
// Jellyfin keeps no "favourited on" date, so there's no "Recently favourited".
const SORTS: { value: LibrarySort, label: string }[] = [
  { value: 'SortName', label: 'Title' },
  { value: 'DateCreated', label: 'Recently Added' },
  { value: 'ProductionYear', label: 'Year' },
]

const queries = useJellyfinQueries()
const sortBy = ref<LibrarySort>('SortName')
const kind = ref<Kind>('all')

const favoritesQuery = useQuery(computed(() => ({
  ...queries.favorites(sortBy.value),
  // A new sort keeps the current grid on screen until the reordered one arrives.
  placeholderData: <T>(previous: T | undefined) => previous,
})))

// Un-hearting patches the cached item first, so it leaves the grid at once.
const items = computed(() => (favoritesQuery.data.value ?? []).filter(item => item.isFavorite))
const loading = computed(() => favoritesQuery.isPending.value)
const loadError = computed(() => (favoritesQuery.data.value ? null : favoritesQuery.error.value))

function matches(item: JellyfinItem, value: Kind) {
  const types = KINDS.find(option => option.value === value)?.types ?? []
  return !types.length || types.includes(item.type)
}

const kinds = computed(() => KINDS
  .map(option => ({ ...option, count: items.value.filter(item => matches(item, option.value)).length }))
  // Only offer a type there's something of; All always shows.
  .filter(option => option.value === 'all' || option.count))

const visible = computed(() => items.value.filter(item => matches(item, kind.value)))

// If the last favourite of a type goes, fall back to All rather than an empty tab.
watch(kinds, (options) => {
  if (!options.some(option => option.value === kind.value)) kind.value = 'all'
})

const countLabel = computed(() => {
  const n = items.value.length
  return `${n} ${n === 1 ? 'title' : 'titles'}`
})
</script>

<template>
  <main class="w-full pb-20 pt-24 sm:pt-28">
    <MyStuffHeader />

    <div v-if="loading || items.length" class="flex flex-wrap items-center justify-between gap-x-5 gap-y-4 px-4 pt-8 sm:px-8 sm:pt-9 lg:px-12">
      <span class="text-[15px] font-semibold text-muted">
        <template v-if="!loading">{{ countLabel }}</template>
        <span v-else class="inline-block h-[0.8em] w-20 animate-pulse rounded bg-surface align-middle" />
      </span>
      <div v-if="items.length" class="flex flex-wrap items-center gap-2.5">
        <div role="group" aria-label="Show" class="rail flex max-w-full gap-0.5 overflow-x-auto rounded-full bg-surface p-1">
          <button
            v-for="option in kinds"
            :key="option.value"
            type="button"
            class="flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-4 text-sm font-bold transition"
            :class="kind === option.value ? 'bg-ink text-canvas' : 'text-ink-2 hover:text-ink'"
            :aria-pressed="kind === option.value"
            @click="kind = option.value"
          >
            {{ option.label }}
            <span class="tabular-nums" :class="kind === option.value ? 'text-canvas/60' : 'text-muted'">{{ option.count }}</span>
          </button>
        </div>
        <SelectMenu v-model="sortBy" label="Sort" prefix="Sort" tone="surface" :options="SORTS" />
      </div>
    </div>

    <div class="px-4 pt-7 sm:px-8 lg:px-12">
      <div
        v-if="loading"
        class="grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-x-5 gap-y-8 sm:grid-cols-[repeat(auto-fill,minmax(176px,1fr))]"
      >
        <div v-for="n in 12" :key="n">
          <MediaCardSkeleton />
        </div>
      </div>
      <ErrorState v-else-if="loadError" compact :error="loadError" :on-retry="favoritesQuery.refetch" />
      <div v-else-if="!items.length" class="flex max-w-md flex-col items-start gap-3 pt-6">
        <h2 class="text-xl font-extrabold tracking-[-0.5px]">
          No favourites yet
        </h2>
        <p class="text-[15px] leading-relaxed text-muted">
          Tap the heart on any movie, show or episode to keep it here.
        </p>
        <NuxtLink to="/" class="mt-1 inline-flex h-11 items-center rounded-full bg-surface px-5 text-sm font-bold transition hover:bg-elevated">
          Browse Home
        </NuxtLink>
      </div>
      <div
        v-else
        class="grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-x-5 gap-y-8 transition-opacity sm:grid-cols-[repeat(auto-fill,minmax(176px,1fr))]"
        :class="favoritesQuery.isPlaceholderData.value ? 'opacity-50' : 'opacity-100'"
      >
        <MediaCard v-for="item in visible" :key="item.id" :item="item" />
      </div>
    </div>
  </main>
</template>
