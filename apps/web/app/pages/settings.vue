<script setup lang="ts">
import type { SelectOption } from '~/components/SelectMenu.vue'

definePageMeta({ middleware: 'auth', layout: 'app' })

const auth = useAuthSession()
const { prefs, update } = usePlaybackPrefs()

const qualityOptions: SelectOption<number | null>[] = [
  { value: null, label: 'Auto', detail: 'Best available' },
  ...QUALITY_CAPS.map(q => ({ value: q.bitrate, label: q.label, detail: q.detail })),
]
const audioOptions: SelectOption<string | null>[] = [
  { value: null, label: 'File default' },
  ...PREF_LANGUAGES.map(l => ({ value: l.code, label: l.label })),
]
const subtitleOptions: SelectOption<string | null>[] = [
  { value: null, label: 'Off' },
  ...PREF_LANGUAGES.map(l => ({ value: l.code, label: l.label })),
]

const maxBitrate = computed({ get: () => prefs.value.maxBitrate, set: value => update({ maxBitrate: value }) })
const audioLanguage = computed({ get: () => prefs.value.audioLanguage, set: value => update({ audioLanguage: value }) })
const subtitleLanguage = computed({ get: () => prefs.value.subtitleLanguage, set: value => update({ subtitleLanguage: value }) })

const toggles = [
  {
    key: 'autoplayNext',
    label: 'Autoplay next episode',
    detail: 'Count down and start the next episode when the credits begin.',
  },
  {
    key: 'autoSkipIntros',
    label: 'Skip intros and recaps',
    detail: 'Jump past them automatically instead of showing a Skip button.',
  },
] as const

const identity = useIdentityConfig()
const identityInput = ref(identity.url.value)
const identityBusy = ref(false)
const identitySourceLabel = computed(() => ({
  override: 'Set in this browser',
  config: 'From the deployment config',
  build: 'Built-in default',
}[identity.source.value]))
const identityDirty = computed(() => normalizeIdentityUrl(identityInput.value) !== identity.url.value)

/** Tokens belong to the old server, so changing Identity signs this browser out. */
async function applyIdentity(input: string | null) {
  identityBusy.value = true
  try {
    await auth.logout()
    identity.setOverride(input)
    identityInput.value = identity.url.value
    await navigateTo('/login')
  }
  finally {
    identityBusy.value = false
  }
}

async function onLogout() {
  await auth.logout()
  await navigateTo('/login')
}
</script>

<template>
  <main class="mx-auto w-full max-w-2xl px-4 pb-20 pt-24 sm:px-8 sm:pt-32">
    <h1 class="mb-8 text-[clamp(2.5rem,5vw,3.5rem)] font-extrabold leading-none tracking-[-0.04em]">
      Settings
    </h1>

    <div class="flex flex-col gap-4">
      <section aria-labelledby="settings-account" class="flex flex-col gap-1.5 rounded-panel bg-surface p-6">
        <h2 id="settings-account" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
          Account
        </h2>
        <p class="text-lg font-bold">
          {{ auth.email.value || 'Signed in' }}
        </p>
      </section>

      <section v-if="!isMockMode()" aria-labelledby="settings-identity" class="flex flex-col gap-3 rounded-panel bg-surface p-6">
        <h2 id="settings-identity" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
          Identity server
        </h2>
        <p class="text-sm text-muted">
          Where sign-in happens. {{ identitySourceLabel }}. Changing it signs you out.
        </p>
        <form class="flex flex-col gap-3 sm:flex-row" @submit.prevent="applyIdentity(identityInput)">
          <input
            v-model="identityInput"
            type="url"
            inputmode="url"
            autocomplete="off"
            spellcheck="false"
            aria-label="Identity server URL"
            placeholder="https://identity.example.com"
            class="h-12 min-w-0 flex-1 rounded-btn border border-white/10 bg-elevated px-4 text-base font-semibold text-ink outline-none focus:border-accent"
          >
          <div class="flex gap-2">
            <button
              type="submit"
              :disabled="identityBusy || !identityDirty || !normalizeIdentityUrl(identityInput)"
              class="h-12 rounded-btn bg-ink px-5 text-base font-extrabold text-canvas transition hover:bg-ink/80 disabled:opacity-40"
            >
              Save
            </button>
            <button
              v-if="identity.source.value === 'override'"
              type="button"
              :disabled="identityBusy"
              class="h-12 rounded-btn bg-elevated px-5 text-base font-bold text-ink-2 transition hover:text-ink disabled:opacity-40"
              @click="applyIdentity(null)"
            >
              Reset
            </button>
          </div>
        </form>
      </section>

      <section aria-labelledby="settings-playback" class="flex flex-col gap-5 rounded-panel bg-surface p-6">
        <h2 id="settings-playback" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
          Playback
        </h2>

        <div
          v-for="toggle in toggles"
          :key="toggle.key"
          class="flex items-center justify-between gap-4"
        >
          <div class="flex min-w-0 flex-col gap-0.5">
            <span :id="`pref-${toggle.key}`" class="text-base font-bold">{{ toggle.label }}</span>
            <span class="text-sm text-muted">{{ toggle.detail }}</span>
          </div>
          <button
            type="button"
            role="switch"
            :aria-checked="prefs[toggle.key]"
            :aria-labelledby="`pref-${toggle.key}`"
            class="relative h-8 w-[52px] shrink-0 rounded-full transition-colors"
            :class="prefs[toggle.key] ? 'bg-ok' : 'bg-elevated'"
            @click="update({ [toggle.key]: !prefs[toggle.key] })"
          >
            <span
              class="absolute left-1 top-1 size-6 rounded-full bg-white shadow transition-transform"
              :class="prefs[toggle.key] ? 'translate-x-5' : ''"
            />
          </button>
        </div>

        <div class="flex items-center justify-between gap-4">
          <div class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span class="text-base font-bold">Default quality</span>
            <span class="text-sm text-muted">Auto plays the original file when it can.</span>
          </div>
          <SelectMenu v-model="maxBitrate" :options="qualityOptions" label="Default quality" />
        </div>

        <div class="flex items-center justify-between gap-4">
          <div class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span class="text-base font-bold">Audio language</span>
            <span class="text-sm text-muted">Used when a title has a track in this language.</span>
          </div>
          <SelectMenu v-model="audioLanguage" :options="audioOptions" label="Audio language" />
        </div>

        <div class="flex items-center justify-between gap-4">
          <div class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span class="text-base font-bold">Subtitles</span>
            <span class="text-sm text-muted">Turned on when a title has subtitles in this language.</span>
          </div>
          <SelectMenu v-model="subtitleLanguage" :options="subtitleOptions" label="Subtitle language" />
        </div>

        <p class="text-[13px] leading-snug text-muted">
          Saved in this browser. You can still change tracks and quality while watching.
        </p>
      </section>

      <button
        type="button"
        class="h-[52px] self-start rounded-btn bg-ink px-7 text-base font-extrabold text-canvas transition hover:bg-ink/80"
        @click="onLogout"
      >
        Sign out
      </button>
    </div>
  </main>
</template>
