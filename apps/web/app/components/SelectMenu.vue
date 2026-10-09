<script setup lang="ts" generic="T extends string | number | null">
import {
  SelectContent,
  SelectItem,
  SelectItemIndicator,
  SelectItemText,
  SelectPortal,
  SelectRoot,
  SelectTrigger,
  SelectViewport,
} from 'reka-ui'

export type SelectOption<V> = { value: V, label: string, detail?: string | null }

/**
 * Pill dropdown on Reka UI's Select: the list is portalled to <body> and positioned with
 * Floating UI (flips/shifts to stay on screen), with full keyboard + typeahead support.
 */
const props = withDefaults(defineProps<{
  options: SelectOption<T>[]
  /** Accessible name, e.g. "Audio". */
  label: string
  /** Visible text before the value inside the trigger, e.g. "Sort". */
  prefix?: string | null
  /** glass = over artwork, surface = on the page background. */
  tone?: 'glass' | 'surface'
}>(), {
  prefix: null,
  tone: 'glass',
})

const model = defineModel<T>({ required: true })

// Reka needs non-null item values, so items are keyed by index and mapped back to `T`.
const selectedKey = computed({
  get: () => {
    const index = props.options.findIndex(option => option.value === model.value)
    return index >= 0 ? String(index) : undefined
  },
  set: (key) => {
    const option = key != null ? props.options[Number(key)] : undefined
    if (option) model.value = option.value
  },
})

const selected = computed(() => props.options.find(option => option.value === model.value) ?? null)
</script>

<template>
  <SelectRoot v-model="selectedKey">
    <SelectTrigger
      class="group flex h-11 max-w-full items-center gap-2 rounded-full pl-4 pr-3.5 text-sm font-bold text-ink outline-none transition focus-visible:ring-2 focus-visible:ring-ink/60"
      :class="tone === 'glass' ? 'glass' : 'bg-surface hover:bg-elevated'"
      :aria-label="label"
    >
      <span v-if="$slots.icon" class="shrink-0 text-ink-2"><slot name="icon" /></span>
      <span v-if="prefix" class="shrink-0 font-semibold text-muted">{{ prefix }}</span>
      <!-- Every label stacked in one grid cell (only the selected one visible), so the
           trigger is as wide as the widest option and doesn't resize on change. -->
      <span class="grid min-w-0 max-w-56 text-left">
        <span
          v-for="option in options"
          :key="String(option.value)"
          class="invisible col-start-1 row-start-1 truncate"
          aria-hidden="true"
        >{{ option.label }}</span>
        <span class="col-start-1 row-start-1 truncate">{{ selected?.label ?? '—' }}</span>
      </span>
      <svg
        class="size-3.5 shrink-0 text-ink-2 transition duration-200 group-data-[state=open]:rotate-180"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2.6"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      ><path d="m6 9 6 6 6-6" /></svg>
    </SelectTrigger>

    <SelectPortal>
      <SelectContent
        position="popper"
        side="bottom"
        align="start"
        :side-offset="8"
        :collision-padding="12"
        :body-lock="false"
        class="select-menu-content glass-strong z-[60] min-w-[var(--reka-select-trigger-width)] max-w-[min(26rem,calc(100vw-1.5rem))] overflow-hidden rounded-[18px] shadow-[0_18px_40px_rgba(0,0,0,0.5)]"
      >
        <SelectViewport class="scrollbar-subtle max-h-[min(18rem,var(--reka-select-content-available-height))] overflow-y-auto p-1.5">
          <SelectItem
            v-for="(option, i) in options"
            :key="String(option.value)"
            :value="String(i)"
            class="flex min-h-10 cursor-pointer select-none items-center gap-2.5 rounded-[10px] px-2.5 text-[15px] font-semibold text-ink outline-none data-[highlighted]:bg-white/10"
          >
            <span class="w-4 shrink-0 font-extrabold">
              <SelectItemIndicator>✓</SelectItemIndicator>
            </span>
            <SelectItemText class="min-w-0 flex-1 truncate">{{ option.label }}</SelectItemText>
            <span v-if="option.detail" class="shrink-0 text-xs font-bold text-muted">{{ option.detail }}</span>
          </SelectItem>
        </SelectViewport>
      </SelectContent>
    </SelectPortal>
  </SelectRoot>
</template>

<style>
/* Open/close motion, from the side it grows out of (data-side is set by the positioner). */
.select-menu-content[data-state='open'] {
  animation: select-menu-in 140ms ease-out;
}

.select-menu-content[data-state='open'][data-side='top'] {
  animation-name: select-menu-in-up;
}

@keyframes select-menu-in {
  from { opacity: 0; transform: translateY(-4px) scale(0.97); }
}

@keyframes select-menu-in-up {
  from { opacity: 0; transform: translateY(4px) scale(0.97); }
}
</style>
