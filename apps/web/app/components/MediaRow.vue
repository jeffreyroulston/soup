<script setup lang="ts">
import emblaCarouselVue from 'embla-carousel-vue'
import type { EmblaCarouselType } from 'embla-carousel'

const props = withDefaults(defineProps<{
  /** Optional while loading: a placeholder bar stands in for a title not known yet. */
  title?: string | null
  /** Number of slides; used to re-init Embla when the list changes. */
  count?: number
  /**
   * Show placeholder slides (the `skeleton` slot, or MediaCardSkeletons) in place of the
   * real ones. The row shows even with a `count` of 0.
   */
  loading?: boolean
  wide?: boolean
  seeAllTo?: string | null
  /** Changing this swaps the slides wholesale (e.g. a tab change): rewind to the start. */
  resetKey?: string | number | null
}>(), {
  title: null,
  count: 0,
  loading: false,
  wide: false,
  seeAllTo: null,
  resetKey: null,
})

const [emblaRef, emblaApi] = emblaCarouselVue({
  align: 'start',
  containScroll: 'trimSnaps',
  dragFree: true,
  skipSnaps: true,
})

const canPrev = ref(false)
const canNext = ref(false)

function syncButtons(api: EmblaCarouselType) {
  canPrev.value = api.canScrollPrev()
  canNext.value = api.canScrollNext()
}

watch(emblaApi, (api) => {
  if (!api) return
  syncButtons(api)
  api.on('select', syncButtons)
  api.on('reInit', syncButtons)
  api.on('settle', syncButtons)
})

const slideClass = computed(() => props.wide
  ? 'min-w-0 shrink-0 grow-0 basis-[min(82%,20rem)] sm:basis-[25rem]'
  : 'min-w-0 shrink-0 grow-0 basis-[8.5rem] sm:basis-[12.5rem]')

watch(() => [props.count, props.loading], () => {
  emblaApi.value?.reInit()
})

watch(() => props.resetKey, async () => {
  // Wait for the new slides to render before measuring them.
  await nextTick()
  emblaApi.value?.reInit()
  emblaApi.value?.scrollTo(0, true)
})
</script>

<template>
  <section
    v-if="count || loading"
    class="group/row flex flex-col gap-3.5"
    :aria-label="title ?? undefined"
    :aria-busy="loading || undefined"
  >
    <div class="flex items-baseline justify-between gap-4 px-4 sm:px-8 lg:px-12">
      <div class="flex min-w-0 flex-wrap items-center gap-x-4 gap-y-2">
        <h2 class="text-xl font-extrabold tracking-[-0.5px] text-ink sm:text-2xl">
          <template v-if="title">{{ title }}</template>
          <span v-else class="inline-block h-[0.8em] w-48 animate-pulse rounded bg-surface align-middle" />
        </h2>
        <slot name="header" />
      </div>
      <div class="flex items-center gap-2">
        <NuxtLink
          v-if="seeAllTo && !loading"
          :to="seeAllTo"
          class="text-[15px] font-bold text-muted hover:text-ink"
        >
          See All
        </NuxtLink>
        <div class="hidden gap-2 sm:flex">
          <button
            type="button"
            class="glass grid size-9 place-items-center rounded-full text-ink disabled:opacity-30"
            :disabled="loading || !canPrev"
            aria-label="Scroll back"
            @click="emblaApi?.scrollPrev()"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
          </button>
          <button
            type="button"
            class="glass grid size-9 place-items-center rounded-full text-ink disabled:opacity-30"
            :disabled="loading || !canNext"
            aria-label="Scroll forward"
            @click="emblaApi?.scrollNext()"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>
          </button>
        </div>
      </div>
    </div>

    <div ref="emblaRef" class="overflow-hidden px-4 py-3 -my-3 sm:px-8 lg:px-12">
      <div class="flex touch-pan-y gap-4 sm:gap-5">
        <template v-if="loading">
          <slot name="skeleton" :slide-class="slideClass">
            <div v-for="n in wide ? 4 : 8" :key="n" :class="slideClass">
              <MediaCardSkeleton :variant="wide ? 'landscape' : 'poster'" :kicker="wide" />
            </div>
          </slot>
        </template>
        <slot v-else :slide-class="slideClass" />
      </div>
    </div>
  </section>
</template>
