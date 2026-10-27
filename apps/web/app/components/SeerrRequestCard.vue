<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { SeerrRequest } from '~/types/seerr'
import { SEERR_REQUEST_STATUS } from '~/types/seerr'

/**
 * One of the user's requests as a row: poster, title, what was asked for, where it stands.
 * Seerr's request list carries only ids, so the title comes from the (cached) details query.
 */
const props = defineProps<{
  request: SeerrRequest
}>()

const queries = useSeerrQueries()
const detailsQuery = useQuery(computed(() => queries.details(props.request.mediaType, props.request.tmdbId)))
const details = computed(() => detailsQuery.data.value ?? null)
const poster = computed(() => tmdbImage(details.value?.posterPath, 'poster'))
const href = computed(() => seerrTitleRoute(props.request))
const status = computed(() => requestStatusLabel(props.request))
const seasons = computed(() => seasonsLabel(props.request))
const requested = computed(() => shortDate(props.request.createdAt))
const canWithdraw = computed(() => props.request.status === SEERR_REQUEST_STATUS.PENDING)
/** The library's copy, when Seerr linked one, so a finished request plays from here. */
const watchTo = computed(() => {
  const info = details.value?.mediaInfo
  return info && isInLibrary(info) && info.jellyfinMediaId ? `/item/${info.jellyfinMediaId}` : null
})

const cancel = useSeerrCancelMutation()
const cancelError = computed(() => cancel.error.value instanceof Error ? cancel.error.value.message : null)

const TONES: Record<string, string> = {
  ok: 'bg-ok/15 text-ok',
  partial: 'bg-ok/15 text-ok',
  pending: 'bg-accent/15 text-accent',
  declined: 'bg-white/10 text-muted',
}
</script>

<template>
  <article class="flex gap-4 rounded-panel bg-surface p-3 sm:gap-5 sm:p-4" :aria-label="details?.title ?? 'Request'">
    <NuxtLink :to="href" class="relative block w-[72px] shrink-0 overflow-hidden rounded-[10px] bg-elevated sm:w-24" :aria-label="details?.title ?? 'Open title'">
      <span class="block aspect-[2/3]">
        <img v-if="poster" :src="poster" :alt="details?.title ?? ''" class="absolute inset-0 size-full object-cover" loading="lazy">
      </span>
    </NuxtLink>

    <div class="flex min-w-0 flex-1 flex-col gap-1.5">
      <div class="min-w-0">
        <TitleLink v-if="details" :to="href" class="text-[17px] font-extrabold text-ink">{{ details.title }}</TitleLink>
        <span v-else class="inline-block h-[0.9em] w-40 animate-pulse rounded bg-elevated align-middle" />
        <p class="truncate text-[13px] font-semibold text-muted">
          {{ [mediaTypeLabel(request.mediaType), details?.year, seasons, request.is4k ? '4K' : null].filter(Boolean).join(' · ') }}
        </p>
      </div>

      <p v-if="requested" class="text-[13px] font-semibold text-muted">
        Requested {{ requested }}
      </p>

      <div class="mt-auto flex flex-wrap items-center gap-2 pt-1">
        <NuxtLink
          v-if="watchTo"
          :to="watchTo"
          class="inline-flex h-9 items-center gap-1.5 rounded-full bg-ink px-4 text-[13px] font-bold text-canvas transition hover:bg-ink/80"
        >
          <svg class="size-3.5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
          Watch
        </NuxtLink>
        <button
          v-if="canWithdraw"
          type="button"
          class="glass inline-flex h-9 items-center rounded-full px-4 text-[13px] font-bold text-ink disabled:opacity-60"
          :disabled="cancel.isPending.value"
          @click="cancel.mutate(request.id)"
        >
          {{ cancel.isPending.value ? 'Withdrawing…' : 'Withdraw' }}
        </button>
        <span v-if="cancelError" role="alert" class="text-[13px] font-semibold text-accent">{{ cancelError }}</span>
        <span class="ml-auto shrink-0 rounded-full px-2.5 py-1 text-[12px] font-extrabold" :class="TONES[status.tone]">
          {{ status.label }}
        </span>
      </div>
    </div>
  </article>
</template>
