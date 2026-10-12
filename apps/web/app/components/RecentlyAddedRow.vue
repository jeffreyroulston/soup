<script setup lang="ts">
import type { JellyfinShelf } from '~/types/jellyfin'

const props = withDefaults(defineProps<{
  /** One shelf per library, titled with the library's name. */
  shelves?: JellyfinShelf[]
  loading?: boolean
}>(), {
  shelves: () => [],
  loading: false,
})

const selected = ref(0)
/** Falls back to the first library if the list shrinks under the selection. */
const active = computed(() => props.shelves[selected.value] ?? props.shelves[0] ?? null)
</script>

<template>
  <MediaRow
    v-if="active || loading"
    title="Recently Added"
    :count="active?.items.length ?? 0"
    :loading="loading"
    :see-all-to="active?.seeAllTo ?? null"
    :reset-key="active?.title"
  >
    <template v-if="loading" #header>
      <span aria-hidden="true" class="h-10 w-44 animate-pulse rounded-full bg-surface" />
    </template>
    <template v-else-if="shelves.length > 1" #header>
      <div role="group" aria-label="Library" class="rail flex max-w-full gap-0.5 overflow-x-auto rounded-full bg-surface p-1">
        <button
          v-for="(shelf, i) in shelves"
          :key="shelf.title"
          type="button"
          class="h-8 shrink-0 whitespace-nowrap rounded-full px-3.5 text-sm font-bold transition"
          :class="shelf === active ? 'bg-ink text-canvas' : 'text-ink-2 hover:text-ink'"
          :aria-pressed="shelf === active"
          @click="selected = i"
        >
          {{ shelf.title }}
        </button>
      </div>
    </template>
    <template #default="{ slideClass }">
      <div v-for="item in active?.items ?? []" :key="item.id" :class="slideClass">
        <!-- Latest episodes stand in for their show -->
        <MediaCard
          :item="item"
          :to="item.type === 'Episode' && item.seriesId ? `/item/${item.seriesId}` : undefined"
        />
      </div>
    </template>
  </MediaRow>
</template>
