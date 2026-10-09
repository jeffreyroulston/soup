import type { AuthSessionResponse, JellyfinSessionPayload } from '~/types/jellyfin'
import { MOCK_EMAIL, MOCK_SESSION } from '~/utils/mockCatalog'
import { isMockMode } from '~/utils/mockMode'
import { exchangeForJellyfin } from '~/utils/soupExchange'
import {
  IdentityError,
  pollDeviceLink,
  refreshSoupSession,
  revokeSoupSession,
  startDeviceLink,
} from '~/utils/soupIdentity'

/** This tab's Jellyfin token from a Soup sign-in; other tabs mint their own from the Soup tokens. */
const STORAGE_KEY = 'soup.jellyfin.session'
/** Direct Jellyfin sign-ins have no Soup tokens to restore from, so they persist across tabs. */
const DIRECT_KEY = 'soup.jellyfin.direct'
const DEVICE_KEY = 'soup.jellyfin.deviceId'
/** Soup Identity session, shared by every tab in this browser. */
const TOKENS_KEY = 'soup.identity.tokens'
export const LAST_SERVER_KEY = 'soup.jellyfin.lastServer'

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

  /** A new Jellyfin token from the stored Soup tokens; null when there is no usable Soup session. */
  async function exchangeSoup(): Promise<AuthSessionResponse | null> {
    const tokens = await freshTokens(identityBaseUrl)
    if (!tokens) return null
    try {
      const session = await exchangeForJellyfin(identityBaseUrl, tokens.accessToken, webDeviceId())
      return { email: tokens.email, jellyfin: session }
    }
    catch (error) {
      if (!(error instanceof IdentityError && error.status === 401)) throw error
      writeTokens(null)
      return null
    }
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
        await applySession(payload)
      }
      else {
        email.value = null
        persistJellyfin(null)
      }
    }
    catch {
      // Identity or Jellyfin unreachable. The Soup tokens stay, so the next load can retry.
      email.value = null
      persistJellyfin(null)
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
      interval,
      expiresIn: started.expires_in,
    }
  }

  async function pollLogin() {
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
    const session = await exchangeForJellyfin(identityBaseUrl, tokens.accessToken, webDeviceId())
    await applySession({ email: tokens.email, jellyfin: session })
    return { status: 'approved' as const, email: tokens.email, jellyfin: session }
  }

  /** Signs in against a Jellyfin server with a username and password, skipping Soup Identity. */
  async function signInDirect(serverUrl: string, username: string, password: string) {
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
    await applyDirectAuth(baseUrl, deviceId, response)
  }

  /** Stores a Jellyfin AuthenticationResult as a direct (non-Soup) session. */
  async function applyDirectAuth(baseUrl: string, deviceId: string, response: Response) {
    const body = await response.json() as {
      AccessToken: string
      ServerId: string
      User: { Id: string, Name: string }
    }
    writeLocal(LAST_SERVER_KEY, baseUrl)
    email.value = body.User.Name
    persistJellyfin({
      baseUrl,
      userId: body.User.Id,
      accessToken: body.AccessToken,
      serverId: body.ServerId,
      deviceId,
      direct: true,
    })
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

  /** `approved` once the code is accepted (the session is then stored), `expired` when the server dropped it. */
  async function pollQuickConnect(baseUrl: string, secret: string): Promise<'pending' | 'approved' | 'expired'> {
    const deviceId = webDeviceId()
    const headers = { Accept: 'application/json', Authorization: mediaBrowserAuth(deviceId) }
    const state = await fetch(`${baseUrl}/QuickConnect/Connect?${new URLSearchParams({ secret })}`, { headers })
    // Unknown secrets come back as 404 (or 401 on some versions) once they time out.
    if (state.status === 404 || state.status === 401) return 'expired'
    if (!state.ok) throw new Error(`Quick Connect check failed (${state.status})`)
    const { Authenticated } = await state.json() as { Authenticated?: boolean }
    if (!Authenticated) return 'pending'
    const response = await fetch(`${baseUrl}/Users/AuthenticateWithQuickConnect`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ Secret: secret }),
    })
    if (!response.ok) throw new Error(`Quick Connect sign-in failed (${response.status})`)
    await applyDirectAuth(baseUrl, deviceId, response)
    return 'approved'
  }

  async function cancelLogin() {
    deviceLink = null
  }

  async function reexchange() {
    if (jellyfin.value?.direct) {
      // A direct token can't be refreshed; the user has to sign in again.
      email.value = null
      persistJellyfin(null)
      await navigateTo('/login')
      throw new Error('Jellyfin session expired')
    }
    if (isMockMode()) {
      await applyMockSession()
      return { email: MOCK_EMAIL, jellyfin: MOCK_SESSION }
    }
    reexchanging ??= (async () => {
      const payload = await exchangeSoup()
      if (!payload) {
        email.value = null
        persistJellyfin(null)
        await navigateTo('/login')
        throw new Error('Soup session expired')
      }
      await applySession(payload)
      return payload
    })().finally(() => {
      reexchanging = null
    })
    return reexchanging
  }

  async function logout() {
    const session = jellyfin.value
    try {
      if (session?.direct) {
        await fetch(`${session.baseUrl}/Sessions/Logout`, {
          method: 'POST',
          headers: { Authorization: mediaBrowserAuth(session.deviceId, session.accessToken) },
        }).catch(() => {})
      }
      else if (!isMockMode()) {
        const tokens = readTokens()
        writeTokens(null)
        if (tokens) await revokeSoupSession(identityBaseUrl, tokens.refreshToken)
      }
      else {
        mockDismissed.value = true
      }
    }
    finally {
      email.value = null
      persistJellyfin(null)
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
    enterMockLibrary: applyMockSession,
  }
}
