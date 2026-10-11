import {
  CURATED_PACKS,
  type CuratedPack,
  type CuratedPackEntry,
  type CuratedPackTheme,
} from '~/data/curatedPacks'
import type { JellyfinItem } from '~/types/jellyfin'

export type MatchedCuratedCollection = {
  pack: CuratedPack
  items: JellyfinItem[]
  /** Higher = better home candidate. */
  score: number
  seasonal: boolean
}

export type CuratedCollectionCard = {
  id: string
  title: string
  description: string
  itemCount: number
  countLabel: string
  theme: CuratedPackTheme
  to: string
  items: JellyfinItem[]
}

const HOME_LIMIT = 3

function normalizeTitle(value: string): string {
  return value
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function providerKey(kind: 'imdb' | 'tmdb', value: string): string {
  return `${kind}:${value.trim().toLowerCase()}`
}

function itemProviderKeys(item: JellyfinItem): string[] {
  const ids = item.providerIds
  if (!ids) return []
  const keys: string[] = []
  for (const [rawKey, rawValue] of Object.entries(ids)) {
    if (!rawValue) continue
    const key = rawKey.toLowerCase()
    if (key === 'imdb' || key === 'imdbid') keys.push(providerKey('imdb', rawValue))
    if (key === 'tmdb' || key === 'tmdbid') keys.push(providerKey('tmdb', rawValue))
  }
  return keys
}

function entryKeys(entry: CuratedPackEntry): string[] {
  const keys: string[] = []
  if (entry.imdb) keys.push(providerKey('imdb', entry.imdb))
  if (entry.tmdb) keys.push(providerKey('tmdb', entry.tmdb))
  return keys
}

function titleYearKey(name: string, year?: number | null): string {
  return `${normalizeTitle(name)}::${year ?? ''}`
}

/** True when `date` falls in the pack's seasonal window (supports wrap across New Year). */
export function isPackInSeason(pack: CuratedPack, date = new Date()): boolean {
  const season = pack.season
  if (!season) return true
  const month = date.getMonth() + 1
  const day = date.getDate()
  const value = month * 100 + day
  const start = season.startMonth * 100 + season.startDay
  const end = season.endMonth * 100 + season.endDay
  if (start <= end) return value >= start && value <= end
  return value >= start || value <= end
}

function matchEntry(
  entry: CuratedPackEntry,
  byProvider: Map<string, JellyfinItem>,
  byTitleYear: Map<string, JellyfinItem>,
): JellyfinItem | null {
  for (const key of entryKeys(entry)) {
    const hit = byProvider.get(key)
    if (hit) return hit
  }
  const exact = byTitleYear.get(titleYearKey(entry.name, entry.year))
  if (exact) return exact
  if (entry.year == null) {
    const loose = byTitleYear.get(titleYearKey(entry.name, null))
    if (loose) return loose
  }
  return null
}

function countLabel(items: JellyfinItem[]): string {
  const series = items.filter(item => item.type === 'Series').length
  const movies = items.length - series
  if (series && movies) return `${items.length} titles`
  if (series) return series === 1 ? '1 series' : `${series} series`
  return movies === 1 ? '1 film' : `${movies} films`
}

export function matchCuratedCollections(
  library: JellyfinItem[],
  opts: { now?: Date, homeLimit?: number } = {},
): { home: MatchedCuratedCollection[], all: MatchedCuratedCollection[] } {
  const now = opts.now ?? new Date()
  const byProvider = new Map<string, JellyfinItem>()
  const byTitleYear = new Map<string, JellyfinItem>()

  for (const item of library) {
    for (const key of itemProviderKeys(item)) {
      if (!byProvider.has(key)) byProvider.set(key, item)
    }
    byTitleYear.set(titleYearKey(item.name, item.productionYear), item)
    // Also index without year for loose fallback lookups from entries that omit year.
    const loose = titleYearKey(item.name, null)
    if (!byTitleYear.has(loose)) byTitleYear.set(loose, item)
  }

  const matched: MatchedCuratedCollection[] = []
  for (const pack of CURATED_PACKS) {
    const seasonal = Boolean(pack.season) && isPackInSeason(pack, now)
    if (pack.season && !seasonal) continue

    const seen = new Set<string>()
    const items: JellyfinItem[] = []
    for (const entry of pack.entries) {
      const hit = matchEntry(entry, byProvider, byTitleYear)
      if (!hit || seen.has(hit.id)) continue
      seen.add(hit.id)
      items.push(hit)
    }
    if (items.length < pack.minMatches) continue

    const waveBonus = pack.wave === 'a' ? 30 : pack.wave === 'b' ? 15 : 0
    const seasonBonus = pack.season ? 100 : 0
    const score = seasonBonus + waveBonus + items.length * 2
    matched.push({ pack, items, score, seasonal: Boolean(pack.season) })
  }

  matched.sort((a, b) => b.score - a.score || b.items.length - a.items.length)
  const limit = opts.homeLimit ?? HOME_LIMIT
  return { home: matched.slice(0, limit), all: matched }
}

export function toCuratedCard(match: MatchedCuratedCollection): CuratedCollectionCard {
  return {
    id: match.pack.id,
    title: match.pack.title,
    description: match.pack.description,
    itemCount: match.items.length,
    countLabel: countLabel(match.items),
    theme: match.pack.theme,
    to: `/collection/${match.pack.id}`,
    items: match.items,
  }
}

export function getCuratedPack(id: string): CuratedPack | null {
  return CURATED_PACKS.find(pack => pack.id === id) ?? null
}

export function matchCuratedPack(
  pack: CuratedPack,
  library: JellyfinItem[],
  now = new Date(),
): MatchedCuratedCollection | null {
  if (pack.season && !isPackInSeason(pack, now)) return null
  const { all } = matchCuratedCollections(library, { now, homeLimit: CURATED_PACKS.length })
  return all.find(entry => entry.pack.id === pack.id) ?? null
}
