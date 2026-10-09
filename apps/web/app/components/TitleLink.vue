<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'

withDefaults(defineProps<{
  to: RouteLocationRaw
  /** Keep to one line with an ellipsis (card captions). */
  truncate?: boolean
}>(), {
  truncate: false,
})
</script>

<template>
  <!-- Main title link: underline plus a chevron that slides in on hover/focus -->
  <NuxtLink
    :to="to"
    class="group/title inline-flex max-w-full items-center gap-1.5 self-start underline decoration-transparent decoration-2 underline-offset-4 transition-colors hover:decoration-current focus-visible:decoration-current"
  >
    <span :class="truncate ? 'min-w-0 truncate' : ''"><slot /></span>
    <svg
      class="size-4 shrink-0 -translate-x-1 opacity-0 transition duration-200 group-hover/title:translate-x-0 group-hover/title:opacity-100 group-focus-visible/title:translate-x-0 group-focus-visible/title:opacity-100"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    ><path d="M9 6l6 6-6 6" /></svg>
  </NuxtLink>
</template>
