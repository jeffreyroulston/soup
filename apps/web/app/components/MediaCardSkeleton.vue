<script setup lang="ts">
// Mirrors MediaCard's box and caption typography so swapping in real cards
// doesn't move anything. Bars sit inside text-sized lines, so line heights match.
withDefaults(defineProps<{
  variant?: 'poster' | 'landscape'
  kicker?: boolean
  detail?: boolean
}>(), {
  variant: 'poster',
  kicker: false,
  detail: true,
})
</script>

<template>
  <div class="block w-full" aria-hidden="true">
    <div
      class="animate-pulse rounded-card bg-surface"
      :class="variant === 'landscape' ? 'aspect-video' : 'aspect-[2/3]'"
    />
    <div class="mt-2.5 flex min-w-0 flex-col gap-0.5">
      <span v-if="kicker" class="truncate text-[13px] font-bold">
        <span class="inline-block h-[0.8em] w-24 animate-pulse rounded bg-surface align-middle" />
      </span>
      <span class="truncate font-bold" :class="variant === 'landscape' ? 'text-base' : 'text-[15px]'">
        <span class="inline-block h-[0.8em] w-3/4 animate-pulse rounded bg-surface align-middle" />
      </span>
      <span v-if="detail" class="truncate text-[13px] font-semibold">
        <span class="inline-block h-[0.8em] w-1/3 animate-pulse rounded bg-surface align-middle" />
      </span>
    </div>
  </div>
</template>
