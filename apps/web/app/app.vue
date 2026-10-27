<script setup lang="ts">
const { jellyfin } = useAuthSession()

/**
 * Bumped when the active server changes. Clearing the cache alone leaves mounted queries
 * showing the old server's rows until something refetches; remounting starts every page
 * and the nav over, with skeletons, against the new server. Signing in from nothing
 * doesn't count, so the login page isn't torn down mid-sign-in.
 */
const serverGeneration = ref(0)
watch(
  () => (jellyfin.value ? `${jellyfin.value.serverId}:${jellyfin.value.userId}` : null),
  (next, previous) => {
    if (next && previous && next !== previous) serverGeneration.value++
  },
)
</script>

<template>
  <div class="min-h-screen bg-canvas text-ink">
    <NuxtLayout :key="serverGeneration">
      <NuxtPage />
    </NuxtLayout>
  </div>
</template>
