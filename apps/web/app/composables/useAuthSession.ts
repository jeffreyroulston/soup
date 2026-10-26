import type { AuthSessionResponse, JellyfinSessionPayload } from '~/types/jellyfin'
import { MOCK_EMAIL, MOCK_SESSION } from '~/utils/mockCatalog'
import { isMockMode } from '~/utils/mockMode'
import { exchangeForJellyfin, fetchServers, pickServer } from '~/utils/soupExchange'
import {
  fetchRoster,
  googleSignInUrl,
  IdentityError,
  pollDeviceLink,
  refreshSoupSession,
  revokeSoupSession,
  startDeviceLink,
  type RosterServer,
} from '~/utils/soupIdentity'

/** This tab's Jellyfin token from a Soup sign-in; other tabs mint their own from the Soup tokens. */
const STORAGE_KEY = 'soup.jellyfin.session'
/** Direct Jellyfin sign-ins have no Soup tokens to restore from, so they persist across tabs. */
const DIRECT_KEY = 'soup.jellyfin.direct'
const DEVICE_KEY = 'soup.jellyfin.deviceId'
/** Soup Identity session, shared by every tab in this browser. */
const TOKENS_KEY = 'soup.identity.tokens'
export const LAST_SERVER_KEY = 'soup.jellyfin.lastServer'
/** Roster id of the Soup server this browser last signed in to. */
const PREFERRED_SERVER_KEY = 'soup.server.preferred'
/** Jellyfin servers added with a username and password, each with its own token. */
const SAVED_KEY = 'soup.servers.direct'

/** A server signed in to directly, kept so the user can switch back without signing in again. */
export type SavedServer = {
  /** `serverId:userId`, so two accounts on one server are separate entries. */
  id: string
  name: string
  baseUrl: string
  serverId: string
  userId: string
  username: string
  accessToken: string
  deviceId: string
  addedAt: number
}

type SoupTokens = {
  accessToken: string
  refreshToken: string
  email: string
  /** Unix seconds. */
  expiresAt: number
}

type DeviceLinkState = {
  deviceCode: string
  userCode: string
  interval: number
  expiresAt: number
}

/** The sign-in this tab is polling for; the login page owns its lifetime. */
let deviceLink: DeviceLinkState | null = null
/** One re-exchange at a time, however many requests hit a 401 together. */
let reexchanging: Promise<AuthSessionResponse> | null = null

function readLocal(key: string): string | null {
  try {
    return localStorage.getItem(key)
  }
  catch {
    return null
  }
}

function writeLocal(key: string, value: string | null) {
  try {
    if (value == null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  }
  catch {
    // storage blocked
  }
}

function readTokens(): SoupTokens | null {
  const raw = readLocal(TOKENS_KEY)
  if (!raw) return null
  try {
    const saved = JSON.parse(raw) as SoupTokens
    return saved.refreshToken ? saved : null
  }
  catch {
    writeLocal(TOKENS_KEY, null)
    return null
  }
}

function writeTokens(tokens: SoupTokens | null) {
  writeLocal(TOKENS_KEY, tokens && JSON.stringify(tokens))
}

function readSaved(): SavedServer[] {
  const raw = readLocal(SAVED_KEY)
  if (!raw) return []
  try {
    const saved = JSON.parse(raw) as SavedServer[]
    return Array.isArray(saved) ? saved.filter(server => server.accessToken && server.baseUrl) : []
  }
  catch {
    writeLocal(SAVED_KEY, null)
    return []
  }
}

/** Jellyfin's own name for the server, else its host. */
async function fetchServerName(baseUrl: string): Promise<string> {
  try {
    const response = await fetch(`${baseUrl}/System/Info/Public`, { headers: { Accept: 'application/json' } })
    const info = await response.json() as { ServerName?: string }
    if (info.ServerName) return info.ServerName
  }
  catch {
    // Signed in fine, so the name is only cosmetic.
  }
  return new URL(baseUrl).host
}

/** Identity rejected the tokens themselves, as opposed to being unreachable. */
function isRejected(error: unknown): boolean {
  return error instanceof IdentityError && (error.status === 400 || error.status === 401)
}

/**
 * Identity rotates refresh tokens, so two tabs refreshing at once would sign each other out.
 * A Web Lock makes the second tab wait and pick up the first one's result.
 */
function withRefreshLock<T>(fn: () => Promise<T>): Promise<T> {
  if (typeof navigator !== 'undefined' && navigator.locks) {
    return navigator.locks.request('soup.identity.refresh', fn) as Promise<T>
  }
  return fn()
}

/** Stored Soup tokens, refreshed when within a minute of expiry; null when signed out. */
async function freshTokens(identityBaseUrl: string): Promise<SoupTokens | null> {
  const skewMs = 60_000
  const isFresh = (tokens: SoupTokens) => tokens.expiresAt * 1000 > Date.now() + skewMs
  const current = readTokens()
  if (!current || isFresh(current)) return current
  return withRefreshLock(async () => {
    const latest = readTokens()
    if (!latest || isFresh(latest)) return latest
    try {
      const refreshed = await refreshSoupSession(identityBaseUrl, latest.refreshToken)
      const next: SoupTokens = {
        accessToken: refreshed.access_token,
        refreshToken: refreshed.refresh_token,
        email: refreshed.email || latest.email,
        expiresAt: Math.floor(Date.now() / 1000) + (refreshed.expires_in || 3600),
      }
      writeTokens(next)
      return next
    }
    catch (error) {
      if (!isRejected(error)) throw error
      writeTokens(null)
      return null
    }
  })
}

/** `crypto.randomUUID` needs a secure context; plain-http LAN hosting still has `getRandomValues`. */
function randomUUID(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  bytes[6] = (bytes[6]! & 0x0f) | 0x40
  bytes[8] = (bytes[8]! & 0x3f) | 0x80
  const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

/** One Jellyfin device per browser, whether signed in through Soup or directly. */
function webDeviceId(): string {
  let id = readLocal(DEVICE_KEY)
  if (!id) {
    id = randomUUID()
    writeLocal(DEVICE_KEY, id)
  }
  return id
}

export function normalizeServerUrl(input: string): string {
  let value = input.trim().replace(/\/+$/, '')
  if (!value) return value
  if (!/^https?:\/\//i.test(value)) value = `http://${value}`
  return value
}

export function useAuthSession() {
  const nuxtApp = useNuxtApp()
  const identityBaseUrl = String(useRuntimeConfig().public.soupIdentityBaseUrl).replace(/\/$/, '')
  const email = useState<string | null>('soup-email', () => null)
  const jellyfin = useState<JellyfinSessionPayload | null>('soup-jellyfin', () => null)
  const ready = useState('soup-auth-ready', () => false)
  const loading = useState('soup-auth-loading', () => false)
  const mockDismissed = useState('soup-mock-dismissed', () => false)
  /** Servers on the Soup roster, from the last exchange. */
  const servers = useState<RosterServer[]>('soup-servers', () => [])
  /** Signed in to Soup but not to a server yet; the login page shows the server picker. */
  const choosingServer = useState('soup-choosing-server', () => false)
  /** Why the last server couldn't be signed in to, shown with the picker. */
  const serverError = useState<string | null>('soup-server-error', () => null)
  /** Servers added directly, in the order they were added. */
  const savedServers = useState<SavedServer[]>('soup-saved-servers', readSaved)
  /** The Soup account, which can differ from `email` while a direct server is active. */
  const soupEmail = useState<string | null>('soup-account-email', () => readTokens()?.email ?? null)

  function writeSaved(next: SavedServer[]) {
    savedServers.value = next
    writeLocal(SAVED_KEY, next.length ? JSON.stringify(next) : null)
  }

  function upsertSaved(server: SavedServer) {
    const exists = savedServers.value.some(entry => entry.id === server.id)
    // Signing in again keeps the server's place in the list.
    writeSaved(exists
      ? savedServers.value.map(entry => (entry.id === server.id ? server : entry))
      : [...savedServers.value, server])
  }

  /** The saved entry for the active direct session, if any. */
  function activeSavedId(): string | null {
    const session = jellyfin.value
    return session?.direct ? `${session.serverId}:${session.userId}` : null
  }

  function persistJellyfin(session: JellyfinSessionPayload | null) {
    jellyfin.value = session
    if (!import.meta.client) return
    if (session && !session.direct) {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ email: email.value, jellyfin: session }))
    }
    else {
      sessionStorage.removeItem(STORAGE_KEY)
    }
    if (session?.direct) {
      writeLocal(DIRECT_KEY, JSON.stringify({ email: email.value, jellyfin: session }))
    }
    else {
      writeLocal(DIRECT_KEY, null)
    }
  }

  /** This tab's Soup session from an earlier load; true when one was restored. */
  function restoreFromStorage(): boolean {
    if (!import.meta.client) return false
    // Signed out in another tab: don't keep browsing on the leftover Jellyfin token.
    if (!readTokens()) return false
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return false
    try {
      const saved = JSON.parse(raw) as Partial<AuthSessionResponse>
      if (!saved.jellyfin?.accessToken) return false
      email.value = saved.email ?? null
      jellyfin.value = saved.jellyfin
      return true
    }
    catch {
      sessionStorage.removeItem(STORAGE_KEY)
      return false
    }
  }

  function restoreDirect(): boolean {
    const raw = readLocal(DIRECT_KEY)
    if (!raw) return false
    try {
      const saved = JSON.parse(raw) as AuthSessionResponse
      if (!saved.jellyfin?.direct) return false
      email.value = saved.email
      jellyfin.value = saved.jellyfin
      // Direct sessions from before saved servers existed.
      const { baseUrl, serverId, userId, accessToken, deviceId } = saved.jellyfin
      if (!savedServers.value.some(server => server.id === `${serverId}:${userId}`)) {
        upsertSaved({
          id: `${serverId}:${userId}`,
          name: saved.jellyfin.serverName ?? new URL(baseUrl).host,
          baseUrl,
          serverId,
          userId,
          username: saved.email,
          accessToken,
          deviceId,
          addedAt: Date.now(),
        })
      }
      return true
    }
    catch {
      writeLocal(DIRECT_KEY, null)
      return false
    }
  }

  async function applySession(payload: AuthSessionResponse) {
    email.value = payload.email
    persistJellyfin(payload.jellyfin)
  }

  /**
   * A new Jellyfin token from the stored Soup tokens for `serverId`, else the preferred or only
   * server. Null when there is no usable Soup session; `jellyfin: null` when the user has to choose.
   */
  async function exchangeSoup(serverId?: string): Promise<AuthSessionResponse | null> {
    const tokens = await freshTokens(identityBaseUrl)
    soupEmail.value = tokens?.email ?? null
    if (!tokens) return null
    try {
      const roster = await fetchServers(identityBaseUrl, tokens.accessToken)
      servers.value = roster
      const server = pickServer(roster, serverId ?? readLocal(PREFERRED_SERVER_KEY))
      if (!server) return { email: tokens.email, jellyfin: null }
      const session = await exchangeForJellyfin(identityBaseUrl, tokens.accessToken, webDeviceId(), server)
      writeLocal(PREFERRED_SERVER_KEY, server.id)
      return { email: tokens.email, jellyfin: session }
    }
    catch (error) {
      if (!(error instanceof IdentityError && error.status === 401)) throw error
      writeTokens(null)
      return null
    }
  }

  /** Signed in to a server, or to Soup alone with the picker up when `jellyfin` is null. */
  async function applySoup(payload: AuthSessionResponse) {
    choosingServer.value = !payload.jellyfin
    serverError.value = null
    await applySession(payload)
  }

  /**
   * After a failed exchange with a known roster, stays signed in to Soup and offers the
   * servers so the user can retry or pick another. False when there's nothing to offer.
   */
  function offerServers(error: unknown): boolean {
    const tokens = readTokens()
    if (!tokens || !servers.value.length) return false
    email.value = tokens.email
    persistJellyfin(null)
    choosingServer.value = true
    serverError.value = error instanceof Error ? error.message : 'Could not sign in to that server'
    return true
  }

  async function applyMockSession() {
    mockDismissed.value = false
    await applySession({ email: MOCK_EMAIL, jellyfin: MOCK_SESSION })
  }

  async function hydrate() {
    if (loading.value) return
    loading.value = true
    try {
      if (isMockMode()) {
        if (!mockDismissed.value) await applyMockSession()
        return
      }
      if (restoreDirect()) return
      // A reload in the same tab reuses its token instead of minting a new one through
      // Identity (three round trips). If it has expired, the first 401 re-exchanges it.
      if (restoreFromStorage()) return
      const payload = await exchangeSoup()
      if (payload) {
        await applySoup(payload)
      }
      else {
        email.value = null
        persistJellyfin(null)
      }
    }
    catch (error) {
      // Identity or Jellyfin unreachable. The Soup tokens stay, so the next load can retry.
      if (!offerServers(error)) {
        email.value = null
        persistJellyfin(null)
      }
    }
    finally {
      ready.value = true
      loading.value = false
    }
  }

  async function startLogin() {
    if (isMockMode()) {
      await applyMockSession()
      return {
        userCode: 'MOCK-0001',
        verificationUrl: '/login',
        googleUrl: '/login',
        interval: 1,
        expiresIn: 600,
      }
    }
    const started = await startDeviceLink(identityBaseUrl)
    const interval = started.interval || 5
    deviceLink = {
      deviceCode: started.device_code,
      userCode: started.user_code,
      interval,
      expiresAt: Math.floor(Date.now() / 1000) + (started.expires_in || 900),
    }
    return {
      userCode: started.user_code,
      verificationUrl: started.verification_uri_complete || started.verification_uri,
      googleUrl: googleSignInUrl(identityBaseUrl, started.user_code),
      interval,
      expiresIn: started.expires_in,
    }
  }

  /**
   * Polls the device link. With `keepCurrent` and a server already active (Settings connecting
   * a Soup account), approval only stores the Soup tokens and roster and returns `linked`.
   */
  async function pollLogin(options: { keepCurrent?: boolean } = {}) {
    if (isMockMode()) {
      await applyMockSession()
      return {
        status: 'approved' as const,
        email: MOCK_EMAIL,
        jellyfin: MOCK_SESSION,
      }
    }
    const state = deviceLink
    if (!state) throw new Error('No sign-in in progress')
    if (state.expiresAt * 1000 < Date.now()) {
      deviceLink = null
      return { status: 'expired' as const }
    }
    const poll = await pollDeviceLink(identityBaseUrl, state.deviceCode)
    if (poll.status === 'pending') {
      return { status: 'pending' as const, userCode: state.userCode, interval: state.interval }
    }
    deviceLink = null
    if (poll.status === 'expired') return { status: 'expired' as const }

    const tokens: SoupTokens = {
      accessToken: poll.access_token,
      refreshToken: poll.refresh_token,
      email: poll.email,
      expiresAt: Math.floor(Date.now() / 1000) + (poll.expires_in || 3600),
    }
    writeTokens(tokens)
    soupEmail.value = tokens.email
    if (options.keepCurrent && jellyfin.value) {
      try {
        servers.value = await fetchRoster(identityBaseUrl, tokens.accessToken)
      }
      catch {
        // Linked either way; Settings can refresh the roster.
      }
      return { status: 'linked' as const }
    }
    let payload: AuthSessionResponse | null
    try {
      payload = await exchangeSoup()
    }
    catch (error) {
      if (offerServers(error)) return { status: 'chooseServer' as const }
      throw error
    }
    if (!payload) throw new Error('Soup rejected the sign-in. Try again.')
    await applySoup(payload)
    if (!payload.jellyfin) return { status: 'chooseServer' as const }
    return { status: 'approved' as const, email: tokens.email, jellyfin: payload.jellyfin }
  }

  /** Signs in to another server on the roster and remembers it for this browser. */
  async function selectServer(serverId: string) {
    const payload = await exchangeSoup(serverId)
    if (!payload) {
      email.value = null
      persistJellyfin(null)
      choosingServer.value = false
      throw new Error('Your Soup session expired. Sign in again.')
    }
    if (payload.jellyfin?.soupServerId !== serverId) {
      throw new Error('That server is no longer on your roster')
    }
    // Cached rows, items and progress all belong to the previous server.
    nuxtApp.$queryClient.clear()
    await applySoup(payload)
  }

  /** The roster, fetched when this tab restored its session without an exchange; `force` refetches. */
  async function loadServers(force = false): Promise<RosterServer[]> {
    if ((servers.value.length && !force) || isMockMode()) return servers.value
    const tokens = await freshTokens(identityBaseUrl)
    soupEmail.value = tokens?.email ?? null
    if (tokens) servers.value = await fetchRoster(identityBaseUrl, tokens.accessToken)
    return servers.value
  }

  /** Makes a saved server the active session. */
  function activateSaved(server: SavedServer) {
    // Cached rows, items and progress all belong to the previous server.
    if (jellyfin.value && jellyfin.value.serverId !== server.serverId) nuxtApp.$queryClient.clear()
    writeLocal(LAST_SERVER_KEY, server.baseUrl)
    email.value = server.username
    choosingServer.value = false
    serverError.value = null
    persistJellyfin({
      baseUrl: server.baseUrl,
      userId: server.userId,
      accessToken: server.accessToken,
      serverId: server.serverId,
      deviceId: server.deviceId,
      direct: true,
      serverName: server.name,
    })
  }

  /** Switches to a saved server once its token checks out; a rejected token drops the entry. */
  async function switchToSaved(id: string) {
    const server = savedServers.value.find(entry => entry.id === id)
    if (!server) throw new Error('That server is no longer saved')
    let response: Response
    try {
      response = await fetch(`${server.baseUrl}/Users/Me`, {
        headers: { Accept: 'application/json', Authorization: mediaBrowserAuth(server.deviceId, server.accessToken) },
      })
    }
    catch {
      throw new Error(`Couldn't reach ${server.name}. Check that it's online and allows this site.`)
    }
    if (response.status === 401 || response.status === 403) {
      writeSaved(savedServers.value.filter(entry => entry.id !== id))
      throw new Error(`Your session on ${server.name} ended. Add it again to sign back in.`)
    }
    if (!response.ok) throw new Error(`${server.name} returned an error (${response.status})`)
    activateSaved(server)
  }

  /**
   * After the active server goes away: another saved server, else the Soup roster.
   * `chooseServer` means Soup is signed in but the login page's picker has to decide.
   */
  async function fallBack(): Promise<'switched' | 'chooseServer' | 'signedOut'> {
    persistJellyfin(null)
    nuxtApp.$queryClient.clear()
    for (const next of savedServers.value) {
      try {
        await switchToSaved(next.id)
        return 'switched'
      }
      catch {
        // Try the next one.
      }
    }
    try {
      const payload = await exchangeSoup()
      if (payload) {
        await applySoup(payload)
        return payload.jellyfin ? 'switched' : 'chooseServer'
      }
    }
    catch (error) {
      if (offerServers(error)) return 'chooseServer'
    }
    email.value = null
    return 'signedOut'
  }

  /** Signs out of a saved server and forgets it, falling back to another server when it was the active one. */
  async function removeSaved(id: string): Promise<'switched' | 'chooseServer' | 'signedOut'> {
    const server = savedServers.value.find(entry => entry.id === id)
    if (!server) return 'switched'
    const wasActive = activeSavedId() === id
    writeSaved(savedServers.value.filter(entry => entry.id !== id))
    void fetch(`${server.baseUrl}/Sessions/Logout`, {
      method: 'POST',
      headers: { Authorization: mediaBrowserAuth(server.deviceId, server.accessToken) },
    }).catch(() => {})
    return wasActive ? fallBack() : 'switched'
  }

  /** Signs in against a Jellyfin server with a username and password, skipping Soup Identity. */
  async function signInDirect(serverUrl: string, username: string, password: string, options: { activate?: boolean } = {}) {
    const baseUrl = normalizeServerUrl(serverUrl)
    if (!baseUrl) throw new Error('Enter your Jellyfin server address')
    const deviceId = webDeviceId()
    let response: Response
    try {
      response = await fetch(`${baseUrl}/Users/AuthenticateByName`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': mediaBrowserAuth(deviceId),
        },
        body: JSON.stringify({ Username: username, Pw: password }),
      })
    }
    catch {
      throw new Error(`Couldn't reach ${baseUrl}. Check the address and that the server allows this site.`)
    }
    if (response.status === 401 || response.status === 403) {
      throw new Error('Incorrect username or password')
    }
    if (!response.ok) {
      throw new Error(`Jellyfin sign-in failed (${response.status})`)
    }
    return applyDirectAuth(baseUrl, deviceId, response, options.activate ?? true)
  }

  /** Saves a Jellyfin AuthenticationResult as a direct (non-Soup) server, and switches to it when `activate`. */
  async function applyDirectAuth(baseUrl: string, deviceId: string, response: Response, activate: boolean): Promise<SavedServer> {
    const body = await response.json() as {
      AccessToken: string
      ServerId: string
      User: { Id: string, Name: string }
    }
    const server: SavedServer = {
      id: `${body.ServerId}:${body.User.Id}`,
      name: await fetchServerName(baseUrl),
      baseUrl,
      serverId: body.ServerId,
      userId: body.User.Id,
      username: body.User.Name,
      accessToken: body.AccessToken,
      deviceId,
      addedAt: savedServers.value.find(entry => entry.id === `${body.ServerId}:${body.User.Id}`)?.addedAt ?? Date.now(),
    }
    upsertSaved(server)
    if (activate) activateSaved(server)
    return server
  }

  /**
   * Starts a Quick Connect request: the user enters the returned code in a Jellyfin app
   * that's already signed in, then `pollQuickConnect` picks up the session.
   */
  async function startQuickConnect(serverUrl: string): Promise<{ baseUrl: string, secret: string, code: string }> {
    const baseUrl = normalizeServerUrl(serverUrl)
    if (!baseUrl) throw new Error('Enter your Jellyfin server address')
    const headers = { Accept: 'application/json', Authorization: mediaBrowserAuth(webDeviceId()) }
    let enabled: Response
    try {
      enabled = await fetch(`${baseUrl}/QuickConnect/Enabled`, { headers })
    }
    catch {
      throw new Error(`Couldn't reach ${baseUrl}. Check the address and that the server allows this site.`)
    }
    if (!enabled.ok || !(await enabled.json().catch(() => false))) {
      throw new Error('Quick Connect is turned off on this server. An admin can enable it in the Jellyfin dashboard.')
    }
    const response = await fetch(`${baseUrl}/QuickConnect/Initiate`, { method: 'POST', headers })
    if (!response.ok) throw new Error(`Couldn't start Quick Connect (${response.status})`)
    const body = await response.json() as { Secret?: string, Code?: string }
    if (!body.Secret || !body.Code) throw new Error('Jellyfin returned no Quick Connect code')
    return { baseUrl, secret: body.Secret, code: body.Code }
  }

  /** `approved` once the code is accepted (the server is then saved), `expired` when the server dropped it. */
  async function pollQuickConnect(
    baseUrl: string,
    secret: string,
    options: { activate?: boolean } = {},
  ): Promise<{ status: 'pending' | 'expired' } | { status: 'approved', server: SavedServer }> {
    const deviceId = webDeviceId()
    const headers = { Accept: 'application/json', Authorization: mediaBrowserAuth(deviceId) }
    const state = await fetch(`${baseUrl}/QuickConnect/Connect?${new URLSearchParams({ secret })}`, { headers })
    // Unknown secrets come back as 404 (or 401 on some versions) once they time out.
    if (state.status === 404 || state.status === 401) return { status: 'expired' }
    if (!state.ok) throw new Error(`Quick Connect check failed (${state.status})`)
    const { Authenticated } = await state.json() as { Authenticated?: boolean }
    if (!Authenticated) return { status: 'pending' }
    const response = await fetch(`${baseUrl}/Users/AuthenticateWithQuickConnect`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ Secret: secret }),
    })
    if (!response.ok) throw new Error(`Quick Connect sign-in failed (${response.status})`)
    const server = await applyDirectAuth(baseUrl, deviceId, response, options.activate ?? true)
    return { status: 'approved', server }
  }

  async function cancelLogin() {
    deviceLink = null
  }

  /** After a 401 with `failedToken`; a no-op when the session has already moved on from it. */
  async function reexchange(failedToken?: string): Promise<AuthSessionResponse> {
    if (failedToken && jellyfin.value && jellyfin.value.accessToken !== failedToken) {
      return { email: email.value ?? '', jellyfin: jellyfin.value }
    }
    if (jellyfin.value?.direct) {
      // A direct token can't be refreshed, so drop the server and move to another one.
      reexchanging ??= (async () => {
        const dead = activeSavedId()
        writeSaved(savedServers.value.filter(entry => entry.id !== dead))
        const result = await fallBack()
        await navigateTo(result === 'switched' ? '/' : '/login')
        throw new Error('Jellyfin session expired')
      })().finally(() => {
        reexchanging = null
      })
      return reexchanging
    }
    if (isMockMode()) {
      await applyMockSession()
      return { email: MOCK_EMAIL, jellyfin: MOCK_SESSION }
    }
    reexchanging ??= (async () => {
      const payload = await exchangeSoup(jellyfin.value?.soupServerId)
      if (!payload) {
        email.value = null
        persistJellyfin(null)
        await navigateTo('/login')
        throw new Error('Soup session expired')
      }
      await applySoup(payload)
      if (!payload.jellyfin) {
        await navigateTo('/login')
        throw new Error('Choose a server')
      }
      return payload
    })().finally(() => {
      reexchanging = null
    })
    return reexchanging
  }

  /** Signs out of Soup and every saved server. */
  async function logout() {
    const saved = savedServers.value
    try {
      if (isMockMode()) {
        mockDismissed.value = true
      }
      else {
        writeSaved([])
        const tokens = readTokens()
        writeTokens(null)
        await Promise.all([
          ...saved.map(server => fetch(`${server.baseUrl}/Sessions/Logout`, {
            method: 'POST',
            headers: { Authorization: mediaBrowserAuth(server.deviceId, server.accessToken) },
          }).catch(() => {})),
          tokens && revokeSoupSession(identityBaseUrl, tokens.refreshToken),
        ])
      }
    }
    finally {
      soupEmail.value = null
      email.value = null
      persistJellyfin(null)
      servers.value = []
      choosingServer.value = false
      serverError.value = null
      nuxtApp.$queryClient.clear()
    }
  }

  return {
    email,
    jellyfin,
    ready,
    loading,
    hydrate,
    startLogin,
    pollLogin,
    cancelLogin,
    signInDirect,
    startQuickConnect,
    pollQuickConnect,
    reexchange,
    logout,
    servers,
    choosingServer,
    serverError,
    selectServer,
    loadServers,
    savedServers,
    soupEmail,
    switchToSaved,
    removeSaved,
    enterMockLibrary: applyMockSession,
  }
}
