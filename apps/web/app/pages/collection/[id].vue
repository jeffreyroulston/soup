<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'

definePageMeta({ middleware: 'auth', layout: 'app' })

const route = useRoute()
const queries = useJellyfinQueries()
const packId = computed(() => String(route.params.id))
const collectionQuery = useQuery(computed(() => queries.curatedCollection(packId.value)))

const collection = computed(() => collectionQuery.data.value ?? null)
const loading = computed(() => collectionQuery.isPending.value)
const missing = computed(() => !loading.value && !collection.value)
</script>

<template>
  <main class="w-full pb-20 pt-24 sm:pt-28">
    <p v-if="missing" class="px-4 pt-32 font-semibold text-accent sm:px-8 lg:px-12">
      This collection isn’t available — not enough matching titles in your library, or it’s out of season.
    </p>

    <template v-else>
      <div class="flex flex-col gap-1.5 px-4 sm:px-8 lg:px-12">
        <h1 class="text-[clamp(2.5rem,5vw,4rem)] font-extrabold leading-none tracking-[-0.04em]">
          <template v-if="collection">{{ collection.title }}</template>
          <span v-else class="inline-block h-[0.8em] w-64 animate-pulse rounded-btn bg-surface align-middle" />
        </h1>
        <span v-if="collection" class="text-[15px] font-semibold text-muted">{{ collection.countLabel }}</span>
        <p v-if="collection?.description" class="max-w-[560px] text-base leading-relaxed text-ink-2">
          {{ collection.description }}
        </p>
      </div>

      <section
        v-if="loading || (collection && collection.items.length)"
        class="mt-8 grid grid-cols-2 gap-x-3 gap-y-6 px-4 sm:grid-cols-3 sm:px-8 md:grid-cols-4 lg:mx-12 lg:grid-cols-5 lg:px-0 xl:grid-cols-6"
        aria-label="Titles in this collection"
      >
        <template v-if="loading">
          <div v-for="n in 12" :key="n" class="aspect-[2/3] animate-pulse rounded-btn bg-elevated" />
        </template>
        <MediaCard v-for="item in collection?.items ?? []" v-else :key="item.id" :item="item" />
      </section>
    </template>
  </main>
</template>
