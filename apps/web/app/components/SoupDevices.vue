<script setup lang="ts">
import {
  IdentityError,
  listDevices,
  renameDevice,
  revokeDevice,
  revokeOtherDevices,
  type DevicePlatform,
  type SoupDevice,
} from '~/utils/soupIdentity'

const auth = useAuthSession()
const base = auth.identityBaseUrl

const devices = ref<SoupDevice[]>([])
const loading = ref(false)
const loaded = ref(false)
const error = ref('')
const editing = ref(false)
/** Device id waiting for a second click to confirm signing it out; 'others' for the bulk action. */
const confirming = ref<string | null>(null)
const busy = ref<string | null>(null)

const others = computed(() => devices.value.filter(device => !device.current))

const PLATFORMS: Record<DevicePlatform, { label: string, icon: string }> = {
  webos: { label: 'webOS TV', icon: 'M3 5h18v12H3zM8 21h8M12 17v4' },
  android_tv: { label: 'Android TV', icon: 'M3 5h18v12H3zM8 21h8M12 17v4' },
  android: { label: 'Android', icon: 'M7 2h10a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zM11 18h2' },
  ios: { label: 'iOS', icon: 'M7 2h10a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zM11 18h2' },
  web: { label: 'Web', icon: 'M2 4h20v12H2zM12 16v4M7 20h10' },
}
const UNKNOWN_ICON = 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01'

const relative = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })
const STEPS: [Intl.RelativeTimeFormatUnit, number][] = [
  ['minute', 60], ['hour', 60], ['day', 24], ['week', 7], ['month', 4.35], ['year', 12],
]

/** "5 minutes ago"; Identity only updates last use on token refresh, so anything recent is "now". */
function ago(iso: string): string {
  let value = (new Date(iso).getTime() - Date.now()) / 60_000
  if (value > -15) return 'just now'
  for (let i = 1; i < STEPS.length; i++) {
    if (Math.abs(value) < STEPS[i]![1]) return relative.format(Math.round(value), STEPS[i - 1]![0])
    value /= STEPS[i]![1]
  }
  return relative.format(Math.round(value), 'year')
}

function platformOf(device: SoupDevice) {
  return device.platform ? PLATFORMS[device.platform] : undefined
}

function nameOf(device: SoupDevice): string {
  return device.device_name ?? platformOf(device)?.label ?? 'Unknown device'
}

function subtitleOf(device: SoupDevice): string {
  const platform = platformOf(device)?.label
  return [
    device.device_name && platform,
    device.current ? 'Active now' : `Active ${ago(device.last_used_at)}`,
    `Signed in ${new Date(device.created_at).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}`,
  ].filter(Boolean).join(' · ')
}

/** Identity errors arrive as raw JSON bodies; show their `message`, else the fallback. */
function message(err: unknown, fallback: string): string {
  if (!(err instanceof Error)) return fallback
  if (!(err instanceof IdentityError)) return err.message || fallback
  try {
    return (JSON.parse(err.message) as { message?: string }).message || fallback
  }
  catch {
    return err.status === 503 ? err.message : fallback
  }
}

onMounted(() => void load())

async function load() {
  if (loading.value) return
  loading.value = true
  error.value = ''
  try {
    devices.value = await auth.withSoupAccess(token => listDevices(base, token))
    loaded.value = true
  }
  catch (err) {
    error.value = err instanceof IdentityError && err.status === 404
      ? 'This Identity server doesn’t support managing devices yet.'
      : message(err, 'Could not load your devices')
  }
  finally {
    loading.value = false
  }
}

function toggleEditing() {
  editing.value = !editing.value
  confirming.value = null
}

async function onRename(device: SoupDevice, value: string) {
  const name = value.trim()
  if (name === (device.device_name ?? '')) return
  error.value = ''
  try {
    await auth.withSoupAccess(token => renameDevice(base, token, device.id, name))
    device.device_name = name || null
  }
  catch (err) {
    error.value = message(err, 'Could not rename that device')
  }
}

async function onSignOut(device: SoupDevice) {
  if (confirming.value !== device.id) {
    confirming.value = device.id
    return
  }
  confirming.value = null
  busy.value = device.id
  error.value = ''
  try {
    await auth.withSoupAccess(token => revokeDevice(base, token, device.id))
    devices.value = devices.value.filter(d => d.id !== device.id)
  }
  catch (err) {
    error.value = message(err, 'Could not sign that device out')
    // It may already be gone, e.g. signed out from another device.
    void load()
  }
  finally {
    busy.value = null
  }
}

async function onSignOutOthers() {
  if (confirming.value !== 'others') {
    confirming.value = 'others'
    return
  }
  confirming.value = null
  busy.value = 'others'
  error.value = ''
  try {
    await auth.withSoupAccess(token => revokeOtherDevices(base, token))
    devices.value = devices.value.filter(d => d.current)
    editing.value = false
  }
  catch (err) {
    error.value = message(err, 'Could not sign the other devices out')
  }
  finally {
    busy.value = null
  }
}
</script>

<template>
  <section aria-labelledby="settings-devices" class="flex flex-col gap-4 rounded-panel bg-surface p-6">
    <div class="flex items-center justify-between gap-3">
      <h2 id="settings-devices" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
        Devices
      </h2>
      <div class="flex items-center gap-2">
        <button
          v-if="loaded && devices.length > 0"
          type="button"
          :aria-pressed="editing"
          class="h-9 rounded-full px-4 text-[13px] font-bold transition"
          :class="editing ? 'bg-ok text-canvas' : 'text-ink-2 hover:bg-white/10 hover:text-ink'"
          @click="toggleEditing"
        >
          {{ editing ? 'Done' : 'Edit' }}
        </button>
        <button
          v-if="!editing"
          type="button"
          :disabled="loading"
          class="flex items-center gap-2 px-1 text-[13px] font-bold text-muted transition enabled:hover:text-ink"
          @click="load"
        >
          <span v-if="loading" class="size-3.5 animate-spin rounded-full border-2 border-muted/30 border-t-muted" />
          Refresh
        </button>
      </div>
    </div>

    <p v-if="error" role="alert" class="text-sm font-semibold text-accent">
      {{ error }}
    </p>

    <ul v-if="!loaded && loading" class="flex flex-col gap-1" aria-hidden="true">
      <li v-for="n in 2" :key="n" class="flex items-center gap-3 px-3 py-2.5">
        <span class="size-10 shrink-0 animate-pulse rounded-[12px] bg-white/5" />
        <span class="flex flex-1 flex-col gap-1.5">
          <span class="h-4 w-36 animate-pulse rounded bg-white/5" />
          <span class="h-3 w-52 animate-pulse rounded bg-white/5" />
        </span>
      </li>
    </ul>

    <ul v-else-if="devices.length" class="flex flex-col gap-1">
      <li
        v-for="device in devices"
        :key="device.id"
        class="flex items-center gap-3 rounded-btn px-3 py-2.5 transition-colors"
        :class="editing ? '' : 'hover:bg-white/[0.04]'"
      >
        <span
          class="grid size-10 shrink-0 place-items-center rounded-[12px]"
          :class="device.current ? 'bg-ok/15 text-ok' : 'bg-white/5 text-ink-2'"
        >
          <svg viewBox="0 0 24 24" class="size-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path :d="platformOf(device)?.icon ?? UNKNOWN_ICON" />
          </svg>
        </span>

        <span v-if="editing" class="flex min-w-0 flex-1 flex-col gap-1">
          <input
            :value="device.device_name ?? ''"
            type="text"
            :placeholder="platformOf(device)?.label ?? 'Unknown device'"
            :aria-label="`Name for ${nameOf(device)}`"
            maxlength="64"
            class="h-10 min-w-0 rounded-[10px] border border-white/10 bg-elevated px-3 text-[15px] font-bold text-ink outline-none placeholder:text-ink-2/60 focus:border-accent"
            @change="onRename(device, ($event.target as HTMLInputElement).value)"
            @keydown.enter="($event.target as HTMLInputElement).blur()"
          >
          <span class="truncate px-0.5 text-[13px] font-semibold text-muted">{{ subtitleOf(device) }}</span>
        </span>
        <span v-else class="flex min-w-0 flex-1 flex-col">
          <span class="truncate text-base font-bold">{{ nameOf(device) }}</span>
          <span class="truncate text-[13px] font-semibold text-muted">{{ subtitleOf(device) }}</span>
        </span>

        <span v-if="device.current" class="shrink-0 rounded-full bg-ok/15 px-3 py-1 text-xs font-extrabold text-ok max-sm:sr-only">
          This browser
        </span>
        <button
          v-else-if="editing"
          type="button"
          :disabled="busy !== null"
          :aria-label="confirming === device.id ? `Confirm signing out ${nameOf(device)}` : `Sign out ${nameOf(device)}`"
          class="grid h-9 min-w-9 shrink-0 place-items-center rounded-full text-[13px] font-bold transition disabled:opacity-50"
          :class="confirming === device.id || busy === device.id ? 'bg-accent px-3.5 text-canvas' : 'text-muted hover:bg-white/10 hover:text-ink'"
          @click="onSignOut(device)"
          @blur="confirming === device.id && (confirming = null)"
        >
          <template v-if="busy === device.id">Signing out…</template>
          <template v-else-if="confirming === device.id">Sign out?</template>
          <svg v-else viewBox="0 0 24 24" class="size-[18px]" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
          </svg>
        </button>
      </li>
    </ul>

    <p v-else-if="loaded" class="text-sm text-muted">
      No devices are signed in to this Soup account.
    </p>

    <div
      v-if="others.length"
      class="flex flex-col gap-2 border-t border-white/10 pt-4 sm:flex-row sm:items-center sm:justify-between"
    >
      <p class="text-sm text-muted">
        Signs out {{ others.length === 1 ? 'the other device' : `all ${others.length} other devices` }} and keeps this browser signed in.
      </p>
      <button
        type="button"
        :disabled="busy !== null"
        class="h-11 shrink-0 self-start rounded-btn px-5 text-[15px] font-extrabold transition disabled:opacity-50"
        :class="confirming === 'others' || busy === 'others' ? 'bg-accent text-canvas' : 'bg-elevated text-ink hover:bg-white/10'"
        @click="onSignOutOthers"
        @blur="confirming === 'others' && (confirming = null)"
      >
        <template v-if="busy === 'others'">Signing out…</template>
        <template v-else-if="confirming === 'others'">Sign out {{ others.length === 1 ? 'it' : 'all' }}?</template>
        <template v-else>Sign out other devices</template>
      </button>
    </div>
  </section>
</template>
