<script setup lang="ts">
import type { JellyfinItem } from '~/types/jellyfin'

const props = defineProps<{
  item: JellyfinItem
}>()

/** Series page with this episode's season selected. */
const seasonTo = computed(() => (props.item.seriesId && props.item.seasonId
  ? { path: `/item/${props.item.seriesId}`, query: { season: props.item.seasonId } }
  : null))
</script>

<template>
  <!-- "Season 1, Episode 4", each part linking to its own page -->
  <span v-if="item.type === 'Episode' && (item.indexNumber != null || item.parentIndexNumber != null)">
    <template v-if="item.parentIndexNumber != null">
      <NuxtLink
        v-if="seasonTo"
        :to="seasonTo"
        class="underline decoration-transparent decoration-2 underline-offset-4 transition-colors hover:text-ink hover:decoration-current"
      >Season {{ item.parentIndexNumber }}</NuxtLink>
      <span v-else>Season {{ item.parentIndexNumber }}</span><template v-if="item.indexNumber != null">, </template>
    </template>
    <NuxtLink
      v-if="item.indexNumber != null"
      :to="`/item/${item.id}`"
      class="underline decoration-transparent decoration-2 underline-offset-4 transition-colors hover:text-ink hover:decoration-current"
    >Episode {{ item.indexNumber }}</NuxtLink>
  </span>
</template>
