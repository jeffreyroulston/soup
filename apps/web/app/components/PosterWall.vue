<script setup lang="ts">
// Signed-out backdrop: a tilted wall of placeholder movie posters (no Jellyfin
// images are reachable before sign-in). Each row drifts slowly, alternating direction.
// Posters are public-domain scans from Wikimedia Commons, served from public/posters.
// Prefixed with the app base URL so sub-path hosting (e.g. /soup/) still finds them.
const baseURL = useRuntimeConfig().app.baseURL.replace(/\/$/, '')
const POSTERS = [
  'metropolis',
  'caligari',
  'the-general',
  'the-kid',
  'night-of-the-living-dead',
  'charade',
  'phantom-of-the-opera',
  'safety-last',
  'gold-rush',
  'sunrise',
  'his-girl-friday',
].map(name => `${baseURL}/posters/${name}.jpg`)
const ROW_COUNT = 6
const TILES_PER_ROW = 12
const rows = Array.from({ length: ROW_COUNT }, (_, r) => {
  const tiles = Array.from({ length: TILES_PER_ROW }, (_, i) => POSTERS[(r * 3 + i * 5) % POSTERS.length])
  // Tiles are rendered twice so translating by -50% loops seamlessly.
  return { tiles: [...tiles, ...tiles], reverse: r % 2 === 1, duration: 90 + (r % 3) * 15 }
})
</script>

<template>
  <div aria-hidden="true" class="pointer-events-none absolute inset-0 overflow-hidden">
    <div class="absolute -inset-16 flex -rotate-6 flex-col gap-4 opacity-25">
      <div
        v-for="(row, r) in rows"
        :key="r"
        class="poster-row flex w-max gap-4"
        :class="{ 'poster-row--reverse': row.reverse }"
        :style="{ animationDuration: `${row.duration}s` }"
      >
        <img
          v-for="(poster, i) in row.tiles"
          :key="i"
          :src="poster"
          alt=""
          draggable="false"
          class="aspect-[2/3] w-28 shrink-0 rounded-card object-cover sm:w-36 lg:w-44"
        >
      </div>
    </div>
    <div class="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(10,10,11,0.4)_0%,#0A0A0B_80%)]" />
  </div>
</template>

<style scoped>
.poster-row {
  /* gap-4 between the two copies keeps the loop seam spacing consistent */
  padding-right: 1rem;
  animation: poster-marquee linear infinite;
}

.poster-row--reverse {
  animation-direction: reverse;
}

@keyframes poster-marquee {
  from {
    transform: translateX(0);
  }
  to {
    transform: translateX(-50%);
  }
}

@media (prefers-reduced-motion: reduce) {
  .poster-row {
    animation: none;
  }
}
</style>
