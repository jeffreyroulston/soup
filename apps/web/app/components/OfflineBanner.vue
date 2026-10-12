<script setup lang="ts">
/**
 * Shown while the server can't be reached but the page still has (cached) content;
 * full-page error states cover the rest. Clears itself when the server answers.
 */
const status = useServerStatus()
const { currentName } = useServers()

const visible = computed(() => status.state.value.offline && status.state.value.fullPageErrors === 0)
const label = computed(() => {
  const server = currentName.value?.trim() || 'your server'
  return status.state.value.kind === 'timeout' ? `${server} isn't responding` : `Can't reach ${server}`
})
</script>

<template>
  <Transition
    enter-from-class="translate-y-4 opacity-0"
    leave-to-class="translate-y-4 opacity-0"
    enter-active-class="transition duration-200 ease-out"
    leave-active-class="transition duration-200 ease-in"
  >
    <div
      v-if="visible"
      role="status"
      aria-live="polite"
      class="glass-strong fixed inset-x-4 bottom-28 z-40 mx-auto flex max-w-max items-center gap-3 rounded-full py-2 pl-5 pr-2 text-[14px] font-semibold text-ink md:bottom-8"
    >
      <span class="size-2 shrink-0 rounded-full bg-accent" aria-hidden="true" />
      <span class="min-w-0 truncate">{{ label }} · Reconnecting…</span>
      <button
        type="button"
        class="h-9 shrink-0 rounded-full bg-ink px-4 text-[13px] font-bold text-canvas transition hover:bg-ink/80 disabled:opacity-60"
        :disabled="status.state.value.probing"
        @click="status.retryNow()"
      >
        Retry now
      </button>
    </div>
  </Transition>
</template>
