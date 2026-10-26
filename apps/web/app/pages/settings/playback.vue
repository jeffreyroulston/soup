<script setup lang="ts">
import type { SelectOption } from '~/components/SelectMenu.vue'

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
</script>

<template>
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
</template>
