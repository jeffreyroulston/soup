export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/login') return
  const auth = useAuthSession()
  if (!auth.ready.value) {
    await auth.hydrate()
  }
  if (!auth.jellyfin.value) {
    return navigateTo('/login')
  }
})
