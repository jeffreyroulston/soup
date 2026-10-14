// Soup Identity calls made straight from the browser (Identity serves open CORS, Bearer auth).

export type DeviceLinkStart = {
  device_code: string
  user_code: string
  verification_uri: string
  verification_uri_complete: string
  expires_in: number
  interval: number
}

export type SessionTokens = {
  access_token: string
  refresh_token: string
  expires_in: number
  token_type: string
  email: string
}

export type RosterServer = {
  id: string
  name: string
  base_url: string | null
  magic_dns: string | null
  audience: string
}

export type DeviceLinkPoll =
  | { status: 'pending' }
  | { status: 'expired' }
  | ({ status: 'approved' } & SessionTokens)

/** Non-2xx Identity response; `status` lets callers tell a dead refresh token from an outage. */
export class IdentityError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
  }
}

async function identityRequest(baseUrl: string, path: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(`${baseUrl}${path}`, init)
  }
  catch (error) {
    const cause = error instanceof Error ? error.message : 'fetch failed'
    throw new IdentityError(`Soup Identity unreachable at ${baseUrl} (${cause})`, 503)
  }
}

async function identityFetch<T>(baseUrl: string, path: string, init: RequestInit = {}): Promise<T> {
  const response = await identityRequest(baseUrl, path, {
    ...init,
    headers: {
      Accept: 'application/json',
      ...(init.body ? { 'Content-Type': 'application/json' } : {}),
      ...init.headers,
    },
  })
  if (!response.ok) {
    const text = await response.text().catch(() => '')
    throw new IdentityError(text || `Identity request failed (${response.status})`, response.status)
  }
  if (response.status === 204) return undefined as T
  return (await response.json()) as T
}

export function startDeviceLink(baseUrl: string): Promise<DeviceLinkStart> {
  return identityFetch<DeviceLinkStart>(baseUrl, '/auth/device/link', { method: 'POST' })
}

/** Google sign-in for a device code, skipping the /link page the QR code opens. */
export function googleSignInUrl(baseUrl: string, userCode: string): string {
  return `${baseUrl}/auth/google/start?user_code=${encodeURIComponent(userCode)}`
}

export async function pollDeviceLink(baseUrl: string, deviceCode: string): Promise<DeviceLinkPoll> {
  const response = await identityRequest(
    baseUrl,
    `/auth/device/link/${encodeURIComponent(deviceCode)}`,
    { headers: { Accept: 'application/json' } },
  )
  if (response.status === 400 || response.status === 404) {
    return { status: 'expired' }
  }
  if (!response.ok) {
    const text = await response.text().catch(() => '')
    throw new IdentityError(text || `Device-link poll failed (${response.status})`, response.status)
  }
  const body = (await response.json()) as Record<string, unknown>
  if (body.status === 'expired') return { status: 'expired' }
  if (body.status === 'approved' && typeof body.access_token === 'string') {
    return {
      status: 'approved',
      access_token: body.access_token,
      refresh_token: body.refresh_token as string,
      expires_in: Number(body.expires_in ?? 3600),
      token_type: String(body.token_type ?? 'Bearer'),
      email: String(body.email ?? ''),
    }
  }
  return { status: 'pending' }
}

export function refreshSoupSession(baseUrl: string, refreshToken: string): Promise<SessionTokens> {
  return identityFetch<SessionTokens>(baseUrl, '/v1/sessions/refresh', {
    method: 'POST',
    body: JSON.stringify({ refresh_token: refreshToken }),
  })
}

export async function revokeSoupSession(baseUrl: string, refreshToken: string) {
  try {
    await identityFetch(baseUrl, '/v1/sessions/revoke', {
      method: 'POST',
      body: JSON.stringify({ refresh_token: refreshToken }),
    })
  }
  catch {
    // best-effort
  }
}

export async function fetchRoster(baseUrl: string, accessToken: string): Promise<RosterServer[]> {
  const body = await identityFetch<{ servers: RosterServer[] }>(baseUrl, '/v1/me/servers', {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  return body.servers ?? []
}

export function mintAssertion(
  baseUrl: string,
  accessToken: string,
  serverId: string,
): Promise<{ assertion: string, server_id: string }> {
  return identityFetch(baseUrl, '/v1/assertions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({ server_id: serverId }),
  })
}
