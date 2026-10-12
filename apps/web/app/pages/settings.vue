<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'app' })

const route = useRoute()

const sections = [
  { to: '/settings/general', label: 'General', icon: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z' },
  { to: '/settings/servers', label: 'Servers', icon: 'M3 4h18v7H3zM3 13h18v7H3zM7 7.5h.01M7 16.5h.01' },
  { to: '/settings/playback', label: 'Playback', icon: 'M6 4l14 8-14 8z' },
]
</script>

<template>
  <main class="mx-auto w-full max-w-5xl px-4 pb-20 pt-24 sm:px-8 sm:pt-32">
    <h1 class="mb-8 text-[clamp(2.5rem,5vw,3.5rem)] font-extrabold leading-none tracking-[-0.04em]">
      Settings
    </h1>

    <div class="flex flex-col gap-6 md:flex-row md:items-start md:gap-10">
      <nav aria-label="Settings sections" class="-mx-4 px-4 md:sticky md:top-28 md:mx-0 md:w-52 md:shrink-0 md:px-0">
        <ul class="flex gap-1 overflow-x-auto rail md:flex-col">
          <li v-for="section in sections" :key="section.to" class="shrink-0">
            <NuxtLink
              :to="section.to"
              :aria-current="route.path === section.to ? 'page' : undefined"
              class="flex h-11 items-center gap-3 rounded-full px-4 text-[15px] transition md:rounded-btn"
              :class="route.path === section.to ? 'bg-ink font-bold text-canvas' : 'font-semibold text-ink-2 hover:bg-white/5 hover:text-ink'"
            >
              <svg class="size-[18px] shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path :d="section.icon" />
              </svg>
              {{ section.label }}
            </NuxtLink>
          </li>
        </ul>
      </nav>

      <div class="min-w-0 flex-1">
        <NuxtPage />
      </div>
    </div>
  </main>
</template>
