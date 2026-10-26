/** True when `NUXT_PUBLIC_MOCK=true` — browse UI without Identity or Jellyfin. */
export function isMockMode(): boolean {
  const value = useRuntimeConfig().public.mock as boolean | string
  return value === true || value === 'true'
}

