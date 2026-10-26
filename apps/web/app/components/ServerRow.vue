<script setup lang="ts">
import type { ServerEntry } from '~/composables/useServers'

const props = defineProps<{
  entry: ServerEntry
  current: boolean
  switching: boolean
  disabled: boolean
  highlight?: boolean
  /** Shows the nickname field and reorder controls instead of Switch. */
  editing?: boolean
  first?: boolean
  last?: boolean
}>()

const emit = defineEmits<{ switch: [], rename: [nickname: string], move: [delta: number] }>()

const subtitle = computed(() => [
  props.entry.host,
  props.entry.kind === 'soup' ? 'Soup' : props.entry.username,
].filter(Boolean).join(' · '))
</script>

<template>
  <div
    class="flex items-center gap-3 rounded-btn px-3 py-2.5 transition-colors"
    :class="highlight ? 'bg-ok/10' : editing ? '' : 'hover:bg-white/[0.04]'"
  >
    <span class="size-2 shrink-0 rounded-full" :class="current ? 'bg-ok' : 'bg-white/15'" />

    <span v-if="editing" class="flex min-w-0 flex-1 flex-col gap-1">
      <input
        :value="entry.name === entry.originalName ? '' : entry.name"
        type="text"
        :placeholder="entry.originalName"
        :aria-label="`Nickname for ${entry.originalName}`"
        maxlength="40"
        class="h-10 min-w-0 rounded-[10px] border border-white/10 bg-elevated px-3 text-[15px] font-bold text-ink outline-none placeholder:text-ink-2/60 focus:border-accent"
        @change="emit('rename', ($event.target as HTMLInputElement).value)"
        @keydown.enter="($event.target as HTMLInputElement).blur()"
      >
      <span class="truncate px-0.5 text-[13px] font-semibold text-muted">{{ subtitle }}</span>
    </span>
    <span v-else class="flex min-w-0 flex-1 flex-col">
      <span class="truncate text-base font-bold">{{ entry.name }}</span>
      <span class="truncate text-[13px] font-semibold text-muted">{{ subtitle }}</span>
    </span>

    <template v-if="editing">
      <span class="flex shrink-0 gap-0.5">
        <button
          type="button"
          :disabled="first"
          :aria-label="`Move ${entry.name} up`"
          class="grid size-9 place-items-center rounded-full text-ink-2 transition enabled:hover:bg-white/10 enabled:hover:text-ink disabled:opacity-25"
          @click="emit('move', -1)"
        >
          <svg viewBox="0 0 24 24" class="size-[18px]" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="m6 15 6-6 6 6" />
          </svg>
        </button>
        <button
          type="button"
          :disabled="last"
          :aria-label="`Move ${entry.name} down`"
          class="grid size-9 place-items-center rounded-full text-ink-2 transition enabled:hover:bg-white/10 enabled:hover:text-ink disabled:opacity-25"
          @click="emit('move', 1)"
        >
          <svg viewBox="0 0 24 24" class="size-[18px]" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="m6 9 6 6 6-6" />
          </svg>
        </button>
      </span>
      <slot name="edit" />
    </template>
    <template v-else>
      <span v-if="current" class="shrink-0 rounded-full bg-ok/15 px-3 py-1 text-xs font-extrabold text-ok max-sm:sr-only">
        Current
      </span>
      <button
        v-else
        type="button"
        :disabled="disabled"
        class="flex h-9 shrink-0 items-center gap-2 rounded-full bg-white/10 px-3.5 text-[13px] font-bold text-ink transition enabled:hover:bg-white/15 disabled:opacity-50"
        @click="emit('switch')"
      >
        <span v-if="switching" class="size-3.5 animate-spin rounded-full border-2 border-ink/30 border-t-ink" />
        Switch
      </button>
    </template>
  </div>
</template>
