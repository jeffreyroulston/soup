<script setup lang="ts">
import type { DeviceUserEntry } from '~/composables/useDeviceUsers'

definePageMeta({ middleware: 'auth', layout: false })
useHead({ title: 'Who\'s watching?' })

const auth = useAuthSession()
const { users, currentKey, switchTo, switchingTo, switchError } = useDeviceUsers()

/** Told apart at a glance when there's no picture; dark enough for a white initial. */
const TILE_COLORS = ['#b4530c', '#2f5d8c', '#3a7259', '#6d4a8c', '#9c3f3a', '#6b6b70']

function tileColor(key: string): string {
  let hash = 0
  for (const char of key) hash = (hash * 31 + char.charCodeAt(0)) >>> 0
  return TILE_COLORS[hash % TILE_COLORS.length]!
}

/** Pictures that failed to load, since most Jellyfin users don't have one. */
const noImage = ref(new Set<string>())

function showsImage(user: DeviceUserEntry): boolean {
  return Boolean(user.imageUrl) && !noImage.value.has(user.key)
}

async function pick(key: string) {
  // Picking whoever's already active just carries on as them.
  if (key !== currentKey.value && !await switchTo(key)) return
  await navigateTo(auth.jellyfin.value ? '/' : '/login', { replace: true })
}

// A failed switch can drop that user; with nobody left, there's only signing in.
watch(() => users.value.length, (count) => {
  if (!count && !auth.jellyfin.value) void navigateTo('/login', { replace: true })
})
</script>

<template>
  <main class="flex min-h-screen flex-col items-center justify-center gap-10 px-6 py-16 sm:gap-14">
    <div class="flex flex-col items-center gap-6 sm:gap-8">
      <span class="text-[44px] leading-none text-ink sm:text-[56px]">
        <SoupWordmark />
      </span>
      <h1 class="text-center text-[34px] font-extrabold leading-[1.05] tracking-[-0.04em] sm:text-[52px]">
        Who's watching?
      </h1>
    </div>

    <ul class="flex max-w-[1040px] flex-wrap justify-center gap-x-5 gap-y-8 sm:gap-x-8 sm:gap-y-10">
      <li v-for="user in users" :key="user.key">
        <button
          type="button"
          :disabled="switchingTo !== null"
          :title="user.name"
          class="group flex w-[132px] flex-col items-center gap-3 rounded-panel text-center transition-opacity sm:w-[172px]"
          :class="switchingTo !== null && switchingTo !== user.key ? 'opacity-40' : ''"
          @click="pick(user.key)"
        >
          <span
            class="relative grid aspect-square w-full place-items-center overflow-hidden rounded-panel text-[56px] font-extrabold text-white ring-[3px] ring-transparent transition group-enabled:group-hover:scale-[1.04] group-enabled:group-hover:ring-ink sm:text-[72px]"
            :style="{ backgroundColor: tileColor(user.key) }"
          >
            {{ user.shortName.charAt(0).toUpperCase() }}
            <img
              v-if="showsImage(user)"
              :src="user.imageUrl!"
              alt=""
              class="absolute inset-0 size-full object-cover"
              @error="noImage.add(user.key)"
            >
            <span v-if="switchingTo === user.key" class="absolute inset-0 grid place-items-center bg-canvas/60">
              <span class="size-9 animate-spin rounded-full border-[3px] border-white/30 border-t-white" />
            </span>
          </span>
          <span class="flex w-full min-w-0 flex-col gap-0.5">
            <span class="truncate text-[17px] font-bold text-ink-2 transition-colors group-enabled:group-hover:text-ink sm:text-xl">
              {{ user.shortName }}
            </span>
            <span
              class="truncate text-[13px] font-semibold"
              :class="user.key === currentKey ? 'text-ok' : 'text-muted'"
            >
              {{ user.key === currentKey ? 'Watching now' : user.detail }}
            </span>
          </span>
        </button>
      </li>
      <li>
        <NuxtLink
          to="/login?add=user&from=users"
          class="group flex w-[132px] flex-col items-center gap-3 rounded-panel text-center sm:w-[172px]"
          :class="switchingTo !== null ? 'pointer-events-none opacity-40' : ''"
        >
          <span class="grid aspect-square w-full place-items-center rounded-panel bg-surface text-muted ring-[3px] ring-transparent transition group-hover:scale-[1.04] group-hover:text-ink group-hover:ring-ink">
            <svg viewBox="0 0 24 24" class="size-14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
              <path d="M12 5v14M5 12h14" />
            </svg>
          </span>
          <span class="truncate text-[17px] font-bold text-muted transition-colors group-hover:text-ink sm:text-xl">
            Add user
          </span>
        </NuxtLink>
      </li>
    </ul>

    <p v-if="switchError" role="alert" class="max-w-md text-center text-sm font-semibold text-accent">
      {{ switchError }}
    </p>
  </main>
</template>
