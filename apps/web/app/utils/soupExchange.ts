import type { JellyfinSessionPayload } from '~/types/jellyfin'
import { CLIENT_NAME, CLIENT_VERSION, DEVICE_NAME, mediaBrowserAuth } from '~/utils/jellyfinHttp'
import { fetchRoster, mintAssertion, type RosterServer } from '~/utils/soupIdentity'

function jellyfinBaseUrl(server: RosterServer): string {
  const magicDns = server.magic_dns && `https://${server.magic_dns.replace(/^https?:\/\//, '')}`
  // An https page can't call an http `base_url` (mixed content), so take the Tailscale name.
  const httpsPage = typeof location !== 'undefined' && location.protocol === 'https:'
  if (magicDns && httpsPage && !server.base_url?.startsWith('https:')) return magicDns
  if (server.base_url) return server.base_url.replace(/\/$/, '')
  if (magicDns) return magicDns
  throw new Error('Roster server has no base_url or magic_dns')
}

/** Roster → assertion → `SoupAuth/Exchange`, all from the browser, which can reach the user's Jellyfin. */
export async function exchangeForJellyfin(
  identityBaseUrl: string,
  accessToken: string,
  deviceId: string,
): Promise<JellyfinSessionPayload> {
  const servers = await fetchRoster(identityBaseUrl, accessToken)
  if (!servers.length) {
    throw new Error('No Jellyfin servers on your Soup roster yet')
  }
  const server = servers[0]!
  const baseUrl = jellyfinBaseUrl(server)
  const { assertion } = await mintAssertion(identityBaseUrl, accessToken, server.id)

  let response: Response
  try {
    response = await fetch(`${baseUrl}/SoupAuth/Exchange`, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': mediaBrowserAuth(deviceId),
      },
      body: JSON.stringify({
        assertion,
        deviceId,
        deviceName: DEVICE_NAME,
        app: CLIENT_NAME,
        appVersion: CLIENT_VERSION,
      }),
    })
  }
  catch {
    throw new Error(`Couldn't reach ${baseUrl}. Check that the server is reachable and allows this site.`)
  }

  if (!response.ok) {
    const text = await response.text().catch(() => '')
    throw new Error(text || `SoupAuth exchange failed (${response.status})`)
  }

  const body = (await response.json()) as {
    AccessToken?: string
    User?: { Id?: string }
    ServerId?: string
  }
  if (!body.AccessToken || !body.User?.Id) {
    throw new Error('Incomplete SoupAuth exchange response')
  }

  return {
    baseUrl,
    userId: body.User.Id,
    accessToken: body.AccessToken,
    serverId: body.ServerId || server.id,
    deviceId,
  }
}
