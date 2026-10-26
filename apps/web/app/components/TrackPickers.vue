<script setup lang="ts">
import type { JellyfinMediaStream } from '~/types/jellyfin'

/**
 * Audio, subtitle and quality pickers for a title page. Audio and subtitles always show what
 * the file has; a lone audio track is a plain label, not a one-item dropdown. Quality shows
 * only when the page passes options for it.
 */
withDefaults(defineProps<{
  audioStreams: JellyfinMediaStream[]
  subtitleStreams: JellyfinMediaStream[]
  qualityOptions?: { value: number | null, label: string }[]
}>(), {
  qualityOptions: () => [],
})

const audio = defineModel<number | null>('audio', { required: true })
/** null is off. */
const subtitle = defineModel<number | null>('subtitle', { required: true })
/** Quality cap in bits/s; null is Auto. */
const quality = defineModel<number | null>('quality', { default: null })
</script>

<template>
  <div v-if="audioStreams.length || subtitleStreams.length || qualityOptions.length" class="flex flex-wrap items-center gap-2">
    <SelectMenu
      v-if="audioStreams.length > 1"
      v-model="audio"
      label="Audio"
      tone="surface"
      :options="audioStreams.map(stream => ({ value: stream.index, label: streamLabel(stream) }))"
    >
      <template #icon>
        <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4z" /><path d="M15.5 8.5a5 5 0 0 1 0 7" /><path d="M18.5 5.5a9 9 0 0 1 0 13" /></svg>
      </template>
    </SelectMenu>
    <span
      v-else-if="audioStreams.length"
      class="flex h-11 min-w-0 items-center gap-2 rounded-full bg-surface px-4 text-sm font-bold text-ink"
    >
      <span class="sr-only">Audio:</span>
      <svg class="size-4 shrink-0 text-ink-2" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4z" /><path d="M15.5 8.5a5 5 0 0 1 0 7" /><path d="M18.5 5.5a9 9 0 0 1 0 13" /></svg>
      <span class="truncate">{{ streamLabel(audioStreams[0]!) }}</span>
    </span>
    <SelectMenu
      v-if="subtitleStreams.length"
      v-model="subtitle"
      label="Subtitles"
      tone="surface"
      :options="[
        { value: null, label: 'Subtitles off' },
        ...subtitleStreams.map(stream => ({ value: stream.index, label: streamLabel(stream) })),
      ]"
    >
      <template #icon>
        <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3" /><path d="M7 15h4M14 15h3M7 11h2M12 11h5" /></svg>
      </template>
    </SelectMenu>
    <span
      v-else-if="audioStreams.length"
      class="flex h-11 items-center gap-2 rounded-full bg-surface px-4 text-sm font-bold text-muted"
    >
      <span class="shrink-0 text-ink-2"><svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3" /><path d="M7 15h4M14 15h3M7 11h2M12 11h5" /></svg></span>
      No subtitles
    </span>
    <SelectMenu
      v-if="qualityOptions.length"
      v-model="quality"
      label="Quality"
      tone="surface"
      :options="qualityOptions"
    >
      <template #icon>
        <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="5" width="20" height="14" rx="2" /><path d="M7 9v6M7 12h3M10 9v6M14 9h2a3 3 0 0 1 0 6h-2z" /></svg>
      </template>
    </SelectMenu>
  </div>
</template>
