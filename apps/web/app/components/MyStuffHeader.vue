<script setup lang="ts">
/** "My Stuff" title and its section tabs: underlined on desktop, a segmented pill on phones. */
const route = useRoute()

const TABS = [
  { to: '/favourites', label: 'Favourites' },
  { to: '/history', label: 'History' },
]
</script>

<template>
  <div class="flex flex-col gap-3 px-4 sm:gap-[18px] sm:px-8 lg:px-12">
    <h1 class="text-[40px] font-extrabold leading-none tracking-[-1.5px] sm:text-[64px] sm:tracking-[-2.5px]">
      My Stuff
    </h1>
    <nav aria-label="My Stuff" class="flex gap-1 rounded-full bg-surface p-1 sm:gap-7 sm:rounded-none sm:border-b sm:border-white/15 sm:bg-transparent sm:p-0">
      <NuxtLink
        v-for="tab in TABS"
        :key="tab.to"
        :to="tab.to"
        :aria-current="route.path === tab.to ? 'page' : undefined"
        class="grid h-9 flex-1 place-items-center rounded-full text-sm transition sm:-mb-px sm:block sm:h-auto sm:flex-none sm:rounded-none sm:border-b-[3px] sm:pb-3.5 sm:pt-2.5 sm:text-[17px]"
        :class="route.path === tab.to
          ? 'bg-ink font-extrabold text-canvas sm:border-accent sm:bg-transparent sm:text-ink'
          : 'font-bold text-muted hover:text-ink sm:border-transparent'"
      >
        {{ tab.label }}
      </NuxtLink>
    </nav>
  </div>
</template>
