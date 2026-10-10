<script setup lang="ts">
import emblaCarouselVue from 'embla-carousel-vue'
import type { EmblaCarouselType } from 'embla-carousel'

const props = withDefaults(defineProps<{
  title: string
  /** Number of slides; used to re-init Embla when the list changes. */
  count: number
  wide?: boolean
  seeAllTo?: string | null
}>(), {
  wide: false,
  seeAllTo: null,
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

watch(() => props.count, () => {
  emblaApi.value?.reInit()
})
</script>

<template>
  <section v-if="count" class="group/row flex flex-col gap-3.5" :aria-label="title">
    <div class="flex items-baseline justify-between gap-4 px-4 sm:px-8 lg:px-12">
      <h2 class="text-xl font-extrabold tracking-[-0.5px] text-ink sm:text-2xl">
        {{ title }}
      </h2>
      <div class="flex items-center gap-2">
        <NuxtLink
          v-if="seeAllTo"
          :to="seeAllTo"
          class="text-[15px] font-bold text-muted hover:text-ink"
        >
          See All
        </NuxtLink>
        <div class="hidden gap-2 sm:flex">
          <button
            type="button"
            class="glass grid size-9 place-items-center rounded-full text-ink disabled:opacity-30"
            :disabled="!canPrev"
            aria-label="Scroll back"
            @click="emblaApi?.scrollPrev()"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
          </button>
          <button
            type="button"
            class="glass grid size-9 place-items-center rounded-full text-ink disabled:opacity-30"
            :disabled="!canNext"
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
        <slot :slide-class="wide
          ? 'min-w-0 shrink-0 grow-0 basis-[min(82%,20rem)] sm:basis-[25rem]'
          : 'min-w-0 shrink-0 grow-0 basis-[8.5rem] sm:basis-[12.5rem]'"
        />
      </div>
    </div>
  </section>
</template>
