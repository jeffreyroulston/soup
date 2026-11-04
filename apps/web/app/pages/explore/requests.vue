<script setup lang="ts">
import { keepPreviousData, useQuery } from '@tanstack/vue-query'
import type { SeerrRequest, SeerrRequestFilter } from '~/types/seerr'

definePageMeta({ middleware: 'auth', layout: 'app' })

const FILTERS: { value: SeerrRequestFilter, label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'pending', label: 'Pending' },
  { value: 'processing', label: 'On the way' },
  { value: 'available', label: 'In library' },
]
const PAGE_SIZE = 20

const seerr = useSeerrStatus()
const queries = useSeerrQueries()
const filter = ref<SeerrRequestFilter>('all')
/** Pages already fetched beyond the first; a filter change starts over. */
const extraPages = ref<SeerrRequest[][]>([])
const skip = ref(0)

const usable = computed(() => seerr.status.value?.configured === true && seerr.status.value.reachable)

const firstPage = useQuery(computed(() => ({
  ...queries.requests(filter.value, PAGE_SIZE, 0),
  enabled: usable.value && seerr.user.value != null,
  placeholderData: keepPreviousData,
})))
const morePage = useQuery(computed(() => ({
  ...queries.requests(filter.value, PAGE_SIZE, skip.value),
  enabled: usable.value && seerr.user.value != null && skip.value > 0,
})))

watch(() => morePage.data.value, (page) => {
  if (page && skip.value > 0) extraPages.value = [...extraPages.value, page.requests]
})

watch(filter, () => {
  extraPages.value = []
  skip.value = 0
})

const requests = computed(() => [...(firstPage.data.value?.requests ?? []), ...extraPages.value.flat()])
const total = computed(() => firstPage.data.value?.total ?? 0)
const loading = computed(() => firstPage.isPending.value && usable.value && seerr.user.value != null)
const hasMore = computed(() => requests.value.length < total.value)
const error = computed(() => (firstPage.data.value ? null : firstPage.error.value))

function loadMore() {
  skip.value = requests.value.length
}
</script>

<template>
  <main class="w-full pb-20 pt-24 sm:pt-28">
    <ExploreHeader />

    <div v-if="!seerr.loaded.value" class="mt-10 flex flex-col gap-3 px-4 sm:px-8 lg:px-12" aria-busy="true">
      <div v-for="n in 4" :key="n" class="h-[132px] animate-pulse rounded-panel bg-surface" />
    </div>

    <SeerrUnavailable v-else-if="!usable" :status="seerr.status.value" :error="seerr.error.value" :on-retry="seerr.refetch" />

    <section v-else-if="!seerr.user.value" class="mx-auto flex w-full max-w-[520px] flex-col items-center px-4 py-20 text-center">
      <h2 class="text-[26px] font-extrabold leading-tight tracking-[-0.8px] text-ink">
        No Seerr account yet
      </h2>
      <p class="mt-3 text-[15px] leading-relaxed text-muted">
        Requests are made as your Seerr account. Sign in to Seerr with your Jellyfin login once and your requests will show up here.
      </p>
    </section>

    <template v-else>
      <div role="group" aria-label="Show" class="mt-8 flex flex-wrap gap-2 px-4 sm:px-8 lg:px-12">
        <button
          v-for="option in FILTERS"
          :key="option.value"
          type="button"
          class="h-[38px] rounded-full px-[18px] text-sm font-bold transition"
          :class="filter === option.value ? 'bg-ink text-canvas' : 'bg-surface text-ink-2 hover:bg-elevated'"
          :aria-pressed="filter === option.value"
          @click="filter = option.value"
        >
          {{ option.label }}
        </button>
      </div>

      <SeerrUnavailable v-if="error" :status="null" :error="error" :on-retry="firstPage.refetch" />

      <div v-else-if="loading" class="mt-6 flex flex-col gap-3 px-4 sm:px-8 lg:px-12" aria-busy="true">
        <div v-for="n in 4" :key="n" class="h-[132px] animate-pulse rounded-panel bg-surface" />
      </div>

      <p v-else-if="!requests.length" class="mt-16 text-center text-muted">
        {{ filter === 'all' ? 'You haven\'t requested anything yet. Find something under Discover.' : 'Nothing here.' }}
      </p>

      <div
        v-else
        class="mt-6 flex flex-col gap-3 px-4 transition-opacity sm:px-8 lg:px-12"
        :class="firstPage.isFetching.value && !morePage.isFetching.value ? 'opacity-70' : 'opacity-100'"
      >
        <SeerrRequestCard v-for="request in requests" :key="request.id" :request="request" />
        <button
          v-if="hasMore"
          type="button"
          class="glass mx-auto mt-4 h-[46px] rounded-full px-6 text-[15px] font-bold text-ink disabled:opacity-60"
          :disabled="morePage.isFetching.value"
          @click="loadMore"
        >
          {{ morePage.isFetching.value ? 'Loading…' : 'Show more' }}
        </button>
      </div>
    </template>
  </main>
</template>
