<script setup lang="ts">
import type { SeerrTitle } from '~/types/seerr'

/** A Seerr title as a poster card, in MediaCard's clothes, with its library status in the corner. */
const props = withDefaults(defineProps<{
  title: SeerrTitle
  /** Overrides the default secondary line (kind and year). */
  detail?: string | null
}>(), { detail: null })

const poster = computed(() => tmdbImage(props.title.posterPath, 'poster'))
const href = computed(() => seerrTitleRoute(props.title))
const secondary = computed(() => props.detail
  ?? [mediaTypeLabel(props.title.mediaType), props.title.year].filter(Boolean).join(', '))
const availability = computed(() => availabilityLabel(props.title.mediaInfo))
const tone = computed(() => availabilityTone(props.title.mediaInfo))
</script>

<template>
  <div class="group/card relative block w-full">
    <NuxtLink :to="href" :aria-label="title.title" class="group relative block w-full">
      <div
        class="relative aspect-[2/3] overflow-hidden rounded-card bg-surface shadow-[0_0_0_1px_rgba(255,255,255,0.06)] transition duration-300 group-hover:scale-[1.03] group-hover:shadow-[0_18px_40px_rgba(0,0,0,0.55)]"
      >
        <img
          v-if="poster"
          :src="poster"
          :alt="title.title"
          class="absolute inset-0 size-full object-cover object-top"
          loading="lazy"
        >
        <div
          v-else
          class="absolute inset-0 flex items-end p-4 text-[22px] font-extrabold leading-none tracking-[-1px] text-ink-2"
        >
          {{ title.title }}
        </div>

        <span
          v-if="availability"
          class="absolute right-2.5 top-2.5 grid size-[26px] place-items-center rounded-full backdrop-blur-md"
          :class="tone === 'ok' ? 'bg-ok text-canvas' : tone === 'partial' ? 'bg-ok/70 text-canvas' : 'bg-accent text-canvas'"
          :aria-label="availability"
          :title="availability"
        >
          <svg v-if="tone === 'ok' || tone === 'partial'" class="size-[13px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M5 12.5l4.5 4.5L19 7.5" />
          </svg>
          <svg v-else class="size-[17px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="9.5" /><path d="M12 6.5V12l3.5 2.5" />
          </svg>
        </span>
      </div>
    </NuxtLink>

    <div class="mt-2.5 flex min-w-0 flex-col gap-0.5">
      <TitleLink :to="href" truncate class="text-[15px] font-bold text-ink">{{ title.title }}</TitleLink>
      <span v-if="secondary" class="truncate text-[13px] font-semibold text-muted">{{ secondary }}</span>
    </div>
  </div>
</template>
