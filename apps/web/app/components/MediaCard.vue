<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'
import type { JellyfinItem } from '~/types/jellyfin'

const props = withDefaults(defineProps<{
  item: JellyfinItem
  /** poster = 2:3 key art, landscape = 16:9 still/backdrop. */
  variant?: 'poster' | 'landscape'
  /** Small uppercase line above the title (e.g. "Continue"); episode links follow it. */
  kicker?: string | null
  /** Overrides the default title line under the art. */
  caption?: string | null
  /** Overrides the default secondary line under the art. */
  detail?: string | null
  /** Draws a white focus ring (current episode). */
  highlighted?: boolean
  /** Where the art links (default: the item's page). */
  to?: RouteLocationRaw
  /** Where the title links (default: the show for episodes, else the item). */
  titleTo?: RouteLocationRaw
  /** Show a play button over the art on hover (when `to` plays). */
  play?: boolean
  /**
   * Where an episode's "Season N, Episode N" links go: the line above the title, the line
   * below it, or nowhere. Auto = above on landscape cards, below on posters.
   */
  episodeLine?: 'auto' | 'kicker' | 'detail' | 'none'
  /** Art only: no link and no caption, for use inside another link. */
  bare?: boolean
  /** Scale the art up on hover. */
  zoom?: boolean
}>(), {
  variant: 'poster',
  kicker: null,
  caption: null,
  detail: null,
  highlighted: false,
  to: undefined,
  titleTo: undefined,
  play: false,
  episodeLine: 'auto',
  bare: false,
  zoom: true,
})

const NuxtLinkComponent = resolveComponent('NuxtLink')

const linkClass = 'underline decoration-transparent decoration-2 underline-offset-4 transition-colors hover:text-ink hover:decoration-current'

const { imageUrl, posterUrl } = useJellyfin()

const landscape = computed(() => props.variant === 'landscape')

const src = computed(() => {
  if (!landscape.value) return posterUrl(props.item, 360)
  // Episodes and extras have their own still as Primary; everything else uses the backdrop.
  if (props.item.type === 'Episode' || props.item.extraType) {
    return imageUrl(props.item, 'Primary', 720) ?? imageUrl(props.item, 'Backdrop', 720)
  }
  return imageUrl(props.item, 'Backdrop', 720) ?? imageUrl(props.item, 'Primary', 720)
})

const title = computed(() => props.caption ?? (props.item.seriesName || props.item.name))

const isEpisode = computed(() => props.item.type === 'Episode')

const episodeIn = computed(() => {
  if (!isEpisode.value || props.episodeLine === 'none') return null
  if (props.episodeLine === 'auto') return landscape.value ? 'kicker' : 'detail'
  return props.episodeLine
})

/** The title shows the episode's own name, so the show gets a link in the episode line. */
const showSeriesLink = computed(() => isEpisode.value && props.caption != null && Boolean(props.item.seriesId && props.item.seriesName))

const titleHref = computed(() => {
  if (props.titleTo) return props.titleTo
  if (props.caption == null && isEpisode.value && props.item.seriesId) return `/item/${props.item.seriesId}`
  return `/item/${props.item.id}`
})

const secondary = computed(() => {
  if (props.detail != null) return props.detail
  if (episodeIn.value === 'detail') return null
  if (landscape.value) return timeLeftLabel(props.item) ?? runtimeLabel(props.item.runTimeTicks)
  return props.item.productionYear ? String(props.item.productionYear) : null
})

const progress = computed(() => (isInProgress(props.item) ? Math.min(100, props.item.playedPercentage ?? 0) : 0))
const href = computed(() => props.to ?? `/item/${props.item.id}`)

const prefetchItem = usePrefetchItem()

/** The title an /item/:id or /watch/:id link opens; both pages start with that item's query. */
function prefetchTarget() {
  const target = href.value
  const path = typeof target === 'string' ? target : 'path' in target ? target.path : undefined
  const id = path?.match(/^\/(?:item|watch)\/([^/?#]+)/)?.[1]
  if (id) prefetchItem(id)
}
</script>

<template>
  <div class="block w-full">
    <component
      :is="bare ? 'div' : NuxtLinkComponent"
      :to="bare ? undefined : href"
      :aria-label="bare ? undefined : title"
      class="group relative block w-full"
      @pointerenter="bare ? undefined : prefetchTarget()"
      @focus="bare ? undefined : prefetchTarget()"
    >
      <div
        class="relative overflow-hidden rounded-card bg-surface shadow-[0_0_0_1px_rgba(255,255,255,0.06)] transition duration-300 group-hover:shadow-[0_18px_40px_rgba(0,0,0,0.55)]"
        :class="[
          zoom ? 'group-hover:scale-[1.03]' : '',
          landscape ? 'aspect-video' : 'aspect-[2/3]',
          highlighted ? 'ring-2 ring-ink ring-offset-[3px] ring-offset-canvas' : '',
        ]"
      >
        <img
          v-if="src"
          :src="src"
          :alt="item.name"
          class="absolute inset-0 size-full object-cover"
          :class="landscape ? 'object-center' : 'object-top'"
          loading="lazy"
        >
        <div
          v-else
          class="absolute inset-0 flex items-end p-4 text-[22px] font-extrabold leading-none tracking-[-1px] text-ink-2"
        >
          {{ item.seriesName || item.name }}
        </div>

        <!-- Extra art layered over the image, clipped to the card -->
        <slot name="art" />

        <span
          v-if="item.played"
          class="absolute right-2.5 top-2.5 grid size-[26px] place-items-center rounded-full bg-canvas/60 backdrop-blur-md"
          aria-label="Watched"
        >
          <svg class="size-[13px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M5 12.5l4.5 4.5L19 7.5" />
          </svg>
        </span>

        <div
          v-if="progress"
          class="absolute inset-x-3 bottom-2 h-1 overflow-hidden rounded-full bg-white/30"
        >
          <div class="h-full rounded-full bg-accent" :style="{ width: `${progress}%` }" />
        </div>
      </div>

      <span
        v-if="play"
        class="pointer-events-none absolute inset-0 grid place-items-center opacity-0 transition duration-200 group-hover:opacity-100 group-focus-visible:opacity-100"
      >
        <span class="glass grid size-14 place-items-center rounded-full">
          <svg class="ml-0.5 size-6" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
        </span>
      </span>
    </component>

    <div v-if="!bare" class="mt-2.5 flex min-w-0 flex-col gap-0.5">
      <span
        v-if="kicker || episodeIn === 'kicker'"
        class="truncate text-[13px] font-bold uppercase tracking-[0.5px] text-muted"
      >
        <template v-if="kicker">{{ kicker }}</template>
        <template v-if="episodeIn === 'kicker'">
          <template v-if="kicker"> · </template>
          <template v-if="showSeriesLink"><NuxtLink :to="`/item/${item.seriesId}`" :class="linkClass">{{ item.seriesName }}</NuxtLink> · </template>
          <EpisodeLinks :item="item" />
        </template>
      </span>
      <TitleLink
        :to="titleHref"
        truncate
        class="font-bold text-ink"
        :class="landscape ? 'text-base' : 'text-[15px]'"
      >{{ title }}</TitleLink>
      <span
        v-if="secondary || episodeIn === 'detail'"
        class="truncate text-[13px] font-semibold text-muted"
      >
        <template v-if="episodeIn === 'detail'">
          <template v-if="showSeriesLink"><NuxtLink :to="`/item/${item.seriesId}`" :class="linkClass">{{ item.seriesName }}</NuxtLink> · </template>
          <EpisodeLinks :item="item" />
          <template v-if="secondary"> · </template>
        </template>{{ secondary }}
      </span>
    </div>
  </div>
</template>
