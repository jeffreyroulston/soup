<script setup lang="ts">
import { LAST_SERVER_KEY } from '~/composables/useAuthSession'

definePageMeta({ layout: false })

const config = useRuntimeConfig()
const auth = useAuthSession()
const router = useRouter()
const mock = isMockMode()

const phase = ref<'idle' | 'waiting' | 'direct' | 'quickConnect' | 'server' | 'error'>('idle')
const userCode = ref('')
const verificationUrl = ref('')
const errorMessage = ref('')
let pollTimer: ReturnType<typeof setTimeout> | null = null
/** Bumped on cancel so a start or poll that's still in flight is ignored. */
let loginRun = 0

const serverUrl = ref('')
const username = ref('')
const password = ref('')
const directError = ref('')
const directBusy = ref(false)
const quickConnectCode = ref('')
const quickConnectBusy = ref(false)
/** Roster id being signed in to from the server picker. */
const selectingServer = ref<string | null>(null)

onMounted(async () => {
  try {
    serverUrl.value = localStorage.getItem(LAST_SERVER_KEY) || config.public.jellyfinUrl || ''
  }
  catch {
    serverUrl.value = config.public.jellyfinUrl || ''
  }
  if (!auth.ready.value) await auth.hydrate()
  if (auth.jellyfin.value) {
    await router.replace('/')
  }
  else if (auth.choosingServer.value) {
    phase.value = 'server'
  }
})

onBeforeUnmount(() => {
  loginRun++
  if (pollTimer) clearTimeout(pollTimer)
})

async function cancelLogin() {
  loginRun++
  if (pollTimer) clearTimeout(pollTimer)
  pollTimer = null
  userCode.value = ''
  verificationUrl.value = ''
  phase.value = 'idle'
  await auth.cancelLogin()
}

function showDirect() {
  directError.value = ''
  phase.value = 'direct'
}

async function submitDirect() {
  if (directBusy.value) return
  directError.value = ''
  directBusy.value = true
  try {
    await auth.signInDirect(serverUrl.value, username.value.trim(), password.value)
    await router.replace('/')
  }
  catch (error) {
    directError.value = error instanceof Error ? error.message : 'Could not sign in'
  }
  finally {
    directBusy.value = false
  }
}

/** Shows a code to enter in a signed-in Jellyfin app, then polls until it's approved. */
async function beginQuickConnect() {
  if (quickConnectBusy.value) return
  directError.value = ''
  quickConnectBusy.value = true
  const run = ++loginRun
  try {
    const started = await auth.startQuickConnect(serverUrl.value)
    if (run !== loginRun) return
    quickConnectCode.value = started.code
    phase.value = 'quickConnect'
    scheduleQuickConnectPoll(started.baseUrl, started.secret, run)
  }
  catch (error) {
    if (run !== loginRun) return
    directError.value = error instanceof Error ? error.message : 'Could not start Quick Connect'
  }
  finally {
    quickConnectBusy.value = false
  }
}

function scheduleQuickConnectPoll(baseUrl: string, secret: string, run: number) {
  if (pollTimer) clearTimeout(pollTimer)
  pollTimer = setTimeout(async () => {
    try {
      const status = await auth.pollQuickConnect(baseUrl, secret)
      if (run !== loginRun) return
      if (status === 'approved') {
        await router.replace('/')
        return
      }
      if (status === 'expired') {
        endQuickConnect('That code expired. Start Quick Connect again.')
        return
      }
      scheduleQuickConnectPoll(baseUrl, secret, run)
    }
    catch (error) {
      if (run !== loginRun) return
      endQuickConnect(error instanceof Error ? error.message : 'Quick Connect failed')
    }
  }, 5000)
}

/** Back to the Jellyfin form, optionally with an error. */
function endQuickConnect(message = '') {
  loginRun++
  if (pollTimer) clearTimeout(pollTimer)
  pollTimer = null
  quickConnectCode.value = ''
  directError.value = message
  phase.value = 'direct'
}

async function chooseServer(serverId: string) {
  if (selectingServer.value) return
  selectingServer.value = serverId
  auth.serverError.value = null
  try {
    await auth.selectServer(serverId)
    await router.replace('/')
  }
  catch (error) {
    auth.serverError.value = error instanceof Error ? error.message : 'Could not sign in to that server'
    if (!auth.email.value) phase.value = 'idle'
  }
  finally {
    selectingServer.value = null
  }
}

async function useAnotherAccount() {
  await auth.logout()
  phase.value = 'idle'
}

async function beginMock() {
  errorMessage.value = ''
  try {
    await auth.enterMockLibrary()
    await router.replace('/')
  }
  catch (error) {
    phase.value = 'error'
    errorMessage.value = error instanceof Error ? error.message : 'Could not enter mock mode'
  }
}

async function beginLogin() {
  if (mock) {
    await beginMock()
    return
  }
  errorMessage.value = ''
  userCode.value = ''
  phase.value = 'waiting'
  const run = ++loginRun
  try {
    const started = await auth.startLogin()
    if (run !== loginRun) return
    userCode.value = started.userCode
    verificationUrl.value = started.verificationUrl
    window.open(started.verificationUrl, '_blank', 'noopener,noreferrer')
    schedulePoll(started.interval || 5, run)
  }
  catch (error) {
    if (run !== loginRun) return
    phase.value = 'error'
    errorMessage.value = error instanceof Error ? error.message : 'Could not start sign-in'
  }
}

function schedulePoll(intervalSec: number, run: number) {
  if (pollTimer) clearTimeout(pollTimer)
  pollTimer = setTimeout(async () => {
    try {
      const result = await auth.pollLogin()
      if (run !== loginRun) return
      if (result.status === 'approved') {
        await router.replace('/')
        return
      }
      if (result.status === 'chooseServer') {
        phase.value = 'server'
        return
      }
      if (result.status === 'expired') {
        phase.value = 'error'
        errorMessage.value = 'Sign-in code expired. Try again.'
        return
      }
      schedulePoll(result.interval || intervalSec, run)
    }
    catch (error) {
      if (run !== loginRun) return
      phase.value = 'error'
      errorMessage.value = error instanceof Error ? error.message : 'Polling failed'
    }
  }, Math.max(2, intervalSec) * 1000)
}
</script>

<template>
  <div class="relative flex min-h-screen flex-col overflow-hidden bg-canvas">
    <PosterWall />

    <main class="relative grid flex-1 place-items-center px-4 py-16">
      <section
        aria-labelledby="login-title"
        class="glass-strong flex w-full max-w-[460px] flex-col gap-5 rounded-[28px] p-8 shadow-[0_40px_80px_rgba(0,0,0,0.5)] sm:p-11"
      >
        <h1
          v-if="!mock && (phase === 'idle' || phase === 'error')"
          id="login-title"
          class="pb-[54px] text-center text-[64px] font-extrabold leading-none tracking-[-2.5px]"
        >
          soup
        </h1>
        <h1 v-else id="login-title" class="text-[38px] font-extrabold leading-[1.05] tracking-[-0.04em]">
          {{ mock ? 'Browse the mock library' : phase === 'waiting' || phase === 'quickConnect' ? 'Approve this sign-in' : phase === 'server' ? 'Choose a server' : 'Sign in with Jellyfin' }}
        </h1>

        <template v-if="mock && phase === 'idle'">
          <p class="text-[15px] leading-relaxed text-ink-2">
            Identity and Jellyfin are skipped. Home, libraries, detail, search, and playback use
            an in-memory catalog with placeholder artwork.
          </p>
          <button
            type="button"
            class="h-[52px] rounded-btn bg-ink text-[17px] font-extrabold text-canvas transition hover:bg-ink/80"
            @click="beginMock"
          >
            Enter mock library
          </button>
        </template>

        <template v-else-if="phase === 'idle'">
          <button
            type="button"
            class="h-[52px] rounded-btn bg-ink text-[17px] font-extrabold text-canvas transition hover:bg-ink/80"
            @click="beginLogin"
          >
            Sign in with Google
          </button>
          <div class="flex items-center gap-3 text-[13px] font-semibold text-muted" aria-hidden="true">
            <span class="h-px flex-1 bg-white/10" />or<span class="h-px flex-1 bg-white/10" />
          </div>
          <button
            type="button"
            class="h-[52px] rounded-btn bg-white/10 text-base font-bold text-ink transition hover:bg-white/15"
            @click="showDirect"
          >
            Sign in with Jellyfin
          </button>
        </template>

        <form v-else-if="phase === 'direct'" class="flex flex-col gap-4" @submit.prevent="submitDirect">
          <p class="text-[15px] leading-relaxed text-ink-2">
            Use your Jellyfin username and password. No Soup invite needed.
          </p>
          <label class="flex flex-col gap-1.5">
            <span class="text-[13px] font-bold text-muted">Server address</span>
            <input
              v-model="serverUrl"
              type="url"
              inputmode="url"
              autocomplete="url"
              required
              placeholder="https://jellyfin.example.com"
              class="h-12 rounded-btn bg-white/10 px-4 text-base font-semibold text-ink placeholder:text-muted/70 focus:bg-white/15 focus:outline-none focus-visible:ring-2 focus-visible:ring-ink"
            >
          </label>
          <label class="flex flex-col gap-1.5">
            <span class="text-[13px] font-bold text-muted">Username</span>
            <input
              v-model="username"
              type="text"
              autocomplete="username"
              autocapitalize="off"
              spellcheck="false"
              required
              class="h-12 rounded-btn bg-white/10 px-4 text-base font-semibold text-ink focus:bg-white/15 focus:outline-none focus-visible:ring-2 focus-visible:ring-ink"
            >
          </label>
          <label class="flex flex-col gap-1.5">
            <span class="text-[13px] font-bold text-muted">Password</span>
            <input
              v-model="password"
              type="password"
              autocomplete="current-password"
              class="h-12 rounded-btn bg-white/10 px-4 text-base font-semibold text-ink focus:bg-white/15 focus:outline-none focus-visible:ring-2 focus-visible:ring-ink"
            >
          </label>
          <p v-if="directError" role="alert" class="text-[14px] font-semibold text-accent">
            {{ directError }}
          </p>
          <button
            type="submit"
            :disabled="directBusy"
            class="mt-1 flex h-[52px] items-center justify-center gap-2.5 rounded-btn bg-ink text-[17px] font-extrabold text-canvas transition enabled:hover:bg-ink/80 disabled:opacity-60"
          >
            <span v-if="directBusy" class="size-4 animate-spin rounded-full border-2 border-canvas/30 border-t-canvas" />
            {{ directBusy ? 'Signing in…' : 'Sign in' }}
          </button>
          <button
            type="button"
            :disabled="quickConnectBusy || !serverUrl.trim()"
            class="flex h-[52px] items-center justify-center gap-2.5 rounded-btn bg-white/10 text-base font-bold text-ink transition enabled:hover:bg-white/15 disabled:opacity-50"
            @click="beginQuickConnect"
          >
            <span v-if="quickConnectBusy" class="size-4 animate-spin rounded-full border-2 border-ink/30 border-t-ink" />
            Use Quick Connect instead
          </button>
          <button
            type="button"
            class="h-11 rounded-btn text-[15px] font-bold text-muted transition hover:text-ink"
            @click="phase = 'idle'"
          >
            Back
          </button>
        </form>

        <template v-else-if="phase === 'quickConnect'">
          <p class="text-[15px] leading-relaxed text-ink-2">
            On a device where you're signed in to Jellyfin, open your profile, choose
            <strong class="text-ink">Quick Connect</strong>, and enter this code:
          </p>
          <div :aria-label="`Code ${quickConnectCode}`" class="flex gap-1.5 sm:gap-2">
            <span
              v-for="(char, i) in quickConnectCode.split('')"
              :key="i"
              aria-hidden="true"
              class="grid h-[68px] min-w-0 flex-1 place-items-center rounded-btn bg-white/10 text-[clamp(1.5rem,7vw,2.25rem)] font-extrabold"
            >{{ char }}</span>
          </div>
          <div class="flex items-center justify-center gap-2.5 text-sm font-semibold text-muted">
            <span class="size-4 animate-spin rounded-full border-2 border-[#3A3A3C] border-t-accent" />
            Waiting for approval
          </div>
          <button
            type="button"
            class="h-11 rounded-btn text-[15px] font-bold text-muted transition hover:text-ink"
            @click="endQuickConnect()"
          >
            Cancel
          </button>
        </template>

        <template v-else-if="phase === 'server'">
          <p class="text-[15px] leading-relaxed text-ink-2">
            You have access to {{ auth.servers.value.length === 1 ? 'this server' : 'these servers' }}.
            You can switch later in Settings.
          </p>
          <p v-if="auth.serverError.value" role="alert" class="text-[14px] font-semibold text-accent">
            {{ auth.serverError.value }}
          </p>
          <ul class="flex flex-col gap-2">
            <li v-for="server in auth.servers.value" :key="server.id">
              <button
                type="button"
                :disabled="selectingServer !== null"
                class="flex w-full items-center gap-3 rounded-btn bg-white/10 px-4 py-3.5 text-left transition hover:bg-white/15 disabled:opacity-60"
                @click="chooseServer(server.id)"
              >
                <span class="flex min-w-0 flex-1 flex-col">
                  <span class="truncate text-[17px] font-extrabold">{{ server.name }}</span>
                  <span class="truncate text-[13px] font-semibold text-muted">{{ serverHost(server) }}</span>
                </span>
                <span
                  v-if="selectingServer === server.id"
                  class="size-4 shrink-0 animate-spin rounded-full border-2 border-ink/30 border-t-ink"
                />
              </button>
            </li>
          </ul>
          <p class="text-center text-[14px] font-semibold text-muted">
            Signed in as {{ auth.email.value }} ·
            <button type="button" class="font-bold text-ink-2 underline-offset-2 hover:text-ink hover:underline" @click="useAnotherAccount">
              Use another account
            </button>
          </p>
        </template>

        <template v-else-if="phase === 'waiting'">
          <p class="text-[15px] leading-relaxed text-ink-2">
            Finish signing in on the verification page. Check that it shows this code:
          </p>
          <div v-if="!userCode" class="h-[68px] w-full animate-pulse rounded-btn bg-white/10" />
          <div v-else :aria-label="`Code ${userCode}`" class="flex gap-1.5 sm:gap-2">
            <span
              v-for="(char, i) in userCode.split('')"
              :key="i"
              aria-hidden="true"
              class="grid h-[68px] place-items-center rounded-btn text-[clamp(1.5rem,7vw,2.25rem)] font-extrabold"
              :class="char === '-' ? 'flex-none px-0.5 text-muted' : 'min-w-0 flex-1 bg-white/10'"
            >{{ char }}</span>
          </div>
          <div class="flex items-center justify-center gap-2.5 text-sm font-semibold text-muted">
            <span class="size-4 animate-spin rounded-full border-2 border-[#3A3A3C] border-t-accent" />
            Waiting for approval
          </div>
          <a
            v-if="verificationUrl"
            :href="verificationUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex h-[52px] items-center justify-center rounded-btn bg-white/10 text-base font-bold text-ink hover:bg-white/15"
          >
            Open verification page
          </a>
          <button
            type="button"
            class="h-11 rounded-btn text-[15px] font-bold text-muted transition hover:text-ink"
            @click="cancelLogin"
          >
            Cancel
          </button>
        </template>

        <template v-else>
          <p class="text-[15px] font-semibold text-accent">
            {{ errorMessage }}
          </p>
          <button
            type="button"
            class="h-[52px] rounded-btn bg-ink text-[17px] font-extrabold text-canvas transition hover:bg-ink/80"
            @click="phase = 'idle'"
          >
            Try again
          </button>
        </template>
      </section>
    </main>
  </div>
</template>
