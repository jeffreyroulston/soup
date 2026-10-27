<script setup lang="ts">
import { useQuery } from '@tanstack/vue-query'
import type { JellyfinItem } from '~/types/jellyfin'

definePageMeta({ middleware: 'auth', layout: 'app' })

const { imageUrl } = useJellyfin()
const queries = useJellyfinQueries()
const homeQuery = useQuery(queries.home())
/** Top Rated and the collection card: below the fold, so they don't hold up the first paint. */
const extrasQuery = useQuery(queries.homeExtras())
const collectionQuery = useQuery(queries.homeCollection())
const genresQuery = useQuery(queries.homeGenres())
const becauseQuery = useQuery(queries.homeBecauseYouWatched())

const home = computed(() => homeQuery.data.value ?? null)
const extras = computed(() => extrasQuery.data.value ?? null)
const collection = computed(() => collectionQuery.data.value ?? null)
const genres = computed(() => genresQuery.data.value ?? [])
const because = computed(() => becauseQuery.data.value ?? [])
const recentlyAdded = computed(() => home.value?.recentlyAdded ?? [])
const loading = computed(() => homeQuery.isPending.value)
const extrasLoading = computed(() => extrasQuery.isPending.value)
const collectionLoading = computed(() => collectionQuery.isPending.value)
const genresLoading = computed(() => genresQuery.isPending.value)
const becauseLoading = computed(() => becauseQuery.isPending.value)
/** Only when there's nothing to show; a failed background refresh keeps the cached rows. */
const loadError = computed(() => (home.value ? null : homeQuery.error.value))

const resumeIds = computed(() => new Set(home.value?.resume.map(item => item.id) ?? []))

const featured = computed<JellyfinItem[]>(() =>
  home.value ? pickHeroItems(home.value, item => !!imageUrl(item, 'Backdrop', 1920)) : [])

/** One collection, picked at random (stable for the day, like the other rotating rows). */
const featuredCollection = computed(() => dailyShuffle(collection.value?.curated ?? [], 'collection')[0] ?? null)

const upNext = computed(() => home.value?.keepWatching ?? [])

function upNextLead(item: JellyfinItem) {
  return resumeIds.value.has(item.id) ? 'Continue' : 'Next'
}

/** Films play straight from the row; episodes open their page first. */
function playsDirectly(item: JellyfinItem) {
  return item.type !== 'Episode' && isPlayable(item)
}

function upNextDetail(item: JellyfinItem) {
  const left = timeLeftLabel(item)
  if (item.type === 'Episode') return left ? `${item.name}, ${left}` : item.name
  return left ?? runtimeLabel(item.runTimeTicks)
}

</script>

<template>
  <main class="w-full pb-20">
    <ErrorState v-if="loadError" class="pt-32" :error="loadError" :on-retry="homeQuery.refetch" />
    <template v-else>
      <!-- Every row brings its own skeleton, so the layout is in place before the data -->
      <HeroCarousel v-if="loading || featured.length" :items="featured" :loading="loading" />
      <div v-else class="h-28" />

      <div class="flex flex-col gap-12">
        <MediaRow title="Keep Watching" :count="upNext.length" :loading="loading" wide>
          <template #default="{ slideClass }">
            <div v-for="item in upNext" :key="item.id" :class="slideClass">
              <MediaCard
                :item="item"
                variant="landscape"
                :kicker="upNextLead(item)"
                :detail="upNextDetail(item)"
                :to="playsDirectly(item) ? watchRoute(item) : undefined"
                :play="playsDirectly(item)"
                :favorite-button="false"
              />
            </div>
          </template>
        </MediaRow>

        <RecentlyAddedRow :shelves="recentlyAdded" :loading="loading" />
        <RankList title="Top Rated" :items="extras?.topRated" :loading="extrasLoading" />

        <ShelfRow v-if="becauseLoading" loading />
        <ShelfRow v-else-if="because[0]" :shelf="because[0]" />

        <CollectionSpotlight v-if="collectionLoading" loading />
        <CollectionSpotlight v-else-if="featuredCollection" :curated="featuredCollection" />
        <CollectionSpotlight v-else-if="collection?.spotlight" :spotlight="collection.spotlight" />

        <template v-if="genresLoading">
          <ShelfRow v-for="n in 2" :key="n" loading />
        </template>
        <ShelfRow v-for="shelf in genres.slice(0, 2)" v-else :key="shelf.title" :shelf="shelf" />

        <MediaRow
          title="Highly Rated, Not Yet Watched"
          :count="extras?.unwatchedTopRated.length ?? 0"
          :loading="extrasLoading"
        >
          <template #default="{ slideClass }">
            <div v-for="item in extras?.unwatchedTopRated ?? []" :key="item.id" :class="slideClass">
              <MediaCard :item="item" :favorite-button="false" />
            </div>
          </template>
        </MediaRow>

        <ShelfRow v-for="shelf in because.slice(1)" :key="shelf.title" :shelf="shelf" />
        <ShelfRow v-for="shelf in genres.slice(2)" :key="shelf.title" :shelf="shelf" />

        <p
          v-if="home && !upNext.length && !recentlyAdded.length"
          class="px-4 text-muted sm:px-8 lg:px-12"
        >
          Nothing here yet. Add some media to your Jellyfin libraries.
        </p>
      </div>
    </template>
  </main>
</template>
