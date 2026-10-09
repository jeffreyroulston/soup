import type { Ref } from 'vue'

/**
 * Renders a long list in chunks: the first `initial` items straight away, then
 * `step` more per idle period until the whole list is in the DOM. Mounting
 * thousands of cards in one frame blocks the main thread for hundreds of ms.
 */
export function useStaggeredList<T>(source: Ref<T[]>, { initial = 60, step = 120 } = {}) {
  const count = ref(initial)
  // Safari has no requestIdleCallback; a 0ms timeout still yields between chunks.
  const idle = import.meta.client && typeof window.requestIdleCallback === 'function'
  let handle: number | ReturnType<typeof setTimeout> | null = null

  const rendered = computed(() =>
    count.value >= source.value.length ? source.value : source.value.slice(0, count.value))
  const complete = computed(() => count.value >= source.value.length)

  function cancel() {
    if (handle == null) return
    if (idle) window.cancelIdleCallback(handle as number)
    else clearTimeout(handle)
    handle = null
  }

  function schedule() {
    if (handle != null || !import.meta.client || complete.value) return
    const next = () => {
      handle = null
      count.value += step
      schedule()
    }
    handle = idle ? window.requestIdleCallback(next, { timeout: 200 }) : setTimeout(next, 0)
  }

  /** Back to the first chunk (new library or filter); refetches of the same list keep their place. */
  function reset() {
    cancel()
    count.value = initial
    schedule()
  }

  /** Everything at once, e.g. before jumping to an anchor that may not be rendered yet. */
  function renderAll() {
    cancel()
    count.value = Math.max(count.value, source.value.length)
  }

  watch(() => source.value.length, schedule, { immediate: true })
  onBeforeUnmount(cancel)

  return { rendered, complete, reset, renderAll }
}
