<script setup lang="ts">
/**
 * A title's overview, clamped to `lines` with More / Less when the clamp cuts it off.
 * Key it by item so expansion resets on navigation.
 */
const props = withDefaults(defineProps<{
  text: string
  /** Ties the toggle to the paragraph for screen readers. */
  id: string
  lines?: 4 | 6
}>(), {
  lines: 6,
})

const el = ref<HTMLElement | null>(null)
const expanded = ref(false)
const clamped = ref(false)

function measure() {
  const node = el.value
  clamped.value = Boolean(node && !expanded.value && node.scrollHeight > node.clientHeight + 1)
}

let observer: ResizeObserver | null = null
watch(el, (node) => {
  observer?.disconnect()
  if (!node) return
  observer ??= new ResizeObserver(measure)
  observer.observe(node)
})
watch(() => props.text, () => nextTick(measure))
onBeforeUnmount(() => observer?.disconnect())
</script>

<template>
  <div class="flex flex-col items-start gap-1">
    <p
      :id="id"
      ref="el"
      class="text-[17px] leading-relaxed text-ink-2"
      :class="expanded ? '' : lines === 4 ? 'line-clamp-4' : 'line-clamp-6'"
    >
      {{ text }}
    </p>
    <button
      v-if="clamped || expanded"
      type="button"
      class="text-[15px] font-extrabold text-ink underline decoration-transparent decoration-2 underline-offset-4 transition-colors hover:decoration-current focus-visible:decoration-current"
      :aria-expanded="expanded"
      :aria-controls="id"
      @click="expanded = !expanded"
    >
      {{ expanded ? 'Less' : 'More' }}
    </button>
  </div>
</template>
