import { deviceUserKey } from '~/composables/useAuthSession'

/** One person on this device's user switcher. */
export type DeviceUserEntry = {
  /** `deviceUserKey`: `soup:<email>` or `direct:<saved id>`. */
  key: string
  name: string
  /** `name` without an email's domain, for where there's little room. */
  shortName: string
  /** The server for a direct user, since they're tied to one. */
  detail: string
  /** Their Jellyfin picture, which may not exist; null until they've signed in to a server here. */
  imageUrl: string | null
}

function avatarUrl(baseUrl?: string, userId?: string): string | null {
  return baseUrl && userId ? `${baseUrl}/Users/${userId}/Images/Primary?maxHeight=360` : null
}

/** The Multi-user switcher: who's on this device, and moving between them. */
export function useDeviceUsers() {
  const auth = useAuthSession()
  const switchingTo = ref<string | null>(null)
  const switchError = ref('')

  const enabled = computed(() => auth.deviceUsers.value !== null)
  const currentKey = auth.activeUserKey

  const users = computed<DeviceUserEntry[]>(() => auth.signedInUsers.value.map((user) => {
    const key = deviceUserKey(user)
    if (user.kind === 'soup') {
      return {
        key,
        name: user.email,
        shortName: user.email.split('@')[0] || user.email,
        detail: 'Soup account',
        imageUrl: avatarUrl(user.baseUrl, user.userId),
      }
    }
    const server = auth.savedServers.value.find(entry => entry.id === user.id)
    const name = server?.username ?? ''
    return {
      key,
      name,
      shortName: name.split('@')[0] || name,
      detail: server?.name ?? '',
      imageUrl: avatarUrl(server?.baseUrl, server?.userId),
    }
  }))

  const current = computed(() => users.value.find(user => user.key === currentKey.value) ?? null)
  const others = computed(() => users.value.filter(user => user.key !== currentKey.value))

  /** True once switched; errors land in `switchError`. */
  async function switchTo(key: string): Promise<boolean> {
    if (switchingTo.value || key === currentKey.value) return false
    switchingTo.value = key
    switchError.value = ''
    try {
      const split = key.indexOf(':')
      const id = key.slice(split + 1)
      if (key.startsWith('soup:')) await auth.switchToSoupUser(id)
      else await auth.switchToSaved(id)
      return true
    }
    catch (error) {
      switchError.value = error instanceof Error ? error.message : 'Could not switch users'
      return false
    }
    finally {
      switchingTo.value = null
    }
  }

  /**
   * Signs the current user out and hands over to the next person, or signs out when there's nobody.
   * `failed` means nobody else could be reached, so everyone stays signed in and `switchError` says why.
   */
  async function signOutCurrent(): Promise<'switched' | 'signedOut' | 'failed'> {
    const leaving = currentKey.value
    for (const user of others.value) {
      if (await switchTo(user.key)) {
        if (leaving) await auth.removeDeviceUser(leaving)
        return 'switched'
      }
    }
    // Still listed means unreachable rather than signed out, and that shouldn't cost them their sign-in.
    if (others.value.length) return 'failed'
    await auth.logout()
    return 'signedOut'
  }

  return { enabled, users, current, others, currentKey, switchTo, switchingTo, switchError, signOutCurrent }
}
