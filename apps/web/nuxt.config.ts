import tailwindcss from '@tailwindcss/vite'

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  ssr: false,
  css: ['~/assets/css/main.css'],
  app: {
    head: {
      htmlAttrs: { lang: 'en' },
      title: 'soup',
      meta: [{ name: 'theme-color', content: '#0a0a0b' }],
      link: [
        { rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml' },
        { rel: 'icon', href: '/favicon.ico', sizes: '48x48' },
        { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' },
        { rel: 'manifest', href: '/site.webmanifest' },
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Manrope:wght@500;600;700;800&display=swap',
        },
      ],
    },
  },
  vite: {
    plugins: [tailwindcss()],
  },
  runtimeConfig: {
    public: {
      /** The browser calls Identity directly; fixed at build time for `nuxt generate`. */
      soupIdentityBaseUrl: 'https://soup-idm.bestiestudios.com',
      appName: 'Soup',
      appOrigin: 'http://localhost:3000',
      /** Prefills the server field for direct Jellyfin sign-in. */
      jellyfinUrl: '',
      /** When true, skip Identity/Jellyfin and serve an in-memory catalog. */
      mock: false,
    },
  },
})
