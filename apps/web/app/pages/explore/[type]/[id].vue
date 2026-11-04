<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { SeerrMediaType, SeerrRequestPayload } from '~/types/seerr'
import { SEERR_MEDIA_STATUS } from '~/types/seerr'

definePageMeta({ middleware: 'auth', layout: 'app' })

const route = useRoute()
const seerr = useSeerrStatus()
const queries = useSeerrQueries()
const jellyfin = useJellyfin()

const mediaType = computed<SeerrMediaType | null>(() => {
  const type = String(route.params.type)
  return type === 'movie' || type === 'tv' ? type : null
})
const tmdbId = computed(() => {
  const id = Number(route.params.id)
  return Number.isInteger(id) && id > 0 ? id : null
})
const valid = computed(() => mediaType.value !== null && tmdbId.value !== null)
const usable = computed(() => seerr.status.value?.configured === true && seerr.status.value.reachable)

const detailsQuery = useQuery(computed(() => ({
  ...queries.details(mediaType.value ?? 'movie', tmdbId.value ?? 0),
  enabled: valid.value && usable.value,
})))
const details = computed(() => detailsQuery.data.value ?? null)
const loading = computed(() => valid.value && usable.value && detailsQuery.isPending.value)
const loadError = computed(() => (details.value ? null : detailsQuery.error.value))
const notFound = computed(() => !valid.value || (loadError.value instanceof SeerrError && loadError.value.status === 404))

const isShow = computed(() => mediaType.value === 'tv')
const info = computed(() => details.value?.mediaInfo ?? null)
const backdrop = computed(() => tmdbImage(details.value?.backdropPath, 'backdrop'))
const poster = computed(() => tmdbImage(details.value?.posterPath, 'poster'))
const inLibrary = computed(() => isInLibrary(info.value))
const availability = computed(() => availabilityLabel(info.value))
const tone = computed(() => availabilityTone(info.value))

/**
 * Where to watch: the Jellyfin item Seerr linked, or failing that the library's copy found
 * by TMDB id (Seerr doesn't always record the link).
 */
const matchQuery = useQuery(computed(() => ({
  queryKey: queryKeys.seerrLibraryMatch(mediaType.value ?? 'movie', tmdbId.value ?? 0),
  queryFn: () => jellyfin.findByTmdbId(tmdbId.value!, isShow.value ? 'Series' : 'Movie', details.value?.title ?? ''),
  enabled: Boolean(details.value) && inLibrary.value && !info.value?.jellyfinMediaId,
  staleTime: 10 * 60_000,
})))
const watchTo = computed(() => {
  if (!inLibrary.value) return null
  const linked = info.value?.jellyfinMediaId
  if (linked) return `/item/${linked}`
  const matched = matchQuery.data.value
  return matched ? `/item/${matched.id}` : null
})

const metaBits = computed(() => {
  const d = details.value
  if (!d) return []
  return [
    d.year ? String(d.year) : null,
    isShow.value && d.seasons.length ? `${d.seasons.length} season${d.seasons.length === 1 ? '' : 's'}` : null,
    runtimeMinutesLabel(d.runtime) ? `${runtimeMinutesLabel(d.runtime)}${isShow.value ? ' episodes' : ''}` : null,
    d.status,
    d.voteAverage ? `★ ${d.voteAverage.toFixed(1)}` : null,
  ].filter((bit): bit is string => Boolean(bit))
})
const chips = computed(() => (details.value?.contentRating ? [details.value.contentRating] : []))
const genres = computed(() => details.value?.genres.join(', ') ?? '')
const trailer = computed(() => details.value?.trailerUrl ?? null)

// Requesting
const canRequest = computed(() => mediaType.value != null && seerr.canRequest(mediaType.value))
const requestable = computed(() => details.value != null && !nothingToRequest(info.value, isShow.value ? details.value.seasons : []))
const pickingSeasons = ref(false)
const chosenSeasons = ref<number[]>([])
/** Seasons with nothing in the library and no live request: the ones worth asking for. */
const openSeasons = computed(() => (details.value?.seasons ?? []).filter(season => seasonStatus(info.value, season.seasonNumber) === null))

function startRequest() {
  if (!isShow.value) {
    submit({ mediaType: 'movie', mediaId: tmdbId.value! })
    return
  }
  chosenSeasons.value = openSeasons.value.map(season => season.seasonNumber)
  pickingSeasons.value = true
}

function toggleSeason(seasonNumber: number) {
  chosenSeasons.value = chosenSeasons.value.includes(seasonNumber)
    ? chosenSeasons.value.filter(n => n !== seasonNumber)
    : [...chosenSeasons.value, seasonNumber]
}

const requestMutation = useSeerrRequestMutation()
const requestError = computed(() => {
  const error = requestMutation.error.value
  if (!error) return null
  if (error instanceof SeerrError && error.code === 'seerr_user_not_linked') {
    return 'No Seerr account is linked to your Jellyfin login. Sign in to Seerr with Jellyfin once, then try again.'
  }
  return error instanceof Error ? error.message : 'The request failed.'
})

function submit(payload: SeerrRequestPayload) {
  requestMutation.mutate(payload, { onSuccess: () => { pickingSeasons.value = false } })
}

function submitSeasons() {
  if (!chosenSeasons.value.length) return
  const all = chosenSeasons.value.length === openSeasons.value.length
    && openSeasons.value.length === (details.value?.seasons.length ?? 0)
  submit({
    mediaType: 'tv',
    mediaId: tmdbId.value!,
    tvdbId: details.value?.tvdbId ?? undefined,
    seasons: all ? 'all' : [...chosenSeasons.value].sort((a, b) => a - b),
  })
}

const requestLabel = computed(() => {
  if (requestMutation.isPending.value) return 'Requesting…'
  if (!requestable.value) return availability.value ?? 'Requested'
  if (isShow.value && info.value && info.value.status !== SEERR_MEDIA_STATUS.UNKNOWN) return 'Request more seasons'
  return isShow.value ? 'Request seasons' : 'Request'
})

watch(() => route.fullPath, () => {
  pickingSeasons.value = false
  requestMutation.reset()
})

useHead(() => ({ title: details.value ? `${details.value.title} · Explore` : 'Explore' }))
</script>

<template>
  <main class="w-full pb-20">
    <template v-if="!seerr.loaded.value || loading">
      <div class="min-h-[min(70vh,600px)] animate-pulse bg-surface" aria-busy="true" />
    </template>

    <SeerrUnavailable v-else-if="!usable" class="pt-32" :status="seerr.status.value" :error="seerr.error.value" :on-retry="seerr.refetch" />

    <section v-else-if="notFound" class="mx-auto flex w-full max-w-[520px] flex-col items-center px-4 pt-40 text-center">
      <h1 class="text-[30px] font-extrabold leading-tight tracking-[-0.8px]">
        This title isn't on TMDB
      </h1>
      <p class="mt-3 text-[15px] leading-relaxed text-muted">
        Seerr has nothing under this id. It may have been removed or merged.
      </p>
      <NuxtLink to="/explore" class="mt-6 grid h-[46px] place-items-center rounded-full bg-ink px-6 text-[15px] font-bold text-canvas transition hover:bg-ink/80">
        Back to Explore
      </NuxtLink>
    </section>

    <SeerrUnavailable v-else-if="loadError" class="pt-32" :status="null" :error="loadError" :on-retry="detailsQuery.refetch" />

    <template v-else-if="details">
      <!-- Hero: full-bleed backdrop, in the item page's layout -->
      <section :aria-label="details.title" class="relative w-full min-h-[min(80vh,680px)]">
        <div class="absolute inset-0 bg-surface">
          <img v-if="backdrop" :src="backdrop" alt="" class="absolute inset-0 size-full object-cover object-top">
          <img v-else-if="poster" :src="poster" alt="" class="absolute inset-0 size-full object-cover object-top opacity-40 blur-2xl">
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/75 via-40% to-transparent to-75%" />

        <div class="relative flex min-h-[min(80vh,680px)] flex-wrap items-end justify-between gap-8 px-4 pb-6 pt-32 sm:px-8 lg:px-12">
          <div class="flex max-w-[820px] flex-col gap-4">
            <span class="text-sm font-extrabold uppercase tracking-[1px] text-accent">
              {{ mediaTypeLabel(details.mediaType) }}
            </span>
            <h1 class="text-balance font-extrabold tracking-[-0.04em]" :class="heroTitleClass(details.title)">
              {{ details.title }}
            </h1>
            <p v-if="details.tagline" class="text-[17px] font-semibold italic text-ink-2">
              {{ details.tagline }}
            </p>
            <div class="flex flex-wrap items-center gap-x-[18px] gap-y-2 text-[15px] font-semibold text-ink-2">
              <span v-for="bit in metaBits" :key="bit">{{ bit }}</span>
              <span v-for="chip in chips" :key="chip" class="rounded bg-white/20 px-1.5 py-px text-xs font-extrabold text-ink">{{ chip }}</span>
              <span
                v-if="availability"
                class="rounded-full px-2.5 py-0.5 text-xs font-extrabold"
                :class="tone === 'ok' || tone === 'partial' ? 'bg-ok/20 text-ok' : 'bg-accent/20 text-accent'"
              >{{ availability }}</span>
            </div>

            <div class="flex flex-wrap items-center gap-3">
              <NuxtLink
                v-if="watchTo"
                :to="watchTo"
                class="inline-flex h-[52px] items-center gap-2 rounded-full bg-ink px-7 text-[17px] font-extrabold text-canvas transition hover:bg-ink/85"
              >
                <svg class="size-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
                Watch in Soup
              </NuxtLink>
              <span v-else-if="inLibrary && matchQuery.isFetching.value" class="text-[13px] font-semibold text-muted">Finding it in your library…</span>

              <!-- Already in the library: the availability chip says so, no dead button needed -->
              <template v-if="inLibrary && !requestable" />
              <button
                v-else-if="canRequest || !seerr.user.value"
                type="button"
                class="inline-flex h-[52px] items-center gap-2 rounded-full px-7 text-[17px] font-extrabold transition disabled:opacity-70"
                :class="watchTo ? 'glass text-ink' : 'bg-accent text-canvas hover:bg-accent/90'"
                :disabled="!requestable || requestMutation.isPending.value || (pickingSeasons && isShow)"
                @click="startRequest"
              >
                <svg v-if="requestable" class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
                <svg v-else class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
                {{ requestLabel }}
              </button>
              <span v-else class="text-[13px] font-semibold text-muted">Your Seerr account can't request {{ isShow ? 'shows' : 'movies' }}.</span>

              <a
                v-if="trailer"
                :href="trailer"
                target="_blank"
                rel="noopener"
                class="glass grid size-[52px] shrink-0 place-items-center rounded-full text-ink"
                aria-label="Watch trailer"
                title="Trailer"
              >
                <svg class="size-[20px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4" /></svg>
              </a>
            </div>

            <p v-if="requestError" role="alert" class="text-[15px] font-semibold text-accent">
              {{ requestError }}
            </p>
          </div>
        </div>
      </section>

      <div class="flex flex-col gap-12 px-4 pt-6 sm:px-8 lg:px-12">
        <!-- Season picker -->
        <section v-if="pickingSeasons && isShow" aria-label="Choose seasons" class="max-w-[820px] rounded-panel bg-surface p-5 sm:p-6">
          <div class="flex flex-wrap items-baseline justify-between gap-3">
            <h2 class="text-xl font-extrabold tracking-[-0.5px]">
              Which seasons?
            </h2>
            <button type="button" class="text-[13px] font-bold text-muted hover:text-ink" @click="chosenSeasons = chosenSeasons.length === openSeasons.length ? [] : openSeasons.map(s => s.seasonNumber)">
              {{ chosenSeasons.length === openSeasons.length ? 'Clear' : 'Select all' }}
            </button>
          </div>
          <ul class="mt-4 grid gap-2 sm:grid-cols-2">
            <li v-for="season in details.seasons" :key="season.seasonNumber">
              <label
                class="flex h-12 items-center gap-3 rounded-btn px-3 transition"
                :class="seasonStatus(info, season.seasonNumber) === null ? 'cursor-pointer bg-elevated/60 hover:bg-elevated' : 'opacity-60'"
              >
                <input
                  type="checkbox"
                  class="size-4 accent-[var(--color-accent)]"
                  :checked="chosenSeasons.includes(season.seasonNumber)"
                  :disabled="seasonStatus(info, season.seasonNumber) !== null"
                  @change="toggleSeason(season.seasonNumber)"
                >
                <span class="min-w-0 flex-1 truncate text-[15px] font-bold">{{ season.name }}</span>
                <span class="text-[12px] font-semibold text-muted">
                  {{ seasonStatusLabel(seasonStatus(info, season.seasonNumber)) ?? `${season.episodeCount} ep` }}
                </span>
              </label>
            </li>
          </ul>
          <div class="mt-5 flex flex-wrap gap-3">
            <button
              type="button"
              class="h-11 rounded-full bg-accent px-6 text-[15px] font-extrabold text-canvas transition hover:bg-accent/90 disabled:opacity-60"
              :disabled="!chosenSeasons.length || requestMutation.isPending.value"
              @click="submitSeasons"
            >
              {{ requestMutation.isPending.value ? 'Requesting…' : `Request ${chosenSeasons.length} season${chosenSeasons.length === 1 ? '' : 's'}` }}
            </button>
            <button type="button" class="glass h-11 rounded-full px-6 text-[15px] font-bold text-ink" @click="pickingSeasons = false">
              Cancel
            </button>
          </div>
        </section>

        <!-- Overview -->
        <section v-if="details.overview || genres" aria-label="About" class="grid max-w-[1100px] gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] lg:gap-12">
          <OverviewText v-if="details.overview" :id="`${details.mediaType}-${details.tmdbId}`" :text="details.overview" />
          <dl class="flex flex-col gap-3 text-[15px]">
            <div v-if="genres">
              <dt class="text-[12px] font-extrabold uppercase tracking-[0.6px] text-muted">Genres</dt>
              <dd class="font-semibold text-ink-2">{{ genres }}</dd>
            </div>
            <div v-if="details.networks.length">
              <dt class="text-[12px] font-extrabold uppercase tracking-[0.6px] text-muted">Network</dt>
              <dd class="font-semibold text-ink-2">{{ details.networks.join(', ') }}</dd>
            </div>
            <div v-if="details.releaseDate">
              <dt class="text-[12px] font-extrabold uppercase tracking-[0.6px] text-muted">{{ isShow ? 'First aired' : 'Released' }}</dt>
              <dd class="font-semibold text-ink-2">{{ shortDate(details.releaseDate) }}</dd>
            </div>
            <div v-if="details.imdbId">
              <dt class="text-[12px] font-extrabold uppercase tracking-[0.6px] text-muted">More</dt>
              <dd class="font-semibold text-ink-2">
                <a :href="`https://www.imdb.com/title/${details.imdbId}/`" target="_blank" rel="noopener" class="underline decoration-white/30 underline-offset-4 hover:text-ink">IMDb</a>
                <span class="mx-2 text-muted">·</span>
                <a :href="`https://www.themoviedb.org/${details.mediaType}/${details.tmdbId}`" target="_blank" rel="noopener" class="underline decoration-white/30 underline-offset-4 hover:text-ink">TMDB</a>
              </dd>
            </div>
          </dl>
        </section>

        <!-- Seasons at a glance (when not picking) -->
        <section v-if="isShow && details.seasons.length && !pickingSeasons" aria-label="Seasons" class="flex flex-col gap-3.5">
          <h2 class="text-xl font-extrabold tracking-[-0.5px] sm:text-2xl">
            Seasons
          </h2>
          <ul class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            <li
              v-for="season in details.seasons"
              :key="season.seasonNumber"
              class="flex h-12 items-center gap-3 rounded-btn bg-surface px-3"
            >
              <span class="min-w-0 flex-1 truncate text-[15px] font-bold">{{ season.name }}</span>
              <span class="text-[12px] font-semibold" :class="seasonStatus(info, season.seasonNumber) === SEERR_MEDIA_STATUS.AVAILABLE ? 'text-ok' : seasonStatus(info, season.seasonNumber) ? 'text-accent' : 'text-muted'">
                {{ seasonStatusLabel(seasonStatus(info, season.seasonNumber)) ?? `${season.episodeCount} episodes` }}
              </span>
            </li>
          </ul>
        </section>

        <!-- Cast -->
        <section v-if="details.cast.length" aria-label="Cast" class="-mx-4 flex flex-col gap-3.5 sm:-mx-8 lg:-mx-12">
          <h2 class="px-4 text-xl font-extrabold tracking-[-0.5px] sm:px-8 sm:text-2xl lg:px-12">
            Cast
          </h2>
          <div class="rail flex gap-7 overflow-x-auto px-4 sm:px-8 lg:px-12">
            <div v-for="member in details.cast" :key="member.id" class="flex w-[112px] shrink-0 flex-col items-center gap-2.5 text-center sm:w-32">
              <span class="relative grid size-[112px] place-items-center overflow-hidden rounded-full bg-surface text-[32px] font-extrabold text-ink-2 sm:size-32">
                <img
                  v-if="tmdbImage(member.profilePath, 'profile')"
                  :src="tmdbImage(member.profilePath, 'profile')!"
                  :alt="member.name"
                  class="absolute inset-0 size-full object-cover"
                  loading="lazy"
                >
                <template v-else>{{ initials(member.name) }}</template>
              </span>
              <span class="text-[15px] font-bold">{{ member.name }}</span>
              <span v-if="member.character" class="line-clamp-2 text-[12px] font-semibold text-muted">{{ member.character }}</span>
            </div>
          </div>
        </section>
      </div>
    </template>
  </main>
</template>
