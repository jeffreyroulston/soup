<script setup lang="ts">
import type { ServerEntry } from '~/composables/useServers'

const route = useRoute()
const auth = useAuthSession()
const { libraries, loaded: librariesLoaded } = useLibraries()

const scrolled = ref(false)
const menuOpen = ref(false)
const menuRef = ref<HTMLElement | null>(null)

const initial = computed(() => (auth.email.value || 'S').charAt(0).toUpperCase())
const mobileLibraries = computed(() => libraries.value.slice(0, 2))

watch(() => route.fullPath, () => {
  menuOpen.value = false
})

function onScroll() {
  scrolled.value = window.scrollY > 24
}

function onPointerDown(event: PointerEvent) {
  if (!menuOpen.value || !menuRef.value) return
  if (event.target instanceof Node && !menuRef.value.contains(event.target)) {
    menuOpen.value = false
  }
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') menuOpen.value = false
}

onMounted(() => {
  auth.loadServers().catch(() => {
    // The current server still works; the list just can't be offered.
  })
  onScroll()
  window.addEventListener('scroll', onScroll, { passive: true })
  window.addEventListener('pointerdown', onPointerDown, true)
  window.addEventListener('keydown', onKeydown)
})

onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScroll)
  window.removeEventListener('pointerdown', onPointerDown, true)
  window.removeEventListener('keydown', onKeydown)
})

function isActive(path: string) {
  if (path === '/') return route.path === '/'
  return route.path === path || route.path.startsWith(`${path}/`)
}

/** My Stuff opens on Favourites; its other tabs keep the nav item lit. */
const myStuffActive = computed(() => isActive('/favourites') || isActive('/history'))

const {
  entries: servers,
  currentKey,
  currentName: currentServerName,
  switchTo,
  switchingTo,
  switchError,
} = useServers()

async function switchServer(entry: ServerEntry) {
  if (await switchTo(entry)) {
    menuOpen.value = false
    await navigateTo('/')
  }
}

async function onLogout() {
  menuOpen.value = false
  await auth.logout()
  await navigateTo('/login')
}
</script>

<template>
  <header
    class="fixed inset-x-0 top-0 z-30 flex items-center justify-between gap-4 px-4 py-4 transition-colors duration-300 sm:px-8 lg:px-12 lg:py-5"
    :class="scrolled ? 'bg-canvas/75 backdrop-blur-xl' : 'bg-transparent'"
  >
    <NuxtLink to="/" class="text-[28px] leading-none text-ink">
      <SoupWordmark />
    </NuxtLink>

    <nav
      aria-label="Primary"
      class="glass absolute left-1/2 hidden max-w-[calc(100%-22rem)] -translate-x-1/2 gap-1 overflow-x-auto rounded-full p-[5px] rail md:flex"
    >
      <NuxtLink
        to="/"
        :aria-current="isActive('/') ? 'page' : undefined"
        class="inline-flex h-[38px] shrink-0 items-center rounded-full px-[18px] text-[15px] transition"
        :class="isActive('/') ? 'bg-ink font-bold text-canvas' : 'font-semibold text-ink-2 hover:text-ink'"
      >
        Home
      </NuxtLink>
      <template v-if="!librariesLoaded">
        <span v-for="n in 2" :key="n" aria-hidden="true" class="inline-flex h-[38px] shrink-0 items-center px-[18px]">
          <span class="h-3 w-14 animate-pulse rounded bg-white/10" />
        </span>
      </template>
      <NuxtLink
        v-for="lib in libraries"
        :key="lib.id"
        :to="`/library/${lib.id}`"
        :aria-current="isActive(`/library/${lib.id}`) ? 'page' : undefined"
        class="inline-flex h-[38px] shrink-0 items-center whitespace-nowrap rounded-full px-[18px] text-[15px] transition"
        :class="isActive(`/library/${lib.id}`) ? 'bg-ink font-bold text-canvas' : 'font-semibold text-ink-2 hover:text-ink'"
      >
        {{ lib.name }}
      </NuxtLink>
      <NuxtLink
        to="/favourites"
        :aria-current="myStuffActive ? 'page' : undefined"
        class="inline-flex h-[38px] shrink-0 items-center whitespace-nowrap rounded-full px-[18px] text-[15px] transition"
        :class="myStuffActive ? 'bg-ink font-bold text-canvas' : 'font-semibold text-ink-2 hover:text-ink'"
      >
        My Stuff
      </NuxtLink>
    </nav>

    <div class="flex items-center gap-2.5">
      <NuxtLink
        to="/search"
        aria-label="Search"
        class="hidden size-11 place-items-center rounded-full transition md:grid"
        :class="isActive('/search') ? 'bg-ink text-canvas' : 'glass text-ink'"
      >
        <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true">
          <circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" />
        </svg>
      </NuxtLink>

      <div ref="menuRef" class="relative">
        <button
          type="button"
          class="grid size-11 place-items-center rounded-full bg-accent text-lg font-extrabold text-canvas"
          aria-haspopup="menu"
          :aria-expanded="menuOpen"
          aria-label="Account menu"
          @click="menuOpen = !menuOpen"
        >
          {{ initial }}
        </button>
        <div
          v-if="menuOpen"
          role="menu"
          class="glass-strong absolute right-0 top-[calc(100%+10px)] w-64 rounded-[18px] p-2 shadow-[0_20px_40px_rgba(0,0,0,0.5)]"
        >
          <p class="truncate px-3 pb-2 pt-1.5 text-[13px] font-semibold text-muted">
            {{ auth.email.value || 'Signed in' }}
          </p>
          <template v-if="servers.length > 1">
            <div class="flex items-center justify-between px-3 pb-1 pt-1.5">
              <p class="text-[11px] font-extrabold uppercase tracking-[0.6px] text-muted">
                Server
              </p>
              <NuxtLink to="/settings/servers" role="menuitem" class="text-[12px] font-bold text-muted hover:text-ink">
                Manage
              </NuxtLink>
            </div>
            <button
              v-for="server in servers"
              :key="server.key"
              type="button"
              role="menuitemradio"
              :aria-checked="server.key === currentKey"
              :disabled="switchingTo !== null"
              class="flex h-11 w-full items-center gap-2.5 rounded-[10px] px-3 text-left text-[15px] font-semibold text-ink hover:bg-white/10 disabled:opacity-60"
              @click="switchServer(server)"
            >
              <span
                class="size-2 shrink-0 rounded-full"
                :class="server.key === currentKey ? 'bg-ok' : 'bg-white/15'"
              />
              <span class="min-w-0 flex-1 truncate">{{ server.name }}</span>
              <span
                v-if="switchingTo === server.key"
                class="size-4 shrink-0 animate-spin rounded-full border-2 border-ink/30 border-t-ink"
              />
            </button>
            <p v-if="switchError" role="alert" class="px-3 py-1.5 text-[13px] font-semibold text-accent">
              {{ switchError }}
            </p>
            <div class="mx-3 my-1.5 h-px bg-white/10" />
          </template>
          <template v-else-if="currentServerName">
            <p class="flex items-center gap-2.5 px-3 pb-2 text-[15px] font-semibold text-ink-2">
              <span class="size-2 shrink-0 rounded-full bg-ok" />
              <span class="min-w-0 truncate">{{ currentServerName }}</span>
            </p>
            <div class="mx-3 my-1.5 h-px bg-white/10" />
          </template>
          <NuxtLink
            to="/settings"
            role="menuitem"
            class="flex h-11 items-center rounded-[10px] px-3 text-[15px] font-semibold text-ink hover:bg-white/10"
          >
            Settings
          </NuxtLink>
          <button
            type="button"
            role="menuitem"
            class="flex h-11 w-full items-center rounded-[10px] px-3 text-left text-[15px] font-semibold text-ink hover:bg-white/10"
            @click="onLogout"
          >
            Sign out
          </button>
        </div>
      </div>
    </div>
  </header>

  <!-- Phone: floating glass tab bar -->
  <nav
    aria-label="Tabs"
    class="glass fixed inset-x-4 bottom-5 z-30 flex h-16 gap-1 rounded-[32px] p-1.5 md:hidden"
  >
    <NuxtLink
      to="/"
      :aria-current="isActive('/') ? 'page' : undefined"
      class="flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-[26px] text-[11px] font-bold"
      :class="isActive('/') ? 'bg-white/15 text-ink' : 'text-muted'"
    >
      <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z" />
      </svg>
      Home
    </NuxtLink>
    <!-- Hold the library tab slots until libraries load, so tabs don't resize -->
    <template v-if="!librariesLoaded">
      <span v-for="n in 2" :key="n" aria-hidden="true" class="flex min-w-0 flex-1 flex-col items-center justify-center gap-1.5">
        <span class="size-5 animate-pulse rounded-md bg-white/10" />
        <span class="h-2 w-10 animate-pulse rounded bg-white/10" />
      </span>
    </template>
    <NuxtLink
      v-for="lib in mobileLibraries"
      :key="lib.id"
      :to="`/library/${lib.id}`"
      :aria-current="isActive(`/library/${lib.id}`) ? 'page' : undefined"
      class="flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-[26px] text-[11px] font-bold"
      :class="isActive(`/library/${lib.id}`) ? 'bg-white/15 text-ink' : 'text-muted'"
    >
      <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M4 4h16v16H4zM8 4v16M16 4v16" />
      </svg>
      <span class="max-w-full truncate px-1">{{ lib.name }}</span>
    </NuxtLink>
    <NuxtLink
      to="/favourites"
      :aria-current="myStuffActive ? 'page' : undefined"
      class="flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-[26px] text-[11px] font-bold"
      :class="myStuffActive ? 'bg-white/15 text-ink' : 'text-muted'"
    >
      <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" aria-hidden="true">
        <path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" />
      </svg>
      My Stuff
    </NuxtLink>
    <NuxtLink
      to="/search"
      :aria-current="isActive('/search') ? 'page' : undefined"
      class="flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-[26px] text-[11px] font-bold"
      :class="isActive('/search') ? 'bg-white/15 text-ink' : 'text-muted'"
    >
      <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true">
        <circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" />
      </svg>
      Search
    </NuxtLink>
  </nav>
</template>
