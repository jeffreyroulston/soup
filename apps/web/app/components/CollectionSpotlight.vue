<script setup lang="ts">
import type { JellyfinCollection, SoupCuratedCollection } from '~/types/jellyfin'

const props = withDefaults(defineProps<{
  /** Soup hard-coded pack matched to this library. */
  curated?: SoupCuratedCollection | null
  /** Jellyfin BoxSet fallback when no curated packs match. */
  spotlight?: JellyfinCollection | null
  loading?: boolean
}>(), {
  curated: null,
  spotlight: null,
  loading: false,
})

const { imageUrl, posterUrl } = useJellyfin()

const title = computed(() => props.curated?.title ?? props.spotlight?.collection.name ?? '')
const description = computed(() =>
  props.curated?.description
  ?? props.spotlight?.collection.overview
  ?? '')
const countLabel = computed(() =>
  props.curated?.countLabel
  ?? (props.spotlight ? `${props.spotlight.items.length} titles` : ''))
const to = computed(() =>
  props.curated?.to
  ?? (props.spotlight ? `/item/${props.spotlight.collection.id}` : '#'))

const items = computed(() => props.curated?.items ?? props.spotlight?.items ?? [])

const backdrop = computed(() => {
  const spot = props.spotlight
  const sources = [...(spot ? [spot.collection] : []), ...items.value]
  for (const item of sources) {
    const url = imageUrl(item, 'Backdrop', 1600)
    if (url) return url
  }
  return null
})

/** Up to four posters, shown side by side on the right. */
const posters = computed(() =>
  items.value
    .map(item => ({ id: item.id, name: item.name, src: posterUrl(item, 360) }))
    .filter(p => p.src)
    .slice(0, 4))

/** Slanted panels: each leans the same way, the last one runs off the card's edge. */
function panelClip(i: number, count: number) {
  return i === count - 1
    ? 'polygon(14% 0, 100% 0, 100% 100%, 0 100%)'
    : 'polygon(14% 0, 100% 0, 86% 100%, 0 100%)'
}
</script>

<template>
  <section
    v-if="loading"
    aria-hidden="true"
    class="relative mx-4 h-[420px] overflow-hidden rounded-[28px] bg-surface sm:mx-8 sm:h-[400px] lg:mx-12"
  >
    <div class="absolute inset-x-6 bottom-8 flex max-w-[480px] flex-col gap-3.5 sm:inset-x-14">
      <span class="text-sm font-bold"><span class="inline-block h-[0.8em] w-36 animate-pulse rounded bg-elevated align-middle" /></span>
      <span class="block h-[calc(clamp(2.25rem,4vw,3.4rem)*0.95)] w-2/3 animate-pulse rounded-btn bg-elevated" />
      <span class="h-[46px] w-44 animate-pulse rounded-full bg-elevated" />
    </div>
  </section>

  <section
    v-else-if="curated || spotlight"
    :aria-label="`${title} collection`"
    class="relative mx-4 block h-[420px] overflow-hidden rounded-[28px] bg-surface sm:mx-8 sm:h-[400px] lg:mx-12"
  >
    <img
      v-if="backdrop"
      :src="backdrop"
      alt=""
      class="absolute inset-0 size-full object-cover object-top"
      loading="lazy"
    >
    <!-- Same scrims as the hero -->
    <div class="absolute inset-0 bg-gradient-to-t from-canvas via-canvas/60 via-30% to-transparent to-60%" />
    <div class="absolute inset-0 bg-gradient-to-r from-canvas/70 via-canvas/10 via-45% to-transparent" />

    <!--
      Full-bleed posters cut on a diagonal, side by side. Phones get them as a
      strip across the top that fades into the backdrop; wider screens get them
      down the right side, narrower until there's room for the copy beside them.
      Each poster opens its film; the clip path is also its hit area.
    -->
    <div
      class="absolute inset-x-0 top-0 flex h-[42%] [mask-image:linear-gradient(to_bottom,#000_45%,transparent)] sm:inset-y-0 sm:left-auto sm:h-auto sm:w-[42%] sm:[mask-image:none] xl:w-[52%]"
    >
      <NuxtLink
        v-for="(poster, i) in posters"
        :key="poster.id"
        :to="`/item/${poster.id}`"
        :aria-label="poster.name"
        class="h-full min-w-0 flex-1 opacity-90 transition-opacity duration-500 hover:opacity-100 focus-visible:opacity-100"
        :class="i > 0 && '-ml-[3.5%]'"
        :style="{ clipPath: panelClip(i, posters.length) }"
      >
        <img :src="poster.src!" alt="" class="size-full object-cover" loading="lazy">
      </NuxtLink>
    </div>

    <!-- Copy stops short of the posters so it never runs over them -->
    <div class="absolute inset-x-6 bottom-8 flex max-w-[520px] flex-col gap-3 sm:bottom-12 sm:left-14 sm:right-[calc(42%+1.5rem)] xl:right-[calc(52%+1.5rem)]">
      <span class="text-sm font-bold text-ink-2">
        Collection · {{ countLabel }}
      </span>
      <h2 class="text-balance text-[clamp(2.25rem,4vw,3.4rem)] font-extrabold leading-[0.95] tracking-[-0.04em] text-white">
        {{ title }}
      </h2>
      <p v-if="description" class="line-clamp-3 text-base leading-relaxed text-white/80 xl:line-clamp-2">
        {{ description }}
      </p>
      <NuxtLink
        :to="to"
        class="mt-1 inline-flex h-[46px] items-center self-start rounded-full bg-white px-6 text-base font-extrabold text-black transition hover:bg-white/90"
      >
        Watch the collection
      </NuxtLink>
    </div>
  </section>
</template>
