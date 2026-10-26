<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { JellyfinItem } from '~/types/jellyfin'

definePageMeta({ middleware: 'auth', layout: 'app' })

const { imageUrl } = useJellyfin()
const queries = useJellyfinQueries()
const playedMutation = usePlayedMutation()
const historyQuery = useQuery(queries.history())

/**
 * Rows toggled on this visit, as they were. Marking something unwatched drops it from
 * the server's list, and marking it watched again stamps it with today's date, so these
 * keep the row in place (dimmed) until the page is left.
 */
const toggled = ref(new Map<string, { original: JellyfinItem, played: boolean }>())

const items = computed(() => {
  const fetched = historyQuery.data.value ?? []
  const byId = new Map(fetched.map(item => [item.id, item]))
  const rows = fetched.map((item) => {
    const local = toggled.value.get(item.id)
    return local ? { ...item, lastPlayedDate: local.original.lastPlayedDate, played: local.played } : item
  })
  for (const [id, local] of toggled.value) {
    if (!byId.has(id)) rows.push({ ...local.original, played: local.played })
  }
  return rows.sort((a, b) => (b.lastPlayedDate ?? '').localeCompare(a.lastPlayedDate ?? ''))
})

const loading = computed(() => historyQuery.isPending.value)
const loadError = computed(() => (historyQuery.data.value ? null : historyQuery.error.value))

function togglePlayed(item: JellyfinItem) {
  const original = toggled.value.get(item.id)?.original ?? item
  toggled.value = new Map(toggled.value).set(item.id, { original, played: !item.played })
  playedMutation.mutate({ id: item.id, value: !item.played })
}

const DAY_MS = 86_400_000

function startOfDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
}

/** Today, Yesterday, Earlier this week, then by month. */
function groupLabel(iso: string | null | undefined, now: Date) {
  if (!iso) return 'Earlier'
  const date = new Date(iso)
  const days = Math.round((startOfDay(now) - startOfDay(date)) / DAY_MS)
  if (days <= 0) return 'Today'
  if (days === 1) return 'Yesterday'
  if (days < 7) return 'Earlier this week'
  return date.toLocaleDateString(undefined, {
    month: 'long',
    year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  })
}

/** A time for the last two days, a weekday this week, a date before that. */
function whenLabel(iso: string | null | undefined, now: Date) {
  if (!iso) return ''
  const date = new Date(iso)
  const days = Math.round((startOfDay(now) - startOfDay(date)) / DAY_MS)
  if (days <= 1) return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
  if (days < 7) return date.toLocaleDateString(undefined, { weekday: 'short' })
  return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
}

const groups = computed(() => {
  const now = new Date()
  const out: { label: string, rows: JellyfinItem[] }[] = []
  for (const item of items.value) {
    const label = groupLabel(item.lastPlayedDate, now)
    const last = out[out.length - 1]
    if (last?.label === label) last.rows.push(item)
    else out.push({ label, rows: [item] })
  }
  return out
})

function when(item: JellyfinItem) {
  return whenLabel(item.lastPlayedDate, new Date())
}

function thumb(item: JellyfinItem) {
  if (item.type === 'Episode') return imageUrl(item, 'Primary', 320) ?? imageUrl(item, 'Backdrop', 320)
  return imageUrl(item, 'Backdrop', 320) ?? imageUrl(item, 'Primary', 320)
}

function subBits(item: JellyfinItem) {
  if (item.type === 'Episode') {
    const s = item.parentIndexNumber
    const e = item.indexNumber
    const code = s != null && e != null ? `S${s}, E${e}` : e != null ? `E${e}` : null
    return [item.seriesName, code].filter((bit): bit is string => Boolean(bit))
  }
  return ['Movie', yearLabel(item)].filter((bit): bit is string => Boolean(bit))
}
</script>

<template>
  <main class="w-full pb-20 pt-24 sm:pt-28">
    <MyStuffHeader />

    <div class="flex max-w-[1100px] flex-col gap-3.5 px-4 pt-8 sm:px-8 sm:pt-9 lg:px-12">
      <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
        <h2 class="text-2xl font-extrabold tracking-[-0.5px]">
          Recently watched
        </h2>
      </div>

      <div v-if="loading" class="flex flex-col gap-1" aria-hidden="true">
        <span class="mb-1.5 mt-2.5 h-3 w-20 animate-pulse rounded bg-surface" />
        <div v-for="n in 6" :key="n" class="flex min-h-[76px] items-center gap-4 px-2.5 py-1.5">
          <span class="h-[58px] w-[104px] shrink-0 animate-pulse rounded-[10px] bg-surface" />
          <span class="flex flex-1 flex-col gap-2">
            <span class="h-3.5 w-48 max-w-full animate-pulse rounded bg-surface" />
            <span class="h-3 w-32 animate-pulse rounded bg-surface" />
          </span>
        </div>
      </div>
      <ErrorState v-else-if="loadError" compact :error="loadError" :on-retry="historyQuery.refetch" />
      <div v-else-if="!items.length" class="flex max-w-md flex-col items-start gap-3 pt-2">
        <span class="grid size-14 place-items-center rounded-full bg-surface text-accent">
          <svg class="size-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></svg>
        </span>
        <h3 class="text-xl font-extrabold tracking-[-0.5px]">
          Nothing watched yet
        </h3>
        <p class="text-[15px] leading-relaxed text-muted">
          Movies and episodes you finish will show up here.
        </p>
        <NuxtLink to="/" class="mt-1 inline-flex h-11 items-center rounded-full bg-surface px-5 text-sm font-bold transition hover:bg-elevated">
          Browse Home
        </NuxtLink>
      </div>
      <div v-else class="flex flex-col gap-4">
        <section v-for="group in groups" :key="group.label" :aria-label="group.label" class="flex flex-col gap-1">
          <h3 class="mb-1.5 mt-2.5 px-2.5 text-[13px] font-extrabold uppercase tracking-[1px] text-muted">
            {{ group.label }}
          </h3>
          <div
            v-for="item in group.rows"
            :key="item.id"
            class="flex min-h-[76px] items-center gap-3 rounded-[14px] px-2.5 py-1.5 transition sm:gap-4"
            :class="item.played ? '' : 'bg-surface/60 opacity-55'"
          >
            <NuxtLink :to="itemRoute(item)" class="group flex min-w-0 flex-1 items-center gap-3 sm:gap-4">
              <span class="relative h-[58px] w-[104px] shrink-0 overflow-hidden rounded-[10px] bg-surface">
                <img v-if="thumb(item)" :src="thumb(item)!" alt="" loading="lazy" class="size-full object-cover transition group-hover:brightness-110">
              </span>
              <span class="flex min-w-0 flex-1 flex-col gap-[3px]">
                <span class="truncate text-base font-extrabold group-hover:underline">{{ item.name }}</span>
                <span class="flex flex-wrap gap-x-2.5 text-sm font-semibold text-muted">
                  <span v-for="bit in subBits(item)" :key="bit" class="truncate">{{ bit }}</span>
                  <span class="tabular-nums sm:hidden">{{ when(item) }}</span>
                </span>
              </span>
            </NuxtLink>
            <span class="hidden shrink-0 text-sm font-semibold tabular-nums text-muted sm:inline">{{ when(item) }}</span>
            <button
              type="button"
              class="grid size-10 shrink-0 place-items-center rounded-full border text-sm font-bold transition sm:flex sm:w-auto sm:min-w-[160px] sm:justify-center sm:px-4"
              :class="item.played ? 'border-ink bg-ink text-canvas hover:bg-ink/80 sm:border-white/20 sm:bg-transparent sm:text-ink sm:hover:bg-white/10' : 'border-white/20 text-ink hover:bg-white/10'"
              :aria-label="item.played ? `Mark ${item.name} unwatched` : `Mark ${item.name} watched`"
              @click="togglePlayed(item)"
            >
              <svg class="size-[18px] sm:hidden" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
              <span class="hidden sm:inline" aria-hidden="true">{{ item.played ? 'Mark unwatched' : 'Mark watched' }}</span>
            </button>
          </div>
        </section>
      </div>
    </div>
  </main>
</template>
