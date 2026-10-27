<script setup lang="ts">
/** "Explore" title and its section tabs, in My Stuff's style. */
const route = useRoute()

const TABS = [
  { to: '/explore', label: 'Discover' },
  { to: '/explore/requests', label: 'Requests' },
]

function isCurrent(to: string) {
  return route.path.replace(/\/$/, '') === to
}
</script>

<template>
  <div class="flex flex-col gap-3 px-4 sm:gap-[18px] sm:px-8 lg:px-12">
    <div class="flex flex-wrap items-end justify-between gap-x-6 gap-y-2">
      <h1 class="text-[40px] font-extrabold leading-none tracking-[-1.5px] sm:text-[64px] sm:tracking-[-2.5px]">
        Explore
      </h1>
      <slot name="aside" />
    </div>
    <nav aria-label="Explore" class="flex gap-1 rounded-full bg-surface p-1 sm:gap-7 sm:rounded-none sm:border-b sm:border-white/15 sm:bg-transparent sm:p-0">
      <NuxtLink
        v-for="tab in TABS"
        :key="tab.to"
        :to="tab.to"
        :aria-current="isCurrent(tab.to) ? 'page' : undefined"
        class="grid h-9 flex-1 place-items-center rounded-full text-sm transition sm:-mb-px sm:block sm:h-auto sm:flex-none sm:rounded-none sm:border-b-[3px] sm:pb-3.5 sm:pt-2.5 sm:text-[17px]"
        :class="isCurrent(tab.to)
          ? 'bg-ink font-extrabold text-canvas sm:border-accent sm:bg-transparent sm:text-ink'
          : 'font-bold text-muted hover:text-ink sm:border-transparent'"
      >
        {{ tab.label }}
      </NuxtLink>
    </nav>
  </div>
</template>
