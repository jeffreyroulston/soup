<script setup lang="ts">
/**
 * What a page shows instead of its content when loading failed: friendly copy for
 * the kind of failure, automatic retries for ones that can clear up, and the raw
 * error tucked under Details.
 */
const props = withDefaults(defineProps<{
  error: unknown
  /** Reloads what failed; omitted when there's nothing to retry. */
  onRetry?: () => unknown
  /** Smaller type, for errors inside a page section rather than the whole page. */
  compact?: boolean
}>(), { onRetry: undefined, compact: false })

const status = useServerStatus()
const { currentName } = useServers()
const auth = useAuthSession()

const kind = computed(() => classifyError(props.error))
const copy = computed(() => errorCopy(kind.value, currentName.value))
const detail = computed(() => errorDetail(props.error))
/** The app-wide reconnect loop owns retries while the whole server is down. */
const followsServer = computed(() => OFFLINE_KINDS.includes(kind.value) && status.state.value.offline)
const canChangeServer = computed(() => OFFLINE_KINDS.includes(kind.value))
const canRetry = computed(() => props.onRetry != null || followsServer.value)

// Retries of our own, for failures the reconnect loop doesn't cover (e.g. a 5xx).
const attempt = ref(0)
const localRetryAt = ref<number | null>(null)
let retryTimer: ReturnType<typeof setTimeout> | null = null

function clearRetry() {
  if (retryTimer) clearTimeout(retryTimer)
  retryTimer = null
  localRetryAt.value = null
}

function scheduleRetry() {
  clearRetry()
  if (!props.onRetry || followsServer.value || !RETRYABLE_KINDS.includes(kind.value)) return
  const delay = retryDelaySeconds(attempt.value) * 1000
  localRetryAt.value = Date.now() + delay
  retryTimer = setTimeout(() => {
    localRetryAt.value = null
    attempt.value += 1
    void props.onRetry?.()
  }, delay)
}

// Each new failure (the retry failed again) schedules the next, further-off retry.
watch(() => [props.error, followsServer.value], scheduleRetry, { immediate: true })

const now = ref(Date.now())
let ticker: ReturnType<typeof setInterval> | null = null
const retryAt = computed(() => (followsServer.value ? status.state.value.retryAt : localRetryAt.value))
const secondsLeft = computed(() =>
  retryAt.value == null ? null : Math.max(1, Math.ceil((retryAt.value - now.value) / 1000)))
const retrying = computed(() => followsServer.value && status.state.value.probing)

function retryNow() {
  if (followsServer.value) {
    status.retryNow()
    return
  }
  clearRetry()
  void props.onRetry?.()
}

async function signInAgain() {
  await auth.logout()
  await navigateTo('/login')
}

onMounted(() => {
  status.trackFullPageError(1)
  ticker = setInterval(() => { now.value = Date.now() }, 1000)
})
onBeforeUnmount(() => {
  status.trackFullPageError(-1)
  clearRetry()
  if (ticker) clearInterval(ticker)
})
</script>

<template>
  <section
    role="alert"
    class="mx-auto flex w-full max-w-[520px] flex-col items-center px-4 text-center"
    :class="compact ? 'py-10' : 'py-24'"
  >
    <h2
      class="font-extrabold tracking-[-0.8px] text-ink"
      :class="compact ? 'text-[22px]' : 'text-[30px] leading-tight'"
    >
      {{ copy.title }}
    </h2>
    <p class="mt-3 text-[15px] leading-relaxed text-muted">
      {{ copy.message }}
    </p>

    <p v-if="retrying" class="mt-4 text-[13px] font-semibold text-ink-2" aria-live="polite">
      Reconnecting…
    </p>
    <p v-else-if="secondsLeft != null" class="mt-4 text-[13px] font-semibold text-ink-2" aria-live="polite">
      Retrying in {{ secondsLeft }}s
    </p>

    <div class="mt-6 flex flex-wrap justify-center gap-3">
      <button
        v-if="kind === 'signedOut'"
        type="button"
        class="h-[46px] rounded-full bg-ink px-6 text-[15px] font-bold text-canvas transition hover:bg-ink/80"
        @click="signInAgain"
      >
        Sign in again
      </button>
      <NuxtLink
        v-else-if="kind === 'notFound'"
        to="/"
        class="grid h-[46px] place-items-center rounded-full bg-ink px-6 text-[15px] font-bold text-canvas transition hover:bg-ink/80"
      >
        Back to Home
      </NuxtLink>
      <button
        v-else-if="canRetry"
        type="button"
        class="h-[46px] rounded-full bg-ink px-6 text-[15px] font-bold text-canvas transition hover:bg-ink/80 disabled:opacity-60"
        :disabled="retrying"
        @click="retryNow"
      >
        {{ secondsLeft != null || retrying ? 'Retry now' : 'Retry' }}
      </button>
      <NuxtLink
        v-if="canChangeServer"
        to="/settings/servers"
        class="glass grid h-[46px] place-items-center rounded-full px-6 text-[15px] font-bold text-ink"
      >
        Change server
      </NuxtLink>
    </div>

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
