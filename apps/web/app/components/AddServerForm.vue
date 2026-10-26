<script setup lang="ts">
import { LAST_SERVER_KEY, type SavedServer } from '~/composables/useAuthSession'
import { discoverServers, type DiscoveredServer } from '~/utils/discoverServers'

const emit = defineEmits<{ added: [server: SavedServer], cancel: [] }>()

const config = useRuntimeConfig()
const auth = useAuthSession()

const step = ref<'find' | 'credentials' | 'quickConnect'>('find')
const serverUrl = ref('')
const username = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)
const quickConnectCode = ref('')
const quickConnectBusy = ref(false)
let pollTimer: ReturnType<typeof setTimeout> | null = null
/** Bumped on cancel so a Quick Connect poll that's still in flight is ignored. */
let run = 0

const nearby = ref<DiscoveredServer[]>([])
const scanning = ref(false)
const savedServerIds = computed(() => new Set(auth.savedServers.value.map(server => server.serverId)))

onMounted(() => void scan())
onBeforeUnmount(() => {
  run++
  if (pollTimer) clearTimeout(pollTimer)
})

async function scan() {
  if (scanning.value || isMockMode()) return
  scanning.value = true
  try {
    let last: string | null = null
    try {
      last = localStorage.getItem(LAST_SERVER_KEY)
    }
    catch {
      // storage blocked
    }
    nearby.value = await discoverServers([
      last,
      config.public.jellyfinUrl,
      ...auth.savedServers.value.map(server => server.baseUrl),
    ])
  }
  finally {
    scanning.value = false
  }
}

function pick(url: string) {
  if (!url.trim()) return
  serverUrl.value = url
  error.value = ''
  step.value = 'credentials'
}

async function submit() {
  if (busy.value) return
  error.value = ''
  busy.value = true
  try {
    emit('added', await auth.signInDirect(serverUrl.value, username.value.trim(), password.value, { activate: false }))
  }
  catch (err) {
    error.value = err instanceof Error ? err.message : 'Could not sign in'
  }
  finally {
    busy.value = false
  }
}

async function beginQuickConnect() {
  if (quickConnectBusy.value) return
  error.value = ''
  quickConnectBusy.value = true
  const current = ++run
  try {
    const started = await auth.startQuickConnect(serverUrl.value)
    if (current !== run) return
    quickConnectCode.value = started.code
    step.value = 'quickConnect'
    schedulePoll(started.baseUrl, started.secret, current)
  }
  catch (err) {
    if (current === run) error.value = err instanceof Error ? err.message : 'Could not start Quick Connect'
  }
  finally {
    quickConnectBusy.value = false
  }
}

function schedulePoll(baseUrl: string, secret: string, current: number) {
  pollTimer = setTimeout(async () => {
    try {
      const result = await auth.pollQuickConnect(baseUrl, secret, { activate: false })
      if (current !== run) return
      if (result.status === 'approved') {
        emit('added', result.server)
        return
      }
      if (result.status === 'expired') {
        endQuickConnect('That code expired. Start Quick Connect again.')
        return
      }
      schedulePoll(baseUrl, secret, current)
    }
    catch (err) {
      if (current === run) endQuickConnect(err instanceof Error ? err.message : 'Quick Connect failed')
    }
  }, 5000)
}

function endQuickConnect(message = '') {
  run++
  if (pollTimer) clearTimeout(pollTimer)
  pollTimer = null
  quickConnectCode.value = ''
  error.value = message
  step.value = 'credentials'
}
</script>

<template>
  <div class="flex flex-col gap-4 rounded-[18px] bg-elevated/60 p-5">
    <template v-if="step === 'find'">
      <div class="flex items-center justify-between">
        <h3 class="text-[15px] font-extrabold">
          On your network
        </h3>
        <span v-if="scanning" class="flex items-center gap-2 text-xs font-bold text-muted" role="status">
          <span class="relative size-2">
            <span class="absolute inset-0 animate-ping rounded-full bg-accent motion-reduce:animate-none" />
            <span class="absolute inset-0 rounded-full bg-accent" />
          </span>
          Scanning
        </span>
        <button v-else type="button" class="text-xs font-bold text-muted transition hover:text-ink" @click="scan">
          Scan again
        </button>
      </div>

      <ul v-if="nearby.length" class="flex flex-col gap-2">
        <li v-for="server in nearby" :key="server.id">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-btn bg-white/[0.06] px-3.5 py-3 text-left transition hover:bg-white/10"
            @click="pick(server.url)"
          >
            <span class="flex min-w-0 flex-1 flex-col">
              <span class="truncate text-base font-extrabold">{{ server.name }}</span>
              <span class="truncate text-[13px] font-semibold text-muted">
                {{ server.host }}<template v-if="server.version"> · Jellyfin {{ server.version }}</template>
              </span>
            </span>
            <span v-if="savedServerIds.has(server.id)" class="shrink-0 text-xs font-bold text-muted">Added</span>
            <svg viewBox="0 0 24 24" class="size-[18px] shrink-0 text-muted" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="m9 6 6 6-6 6" />
            </svg>
          </button>
        </li>
      </ul>
      <p v-else-if="!scanning" class="text-sm text-muted">
        Nothing found from this browser. Enter the server's address instead.
      </p>
      <div v-else class="h-[60px] animate-pulse rounded-btn bg-white/[0.06]" />

      <form class="flex gap-2" @submit.prevent="pick(serverUrl)">
        <label for="add-server-address" class="sr-only">Server address</label>
        <input
          id="add-server-address"
          v-model="serverUrl"
          type="text"
          inputmode="url"
          autocomplete="url"
          autocapitalize="off"
          spellcheck="false"
          placeholder="https://jellyfin.example.com"
          class="h-12 min-w-0 flex-1 rounded-btn border border-white/10 bg-elevated px-4 text-base font-semibold text-ink outline-none placeholder:text-muted/70 focus:border-accent"
        >
        <button
          type="submit"
          :disabled="!serverUrl.trim()"
          class="h-12 shrink-0 rounded-btn bg-ink px-5 text-base font-extrabold text-canvas transition enabled:hover:bg-ink/80 disabled:opacity-40"
        >
          Next
        </button>
      </form>
    </template>

    <form v-else-if="step === 'credentials'" class="flex flex-col gap-3" @submit.prevent="submit">
      <div class="flex items-center justify-between gap-3">
        <p class="min-w-0 truncate text-[15px] font-extrabold">
          {{ normalizeServerUrl(serverUrl) }}
        </p>
        <button type="button" class="shrink-0 text-[13px] font-bold text-muted transition hover:text-ink" @click="step = 'find'">
          Change
        </button>
      </div>
      <label class="flex flex-col gap-1.5">
        <span class="text-[13px] font-bold text-muted">Username</span>
        <input
          v-model="username"
          type="text"
          autocomplete="username"
          autocapitalize="off"
          spellcheck="false"
          required
          class="h-12 rounded-btn border border-white/10 bg-elevated px-4 text-base font-semibold text-ink outline-none focus:border-accent"
        >
      </label>
      <label class="flex flex-col gap-1.5">
        <span class="text-[13px] font-bold text-muted">Password</span>
        <input
          v-model="password"
          type="password"
          autocomplete="current-password"
          class="h-12 rounded-btn border border-white/10 bg-elevated px-4 text-base font-semibold text-ink outline-none focus:border-accent"
        >
      </label>
      <p v-if="error" role="alert" class="text-sm font-semibold text-accent">
        {{ error }}
      </p>
      <div class="flex flex-wrap gap-2 pt-1">
        <button
          type="submit"
          :disabled="busy"
          class="flex h-11 items-center gap-2 rounded-btn bg-ink px-5 text-[15px] font-extrabold text-canvas transition enabled:hover:bg-ink/80 disabled:opacity-60"
        >
          <span v-if="busy" class="size-4 animate-spin rounded-full border-2 border-canvas/30 border-t-canvas" />
          Add server
        </button>
        <button
          type="button"
          :disabled="quickConnectBusy"
          class="flex h-11 items-center gap-2 rounded-btn bg-white/10 px-5 text-[15px] font-bold text-ink transition enabled:hover:bg-white/15 disabled:opacity-50"
          @click="beginQuickConnect"
        >
          <span v-if="quickConnectBusy" class="size-4 animate-spin rounded-full border-2 border-ink/30 border-t-ink" />
          Use Quick Connect
        </button>
      </div>
    </form>

    <template v-else>
      <p class="text-sm leading-relaxed text-ink-2">
        In a Jellyfin app that's signed in to this server, open your profile, choose
        <strong class="text-ink">Quick Connect</strong>, and enter:
      </p>
      <p :aria-label="`Code ${quickConnectCode}`" class="text-[32px] font-extrabold tracking-[6px]">
        {{ quickConnectCode }}
      </p>
      <div class="flex items-center gap-2.5 text-sm font-semibold text-muted">
        <span class="size-4 animate-spin rounded-full border-2 border-[#3A3A3C] border-t-accent" />
        Waiting for approval
      </div>
      <button type="button" class="self-start text-[13px] font-bold text-muted transition hover:text-ink" @click="endQuickConnect()">
        Back
      </button>
    </template>

    <button
      v-if="step !== 'quickConnect'"
      type="button"
      class="self-start text-[13px] font-bold text-muted transition hover:text-ink"
      @click="emit('cancel')"
    >
      Cancel
    </button>
  </div>
</template>
