<script setup lang="ts">
import type { JellyfinItem } from '~/types/jellyfin'

withDefaults(defineProps<{
  title: string
  items?: JellyfinItem[]
  loading?: boolean
}>(), {
  items: () => [],
  loading: false,
})

const SLIDE_CLASS = 'rank-slide relative min-w-0 shrink-0 grow-0 basis-[min(92%,20rem)] pl-[2rem] sm:basis-[26.5rem] sm:pl-[3rem]'

function detail(item: JellyfinItem) {
  return [
    item.communityRating ? `★ ${item.communityRating.toFixed(1)}` : null,
    item.genres?.[0],
    item.type === 'Series' ? 'Series' : null,
    item.productionYear,
  ]
    .filter(Boolean)
    .join(', ')
}

function numeralClass(i: number) {
  return [
    'pointer-events-none absolute top-0 select-none text-[7.5rem] font-extrabold leading-[0.8] sm:text-[11rem]',
    i + 1 >= 10 ? 'tracking-[-0.12em]' : 'tracking-[-0.04em]',
  ]
}
</script>

<template>
  <MediaRow :title="title" :count="items.length" :loading="loading" wide>
    <!-- Numerals are known up front, so they show while the cards load -->
    <template #skeleton>
      <div v-for="i in 4" :key="i" :class="SLIDE_CLASS">
        <span
          aria-hidden="true"
          class="rank-numeral left-0 z-10"
          :class="[numeralClass(i - 1), i === 1 ? 'rank-numeral-first' : '']"
        >{{ i }}</span>
        <MediaCardSkeleton variant="landscape" />
      </div>
    </template>
    <template #default>
      <div
        v-for="(item, i) in items"
        :key="item.id"
        :class="SLIDE_CLASS"
      >
        <!-- Big outlined rank numeral, drawn over the card's left edge -->
        <span
          aria-hidden="true"
          class="rank-numeral left-0 z-10"
          :class="[numeralClass(i), i === 0 ? 'rank-numeral-first' : '']"
        >{{ i + 1 }}</span>
        <div class="relative">
          <span class="sr-only">Number {{ i + 1 }}:</span>
          <MediaCard
            :item="item"
            variant="landscape"
            :detail="detail(item)"
            :zoom="false"
            :favorite-button="false"
          >
            <!-- Knockout: the same numeral in the page colour with a halo, offset back by the
                 slide padding, so the image looks cut away around the numeral above. -->
            <template #art>
              <span
                aria-hidden="true"
                class="rank-knockout -left-[2rem] sm:-left-[3rem]"
                :class="numeralClass(i)"
              >{{ i + 1 }}</span>
            </template>
          </MediaCard>
        </div>
      </div>
    </template>
  </MediaRow>
</template>

<style scoped>
.rank-numeral {
  color: transparent;
  font-family: var(--font-sans);
  font-variant-numeric: lining-nums;
  background-image: linear-gradient(to bottom, rgb(255 255 255 / 0.85), rgb(255 255 255 / 0.08) 85%);
  background-clip: text;
  -webkit-background-clip: text;
  filter: drop-shadow(0 10px 24px rgb(0 0 0 / 0.5));
}

.rank-slide:has(a:hover) .rank-numeral {
  background-image: linear-gradient(to bottom, rgb(255 255 255 / 1), rgb(255 255 255 / 0.16) 90%);
}

.rank-numeral-first {
  background-image: linear-gradient(to bottom, var(--color-accent), rgb(252 120 20 / 0.08) 85%);
}

.rank-slide:has(a:hover) .rank-numeral-first {
  background-image: linear-gradient(to bottom, #ffb26b, rgb(252 120 20 / 0.2) 90%);
}

/* Page-coloured glyph plus a ring of hard shadows = a rounded 8px gap around the numeral. */
.rank-knockout {
  color: var(--color-canvas);
  text-shadow:
    8.00px 0px 0 var(--color-canvas),
    7.73px 2.07px 0 var(--color-canvas),
    6.93px 4.00px 0 var(--color-canvas),
    5.66px 5.66px 0 var(--color-canvas),
    4.00px 6.93px 0 var(--color-canvas),
    2.07px 7.73px 0 var(--color-canvas),
    0px 8.00px 0 var(--color-canvas),
    -2.07px 7.73px 0 var(--color-canvas),
    -4.00px 6.93px 0 var(--color-canvas),
    -5.66px 5.66px 0 var(--color-canvas),
    -6.93px 4.00px 0 var(--color-canvas),
    -7.73px 2.07px 0 var(--color-canvas),
    -8.00px 0px 0 var(--color-canvas),
    -7.73px -2.07px 0 var(--color-canvas),
    -6.93px -4.00px 0 var(--color-canvas),
    -5.66px -5.66px 0 var(--color-canvas),
    -4.00px -6.93px 0 var(--color-canvas),
    -2.07px -7.73px 0 var(--color-canvas),
    0px -8.00px 0 var(--color-canvas),
    2.07px -7.73px 0 var(--color-canvas),
    4.00px -6.93px 0 var(--color-canvas),
    5.66px -5.66px 0 var(--color-canvas),
    6.93px -4.00px 0 var(--color-canvas),
    7.73px -2.07px 0 var(--color-canvas);
}
</style>
