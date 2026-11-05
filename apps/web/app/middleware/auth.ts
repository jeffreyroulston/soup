/** True the first time this tab loads the app; a reload isn't a new launch. */
function firstLoadInTab(): boolean {
  const key = 'soup.users.launched'
  try {
    if (sessionStorage.getItem(key)) return false
    sessionStorage.setItem(key, '1')
    return true
  }
  catch {
    return false
  }
}

export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/login') return
  const auth = useAuthSession()
  const launching = !auth.ready.value
  if (launching) {
    await auth.hydrate()
  }
  const users = auth.signedInUsers.value
  const signedIn = Boolean(auth.jellyfin.value)
  // The picker still works with nobody active, but not with Multi-user off or nobody to pick.
  if (to.path === '/users') {
    if (auth.deviceUsers.value === null) return navigateTo(signedIn ? '/' : '/login')
    if (!signedIn && (auth.choosingServer.value || !users.length)) return navigateTo('/login')
    return
  }
  if (!signedIn) {
    // The active user's session ended, but someone else on this device can carry on.
    return navigateTo(users.length && !auth.choosingServer.value ? '/users' : '/login')
  }
  // Ask on opening the app at Home; a link to a title goes straight there.
  if (launching && firstLoadInTab() && to.path === '/' && users.length > 1) {
    return navigateTo('/users')
  }
})
