<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'

/**
 * The white Play / Resume button. When there's progress, the time left sits beside the
 * label and a bar runs the full width of the button's bottom edge.
 */
const props = withDefaults(defineProps<{
  label: string
  /** e.g. "38 min left". */
  detail?: string | null
  /** 0–100; 0 hides the bar. */
  progress?: number
  /** Renders a link; otherwise a button that emits `click`. */
  to?: RouteLocationRaw
}>(), {
  detail: null,
  progress: 0,
  to: undefined,
})

defineEmits<{ click: [] }>()

const NuxtLinkComponent = resolveComponent('NuxtLink')
</script>

<template>
  <component
    :is="to ? NuxtLinkComponent : 'button'"
    :to="to"
    :type="to ? undefined : 'button'"
    class="relative inline-flex h-[52px] items-center gap-2.5 overflow-hidden whitespace-nowrap rounded-btn bg-ink px-5 text-[17px] font-extrabold text-canvas transition hover:bg-ink/80 sm:px-[26px]"
    @click="to ? undefined : $emit('click')"
  >
    <svg class="size-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" /></svg>
    {{ label }}
    <span v-if="detail" class="text-[15px] font-bold text-canvas/70">{{ detail }}</span>
    <span v-if="props.progress > 0" class="absolute inset-x-0 bottom-0 h-1 bg-canvas/15" aria-hidden="true">
      <span class="block h-full bg-accent" :style="{ width: `${Math.min(100, props.progress)}%` }" />
    </span>
  </component>
</template>
