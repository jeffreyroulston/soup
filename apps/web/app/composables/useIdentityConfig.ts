/** Browser override for the Soup Identity base URL (Settings → Identity server). */
export const IDENTITY_OVERRIDE_KEY = 'soup.identity.baseUrl'

export type IdentitySource = 'override' | 'config' | 'build'

type IdentityState = {
  url: string
  source: IdentitySource
  /** Baked in by `NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL` at build time. */
  build: string
  /** From `soup.config.json` beside the deployed files, when it sets one. */
  file: string | null
}

export function normalizeIdentityUrl(input: string): string {
  let value = input.trim().replace(/\/+$/, '')
  if (value && !/^https?:\/\//i.test(value)) value = `https://${value}`
  return value
}

function readOverride(): string | null {
  try {
    const raw = localStorage.getItem(IDENTITY_OVERRIDE_KEY)
    return raw ? normalizeIdentityUrl(raw) || null : null
  }
  catch {
    return null
  }
}

function writeOverride(value: string | null) {
  try {
    if (value) localStorage.setItem(IDENTITY_OVERRIDE_KEY, value)
    else localStorage.removeItem(IDENTITY_OVERRIDE_KEY)
  }
  catch {
    // storage blocked
  }
}

/**
 * Resolves where the app talks to Identity, in priority order:
 * browser override → `soup.config.json` → build-time env. `useAuthSession`
 * reads the result through `useRuntimeConfig().public.soupIdentityBaseUrl`.
 */
export function useIdentityConfig() {
  const config = useRuntimeConfig()
  const state = useState<IdentityState>('soup-identity-config', () => ({
    url: String(config.public.soupIdentityBaseUrl),
    source: 'build',
    build: String(config.public.soupIdentityBaseUrl),
    file: null,
  }))

  function apply(url: string, source: IdentitySource) {
    config.public.soupIdentityBaseUrl = url
    state.value = { ...state.value, url, source }
  }

  function resolveDefault(): { url: string, source: IdentitySource } {
    return state.value.file
      ? { url: state.value.file, source: 'config' }
      : { url: state.value.build, source: 'build' }
  }

  /** Called once by the startup plugin with the build and config-file values. */
  function initialize(defaults: { build: string, file: string | null }) {
    state.value = { ...state.value, build: defaults.build, file: defaults.file }
    const override = readOverride()
    if (override) apply(override, 'override')
    else {
      const d = resolveDefault()
      apply(d.url, d.source)
    }
  }

  /** Persist a browser override; null clears it and returns to the deployment default. */
  function setOverride(input: string | null) {
    const value = input ? normalizeIdentityUrl(input) : ''
    writeOverride(value || null)
    if (value) apply(value, 'override')
    else {
      const d = resolveDefault()
      apply(d.url, d.source)
    }
  }

  return {
    url: computed(() => state.value.url),
    source: computed(() => state.value.source),
    defaultUrl: computed(() => resolveDefault().url),
    initialize,
    setOverride,
  }
}
