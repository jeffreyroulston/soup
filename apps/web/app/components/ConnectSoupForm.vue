<script setup lang="ts">
import { renderSVG } from 'uqr'

const emit = defineEmits<{ linked: [], cancel: [] }>()

const auth = useAuthSession()

const userCode = ref('')
const verificationUrl = ref('')
/** "Continue with Google" skips the /link page the QR code opens. */
const googleUrl = ref('')
const error = ref('')
const qrSvg = computed(() => (verificationUrl.value
  ? renderSVG(verificationUrl.value, { border: 2, pixelSize: 8, blackColor: '#000', whiteColor: '#fff' })
  : ''))
let timer: ReturnType<typeof setTimeout> | null = null
/** Bumped on stop so a start or poll that's still in flight is ignored. */
let run = 0

onMounted(() => void start())
onBeforeUnmount(stop)

function stop() {
  run++
  if (timer) clearTimeout(timer)
  timer = null
  void auth.cancelLogin()
}

async function start() {
  stop()
  const current = run
  error.value = ''
  userCode.value = ''
  verificationUrl.value = ''
  googleUrl.value = ''
  try {
    const started = await auth.startLogin()
    if (current !== run) return
    userCode.value = started.userCode
    verificationUrl.value = started.verificationUrl
    googleUrl.value = started.googleUrl
    schedulePoll(started.interval || 5, current)
  }
  catch (err) {
    if (current === run) error.value = err instanceof Error ? err.message : 'Could not start sign-in'
  }
}

function schedulePoll(intervalSec: number, current: number) {
  timer = setTimeout(async () => {
    try {
      const result = await auth.pollLogin({ keepCurrent: true })
      if (current !== run) return
      if (result.status === 'pending') {
        schedulePoll(result.interval || intervalSec, current)
        return
      }
      // Keep a live code on screen rather than an expired one.
      if (result.status === 'expired') {
        void start()
        return
      }
      emit('linked')
    }
    catch (err) {
      if (current === run) error.value = err instanceof Error ? err.message : 'Sign-in failed'
    }
  }, Math.max(2, intervalSec) * 1000)
}

function openGoogle() {
  if (googleUrl.value) window.open(googleUrl.value, '_blank', 'noopener,noreferrer')
}
</script>

<template>
  <div class="flex flex-col gap-4 rounded-[18px] bg-elevated/60 p-5">
    <div class="flex items-center gap-[18px]">
      <div
        v-if="error"
        class="flex size-28 shrink-0 flex-col items-center justify-center gap-2 rounded-2xl bg-white/5 p-3 text-center"
      >
        <p class="text-[12px] font-semibold text-accent">
          {{ error }}
        </p>
        <button type="button" class="text-[13px] font-bold text-ink-2 hover:text-ink hover:underline" @click="start">
          Retry
        </button>
      </div>
      <div v-else-if="!qrSvg" class="size-28 shrink-0 animate-pulse rounded-2xl bg-white/10" />
      <div
        v-else
        role="img"
        aria-label="QR code to sign in on your phone"
        class="size-28 shrink-0 overflow-hidden rounded-2xl bg-white p-2 [&>svg]:block [&>svg]:size-full"
        v-html="qrSvg"
      />
      <div class="flex min-w-0 flex-col gap-1.5">
        <p class="text-[15px] font-extrabold">
          Scan with your phone
        </p>
        <p class="text-sm leading-snug text-ink-2">
          Or continue with Google in a new tab. Check it shows
        </p>
        <p v-if="userCode" class="text-xl font-extrabold tracking-[3px]">
          {{ userCode }}
        </p>
        <div v-else class="h-7 w-28 animate-pulse rounded-md bg-white/10" />
      </div>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        :disabled="!googleUrl"
        class="h-11 rounded-btn bg-ink px-5 text-[15px] font-extrabold text-canvas transition enabled:hover:bg-ink/80 disabled:opacity-50"
        @click="openGoogle"
      >
        Continue with Google
      </button>
      <button type="button" class="h-11 px-3 text-[13px] font-bold text-muted transition hover:text-ink" @click="emit('cancel')">
        Cancel
      </button>
    </div>
  </div>
</template>
