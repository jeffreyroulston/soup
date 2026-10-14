<script setup lang="ts">
import type { JellyfinShelf } from '~/types/jellyfin'

withDefaults(defineProps<{
  /** May be missing while loading, when the row's title isn't known yet. */
  shelf?: JellyfinShelf | null
  loading?: boolean
}>(), {
  shelf: null,
  loading: false,
})
</script>

<template>
  <MediaRow
    :title="shelf?.title"
    :count="shelf?.items.length ?? 0"
    :loading="loading"
    :see-all-to="shelf?.seeAllTo ?? null"
  >
    <template #default="{ slideClass }">
      <div v-for="item in shelf?.items ?? []" :key="item.id" :class="slideClass">
        <!-- Latest episodes stand in for their show -->
        <MediaCard
          :item="item"
          :to="item.type === 'Episode' && item.seriesId ? `/item/${item.seriesId}` : undefined"
          :favorite-button="false"
        />
      </div>
    </template>
  </MediaRow>
</template>
