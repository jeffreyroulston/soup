<script setup lang="ts">
import type { SeerrStatus } from '~/types/seerr'

/**
 * What Explore shows instead of content when Seerr can't be used: not set up on this
 * server, not answering, or the status call itself failed.
 */
const props = withDefaults(defineProps<{
  status: SeerrStatus | null
  error?: unknown
  onRetry?: () => unknown
}>(), { error: undefined, onRetry: undefined })

const { currentName } = useServers()

const copy = computed(() => {
  const server = currentName.value?.trim() || 'this server'
  if (props.status && !props.status.configured) {
    return {
      title: 'Explore isn\'t set up here',
      message: `Explore needs a Seerr (Jellyseerr) server. An admin can connect one under Soup settings in the ${server} dashboard.`,
    }
  }
  if (props.status && !props.status.reachable) {
    return {
      title: 'Can\'t reach Seerr',
      message: `${server} couldn't talk to its Seerr server. It may be off or restarting.`,
    }
  }
  if (props.error instanceof SeerrError) {
    return { title: 'Explore isn\'t available', message: props.error.message }
  }
  return { title: 'Explore isn\'t available', message: 'Try again in a moment.' }
})

const detail = computed(() => props.status?.error ?? (props.error instanceof Error ? props.error.message : null))
</script>

<template>
  <section role="status" class="mx-auto flex w-full max-w-[520px] flex-col items-center px-4 py-20 text-center">
    <h2 class="text-[26px] font-extrabold leading-tight tracking-[-0.8px] text-ink">
      {{ copy.title }}
    </h2>
    <p class="mt-3 text-[15px] leading-relaxed text-muted">
      {{ copy.message }}
    </p>
    <button
      v-if="onRetry && (!status || status.configured)"
      type="button"
      class="mt-6 h-[46px] rounded-full bg-ink px-6 text-[15px] font-bold text-canvas transition hover:bg-ink/80"
      @click="onRetry()"
    >
      Retry
    </button>
    <details v-if="detail" class="mt-8 max-w-full text-[12px] text-muted">
      <summary class="cursor-pointer font-semibold hover:text-ink-2">
        Details
      </summary>
      <p class="mt-2 break-all text-left font-mono">
        {{ detail }}
      </p>
    </details>
  </section>
</template>
