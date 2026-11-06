<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { SeerrMediaType } from '~/types/seerr'

/** "Browse by genre": big tinted backdrop tiles, movies or shows, each opening the genre's listing. */
const queries = useSeerrQueries()
const mediaType = ref<SeerrMediaType>('movie')

const genresQuery = useQuery(computed(() => queries.genres(mediaType.value)))
const genres = computed(() => genresQuery.data.value ?? [])

const TYPES: { value: SeerrMediaType, label: string }[] = [
  { value: 'movie', label: 'Movies' },
  { value: 'tv', label: 'Shows' },
]

/** The slider's backdrops come from the genre's top titles; pick a steady one per genre. */
function backdropFor(backdrops: string[], id: number): string | null {
  return tmdbImage(backdrops[id % backdrops.length], 'thumb')
}
</script>

<template>
  <MediaRow
    v-if="!genresQuery.error.value"
    title="Browse by Genre"
    :count="genres.length"
    :loading="genresQuery.isPending.value"
    :reset-key="mediaType"
    wide
  >
    <template #header>
      <div class="flex gap-1 rounded-full bg-surface p-1" role="group" aria-label="Genres for">
        <button
          v-for="type in TYPES"
          :key="type.value"
          type="button"
          class="h-8 rounded-full px-3.5 text-[13px] transition"
          :class="mediaType === type.value ? 'bg-ink font-extrabold text-canvas' : 'font-bold text-muted hover:text-ink'"
          :aria-pressed="mediaType === type.value"
          @click="mediaType = type.value"
        >
          {{ type.label }}
        </button>
      </div>
    </template>

    <template #skeleton="{ slideClass }">
      <div v-for="n in 4" :key="n" :class="slideClass">
        <div class="aspect-[16/9] animate-pulse rounded-card bg-surface" />
      </div>
    </template>

    <template #default="{ slideClass }">
      <div v-for="genre in genres" :key="`${mediaType}-${genre.id}`" :class="slideClass">
        <NuxtLink
          :to="seerrGenreRoute(mediaType, genre.id)"
          class="group relative block aspect-[16/9] overflow-hidden rounded-card bg-surface shadow-[0_0_0_1px_rgba(255,255,255,0.06)] transition duration-300 hover:scale-[1.03] hover:shadow-[0_18px_40px_rgba(0,0,0,0.55)]"
          :style="{ '--tint': genreTint(genre.id) }"
        >
          <img
            v-if="backdropFor(genre.backdrops, genre.id)"
            :src="backdropFor(genre.backdrops, genre.id)!"
            alt=""
            class="absolute inset-0 size-full object-cover grayscale transition duration-500 group-hover:scale-105"
            loading="lazy"
          >
          <!-- Duotone-ish wash: the genre's colour multiplied over a grey backdrop -->
          <div class="absolute inset-0 bg-[var(--tint)] mix-blend-multiply" />
          <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/10 to-transparent" />
          <span class="absolute inset-x-4 bottom-3.5 text-[22px] font-extrabold leading-tight tracking-[-0.5px] text-white sm:text-[26px]">
            {{ genre.name }}
          </span>
        </NuxtLink>
      </div>
    </template>
  </MediaRow>
</template>
