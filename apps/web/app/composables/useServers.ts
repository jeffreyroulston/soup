import { serverHost } from '~/utils/soupExchange'

/** Per-browser server list tweaks, keyed by `ServerEntry.key`. */
type ServerPrefs = {
  /** Keys in the user's order; servers not listed follow, Soup first. */
  order: string[]
  nicknames: Record<string, string>
}

const PREFS_KEY = 'soup.servers.prefs'

function loadPrefs(): ServerPrefs {
  try {
    const saved = JSON.parse(localStorage.getItem(PREFS_KEY) ?? '{}') as Partial<ServerPrefs>
    return { order: saved.order ?? [], nicknames: saved.nicknames ?? {} }
  }
  catch {
    return { order: [], nicknames: {} }
  }
}

/** One switchable server, from the Soup roster or added directly. */
export type ServerEntry = {
  /** `soup:<roster id>` or `direct:<saved id>`. */
  key: string
  kind: 'soup' | 'direct'
  /** Roster id or saved-server id, whichever `kind` switches by. */
  id: string
  /** Nickname when set, else the server's own name. */
  name: string
  /** Name from the roster or Jellyfin, before any nickname. */
  originalName: string
  host: string
  /** Jellyfin username, for directly added servers. */
  username?: string
}

/** Roster and directly added servers as one list, with the active one and a way to switch. */
export function useServers() {
  const auth = useAuthSession()
  const switchingTo = ref<string | null>(null)
  const switchError = ref('')
  const prefs = useState<ServerPrefs>('server-prefs', loadPrefs)

  function savePrefs(next: ServerPrefs) {
    prefs.value = next
    try {
      localStorage.setItem(PREFS_KEY, JSON.stringify(next))
    }
    catch {
      // Private mode or full storage: the change still applies for this visit.
    }
  }

  const entries = computed<ServerEntry[]>(() => {
    const { order, nicknames } = prefs.value
    const all = [
      ...auth.servers.value.map(server => ({
        key: `soup:${server.id}`,
        kind: 'soup' as const,
        id: server.id,
        originalName: server.name,
        host: serverHost(server),
      })),
      ...auth.savedServers.value.map(server => ({
        key: `direct:${server.id}`,
        kind: 'direct' as const,
        id: server.id,
        originalName: server.name,
        host: new URL(server.baseUrl).host,
        username: server.username,
      })),
    ].map(entry => ({ ...entry, name: nicknames[entry.key] || entry.originalName }))
    const rank = (key: string) => {
      const index = order.indexOf(key)
      return index === -1 ? order.length : index
    }
    // Array sort is stable, so unranked servers keep their natural order.
    return all.sort((a, b) => rank(a.key) - rank(b.key))
  })

  /** Sets or, when blank, clears a server's nickname. */
  function rename(key: string, nickname: string) {
    const nicknames = { ...prefs.value.nicknames }
    const trimmed = nickname.trim()
    if (trimmed) nicknames[key] = trimmed
    else delete nicknames[key]
    savePrefs({ ...prefs.value, nicknames })
  }

  /** Moves a server `delta` places up (negative) or down the list. */
  function move(key: string, delta: number) {
    const keys = entries.value.map(entry => entry.key)
    const from = keys.indexOf(key)
    const to = from + delta
    if (from === -1 || to < 0 || to >= keys.length) return
    keys.splice(to, 0, ...keys.splice(from, 1))
    savePrefs({ ...prefs.value, order: keys })
  }

  const currentKey = computed(() => {
    const session = auth.jellyfin.value
    if (!session) return null
    if (session.direct) return `direct:${session.serverId}:${session.userId}`
    // Sessions from before the picker don't carry the roster id, so match those by address.
    const host = new URL(session.baseUrl).host
    const id = session.soupServerId ?? auth.servers.value.find(server => serverHost(server) === host)?.id
    return id ? `soup:${id}` : null
  })

  /** Roster name first; otherwise Jellyfin's own name, then the address. */
  const currentName = computed(() => entries.value.find(entry => entry.key === currentKey.value)?.name
    ?? auth.jellyfin.value?.serverName
    ?? (auth.jellyfin.value ? new URL(auth.jellyfin.value.baseUrl).host : ''))

  /** True once switched; errors land in `switchError`. */
  async function switchTo(entry: ServerEntry): Promise<boolean> {
    if (switchingTo.value || entry.key === currentKey.value) return false
    switchingTo.value = entry.key
    switchError.value = ''
    try {
      if (entry.kind === 'soup') await auth.selectServer(entry.id)
      else await auth.switchToSaved(entry.id)
      return true
    }
    catch (error) {
      switchError.value = error instanceof Error ? error.message : 'Could not switch servers'
      if (!auth.jellyfin.value) await navigateTo('/login')
      return false
    }
    finally {
      switchingTo.value = null
    }
  }

  return { entries, currentKey, currentName, switchTo, switchingTo, switchError, rename, move }
}
