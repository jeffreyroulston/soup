<script setup lang="ts">
import { renderSVG } from 'uqr'
import { LAST_SERVER_KEY } from '~/composables/useAuthSession'
import { discoverServers, type DiscoveredServer } from '~/utils/discoverServers'

definePageMeta({ layout: false })

const config = useRuntimeConfig()
const auth = useAuthSession()
const router = useRouter()
const mock = isMockMode()

const phase = ref<'idle' | 'waiting' | 'direct' | 'quickConnect' | 'server' | 'error'>('idle')
const userCode = ref('')
const verificationUrl = ref('')
const errorMessage = ref('')
/** Couldn't start the device link that backs the QR code and the Google button. */
const linkError = ref('')
const qrSvg = computed(() => (verificationUrl.value
  ? renderSVG(verificationUrl.value, { border: 2, pixelSize: 8, blackColor: '#000', whiteColor: '#fff' })
  : ''))
let pollTimer: ReturnType<typeof setTimeout> | null = null
/** Bumped on cancel so a start or poll that's still in flight is ignored. */
let loginRun = 0
let linkTimer: ReturnType<typeof setTimeout> | null = null
/** Same as `loginRun`, for the device link. */
let linkRun = 0
let linkStarting: Promise<void> | null = null

const serverUrl = ref('')
const username = ref('')
const password = ref('')
const directError = ref('')
const directBusy = ref(false)
const quickConnectCode = ref('')
const quickConnectBusy = ref(false)
/** Roster id being signed in to from the server picker. */
const selectingServer = ref<string | null>(null)
/** The roster with the user's nicknames and order from Settings. */
const { entries: serverEntries } = useServers()
const rosterServers = computed(() => serverEntries.value.filter(entry => entry.kind === 'soup'))

/** Jellyfin servers that answered from this browser, offered on the idle screen. */
const nearby = ref<DiscoveredServer[]>([])
const scanning = ref(false)
let lastServer: string | null = null
/** Same as `loginRun`, for network scans. */
let scanRun = 0

onMounted(async () => {
  try {
    lastServer = localStorage.getItem(LAST_SERVER_KEY)
  }
  catch {
    lastServer = null
  }
  serverUrl.value = lastServer || config.public.jellyfinUrl || ''
  if (!auth.ready.value) await auth.hydrate()
  if (auth.jellyfin.value) {
    await router.replace('/')
  }
  else if (auth.choosingServer.value) {
    phase.value = 'server'
  }
  else {
    void ensureLink()
    void scanNetwork()
  }
})

async function scanNetwork() {
  if (mock || scanning.value) return
  const run = ++scanRun
  scanning.value = true
  try {
    const found = await discoverServers([lastServer, config.public.jellyfinUrl])
    if (run === scanRun) nearby.value = found
  }
  finally {
    if (run === scanRun) scanning.value = false
  }
}

/** Direct sign-in against a server picked from the scan. */
function connectTo(server: DiscoveredServer) {
  serverUrl.value = server.url
  showDirect()
}

function submitAddress() {
  if (serverUrl.value.trim()) showDirect()
}

// The QR code is on the idle screen, so keep a link going whenever we land back there.
watch(phase, (next) => {
  if (next === 'idle') void ensureLink()
})

onBeforeUnmount(() => {
  loginRun++
  scanRun++
  if (pollTimer) clearTimeout(pollTimer)
  stopLink()
})

function stopLink() {
  linkRun++
  if (linkTimer) clearTimeout(linkTimer)
  linkTimer = null
  linkStarting = null
  userCode.value = ''
  verificationUrl.value = ''
  void auth.cancelLogin()
}

/** Starts a device link (backs both the QR code and "Sign in with Google") unless one is live. */
function ensureLink(): Promise<void> {
  if (mock || verificationUrl.value) return Promise.resolve()
  if (linkStarting) return linkStarting
  linkError.value = ''
  const run = ++linkRun
  linkStarting = (async () => {
    try {
      const started = await auth.startLogin()
      if (run !== linkRun) return
      userCode.value = started.userCode
      verificationUrl.value = started.verificationUrl
      scheduleLinkPoll(started.interval || 5, run)
    }
    catch (error) {
      if (run !== linkRun) return
      linkError.value = error instanceof Error ? error.message : 'Could not start sign-in'
    }
    finally {
      if (run === linkRun) linkStarting = null
    }
  })()
  return linkStarting
}

/** Fresh link once the old one expires, so the QR code never goes stale on screen. */
function restartLink() {
  stopLink()
  void ensureLink()
}

function showDirect() {
  stopLink()
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
      const { status } = await auth.pollQuickConnect(baseUrl, secret)
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

/** Opens the verification page for the live link; the QR code's poll finishes the sign-in. */
async function beginLogin() {
  if (mock) {
    await beginMock()
    return
  }
  errorMessage.value = ''
  // Opened from the click itself when the link is ready, so popup blockers let it through.
  const popup = verificationUrl.value ? null : window.open('', '_blank')
  if (verificationUrl.value) window.open(verificationUrl.value, '_blank', 'noopener,noreferrer')
  phase.value = 'waiting'
  await ensureLink()
  if (!verificationUrl.value) {
    popup?.close()
    phase.value = 'error'
    errorMessage.value = linkError.value || 'Could not start sign-in'
    return
  }
  if (popup) {
    popup.opener = null
    popup.location.href = verificationUrl.value
  }
}

function scheduleLinkPoll(intervalSec: number, run: number) {
  if (linkTimer) clearTimeout(linkTimer)
  linkTimer = setTimeout(async () => {
    try {
      const result = await auth.pollLogin()
      if (run !== linkRun) return
      if (result.status === 'approved') {
        await router.replace('/')
        return
      }
      if (result.status === 'chooseServer') {
        verificationUrl.value = ''
        phase.value = 'server'
        return
      }
      if (result.status === 'expired') {
        if (phase.value === 'waiting') {
          stopLink()
          phase.value = 'error'
          errorMessage.value = 'Sign-in code expired. Try again.'
        }
        else {
          restartLink()
        }
        return
      }
      scheduleLinkPoll(result.interval || intervalSec, run)
    }
    catch (error) {
      if (run !== linkRun) return
      stopLink()
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
        class="glass-strong flex w-full max-w-[480px] flex-col gap-5 rounded-[28px] p-8 shadow-[0_40px_80px_rgba(0,0,0,0.5)] sm:p-11"
      >
        <h1
          v-if="!mock && (phase === 'idle' || phase === 'error')"
          id="login-title"
          class="pb-2 text-center text-[64px] leading-none"
        >
          <SoupWordmark />
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
          <div class="flex items-center gap-[18px] rounded-[20px] bg-white/5 p-3.5 max-sm:order-last">
            <div
              v-if="linkError"
              class="flex size-32 shrink-0 flex-col items-center justify-center gap-2 rounded-2xl bg-white/5 p-3 text-center"
            >
              <p class="text-[12px] font-semibold text-accent">
                {{ linkError }}
              </p>
              <button type="button" class="text-[13px] font-bold text-ink-2 hover:text-ink hover:underline" @click="ensureLink()">
                Retry
              </button>
            </div>
            <div v-else-if="!qrSvg" class="size-32 shrink-0 animate-pulse rounded-2xl bg-white/10" />
            <div
              v-else
              role="img"
              aria-label="QR code to sign in on your phone"
              class="size-32 shrink-0 overflow-hidden rounded-2xl bg-white p-2 [&>svg]:block [&>svg]:size-full"
              v-html="qrSvg"
            />
            <div class="flex min-w-0 flex-col gap-1.5">
              <h2 class="text-[17px] font-extrabold">
                Scan with your phone
              </h2>
              <p class="text-sm leading-snug text-ink-2">
                Point your camera at the code and sign in there. Your phone will show
              </p>
              <p v-if="userCode" class="text-[22px] font-extrabold tracking-[3px]">
                {{ userCode }}
              </p>
              <div v-else class="h-7 w-28 animate-pulse rounded-md bg-white/10" />
            </div>
          </div>

          <button
            type="button"
            class="flex h-[52px] items-center justify-center gap-2.5 rounded-btn bg-ink text-[17px] font-extrabold text-canvas transition hover:bg-ink/80"
            @click="beginLogin"
          >
            <svg viewBox="0 0 48 48" class="size-5 shrink-0" aria-hidden="true">
              <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z" />
              <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z" />
              <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z" />
              <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z" />
            </svg>
            Continue with Google
          </button>

          <div class="flex items-center gap-3 text-[13px] font-semibold text-muted" aria-hidden="true">
            <span class="h-px flex-1 bg-white/10" />or connect to a Jellyfin server<span class="h-px flex-1 bg-white/10" />
          </div>

          <section aria-labelledby="nearby-title" class="flex flex-col gap-2">
            <div class="flex items-center justify-between px-0.5">
              <h2 id="nearby-title" class="text-[13px] font-bold text-muted">
                On your network
              </h2>
              <span v-if="scanning" class="flex items-center gap-2 text-xs font-bold text-muted" role="status">
                <span class="relative size-2">
                  <span class="absolute inset-0 animate-ping rounded-full bg-accent motion-reduce:animate-none" />
                  <span class="absolute inset-0 rounded-full bg-accent" />
                </span>
                Scanning
              </span>
              <button
                v-else
                type="button"
                class="text-xs font-bold text-muted transition hover:text-ink"
                @click="scanNetwork"
              >
                Scan again
              </button>
            </div>
            <ul v-if="nearby.length" class="flex flex-col gap-2">
              <li v-for="server in nearby" :key="server.id">
                <button
                  type="button"
                  class="flex w-full items-center gap-3 rounded-btn bg-white/[0.08] px-3.5 py-3 text-left transition hover:bg-white/15"
                  @click="connectTo(server)"
                >
                  <span class="grid size-9 shrink-0 place-items-center rounded-[10px] bg-white/[0.08]">
                    <svg viewBox="0 0 24 24" class="size-[18px]" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                      <rect x="3" y="4" width="18" height="7" rx="2" /><rect x="3" y="13" width="18" height="7" rx="2" /><path d="M7 7.5h.01M7 16.5h.01" />
                    </svg>
                  </span>
                  <span class="flex min-w-0 flex-1 flex-col">
                    <span class="truncate text-base font-extrabold">{{ server.name }}</span>
                    <span class="truncate text-[13px] font-semibold text-muted">
                      {{ server.host }}<template v-if="server.version"> · Jellyfin {{ server.version }}</template>
                    </span>
                  </span>
                  <svg viewBox="0 0 24 24" class="size-[18px] shrink-0 text-muted" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <path d="m9 6 6 6-6 6" />
                  </svg>
                </button>
              </li>
            </ul>
            <div v-else-if="!scanning" class="flex items-start gap-3 rounded-btn bg-white/5 p-3.5">
              <svg viewBox="0 0 24 24" class="mt-px size-5 shrink-0 text-muted" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M12 20h.01M8.5 16.43a5 5 0 0 1 7 0M5 12.86a10 10 0 0 1 5.17-2.69M19 12.86a10 10 0 0 0-2-1.52M2 8.82a15 15 0 0 1 4.18-2.64M22 8.82a15 15 0 0 0-11.29-3.76M2 2l20 20" />
              </svg>
              <span class="flex flex-col gap-0.5">
                <span class="text-[15px] font-extrabold">No servers found yet</span>
                <span class="text-[13px] font-semibold leading-snug text-muted">Check you're on the same network as your Jellyfin server, or enter its address below.</span>
              </span>
            </div>
            <div v-else class="h-[60px] animate-pulse rounded-btn bg-white/[0.08]" />
          </section>

          <form class="flex gap-2" @submit.prevent="submitAddress">
            <label for="server-address" class="sr-only">Server address</label>
            <input
              id="server-address"
              v-model="serverUrl"
              type="text"
              inputmode="url"
              autocomplete="url"
              autocapitalize="off"
              spellcheck="false"
              placeholder="Or enter a server address"
              class="h-12 min-w-0 flex-1 rounded-btn bg-white/10 px-4 text-[15px] font-semibold text-ink placeholder:text-muted/70 focus:bg-white/15 focus:outline-none focus-visible:ring-2 focus-visible:ring-ink"
            >
            <button
              type="submit"
              aria-label="Connect"
              :disabled="!serverUrl.trim()"
              class="grid size-12 shrink-0 place-items-center rounded-btn bg-white/10 text-ink transition enabled:hover:bg-white/15 disabled:opacity-50"
            >
              <svg viewBox="0 0 24 24" class="size-5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M5 12h14M13 6l6 6-6 6" />
              </svg>
            </button>
          </form>
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
            <li v-for="server in rosterServers" :key="server.key">
              <button
                type="button"
                :disabled="selectingServer !== null"
                class="flex w-full items-center gap-3 rounded-btn bg-white/10 px-4 py-3.5 text-left transition hover:bg-white/15 disabled:opacity-60"
                @click="chooseServer(server.id)"
              >
                <span class="flex min-w-0 flex-1 flex-col">
                  <span class="truncate text-[17px] font-extrabold">{{ server.name }}</span>
                  <span class="truncate text-[13px] font-semibold text-muted">{{ server.host }}</span>
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
            @click="phase = 'idle'"
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
