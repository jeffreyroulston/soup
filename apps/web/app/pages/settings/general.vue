<script setup lang="ts">
const auth = useAuthSession()
const { signOutCurrent, switchError } = useDeviceUsers()
const signingOut = ref(false)

/** While a direct server is active, the Soup account can be someone else's on a shared device. */
const accountName = computed(() => (auth.jellyfin.value?.direct ? auth.email.value : auth.soupEmail.value || auth.email.value))
/** Devices belong to the Soup account, which a direct user on a shared device mustn't manage. */
const soupUserActive = computed(() => Boolean(auth.soupEmail.value && auth.jellyfin.value && !auth.jellyfin.value.direct))

const identity = useIdentityConfig()
const identityInput = ref(identity.url.value)
const identityBusy = ref(false)
const identitySourceLabel = computed(() => ({
  override: 'Set in this browser',
  config: 'From the deployment config',
  build: 'Built-in default',
}[identity.source.value]))
const identityDirty = computed(() => normalizeIdentityUrl(identityInput.value) !== identity.url.value)

/** Tokens belong to the old server, so changing Identity signs this browser out. */
async function applyIdentity(input: string | null) {
  identityBusy.value = true
  try {
    await auth.logout()
    identity.setOverride(input)
    identityInput.value = identity.url.value
    await navigateTo('/login')
  }
  finally {
    identityBusy.value = false
  }
}

/** Signs out just the current user; anyone else on this device stays signed in. */
async function onLogout() {
  signingOut.value = true
  try {
    const result = await signOutCurrent()
    if (result === 'signedOut') await navigateTo('/login')
    else if (result === 'switched') await navigateTo(auth.signedInUsers.value.length > 1 ? '/users' : '/')
  }
  finally {
    signingOut.value = false
  }
}
</script>

<template>
  <div class="flex flex-col gap-4">
    <section aria-labelledby="settings-account" class="flex flex-col gap-4 rounded-panel bg-surface p-6">
      <h2 id="settings-account" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
        Account
      </h2>
      <div class="flex flex-col gap-0.5">
        <p class="text-lg font-bold">
          {{ accountName || 'Signed in' }}
        </p>
        <p class="text-sm text-muted">
          {{ auth.jellyfin.value?.direct || !auth.soupEmail.value ? 'Signed in directly to Jellyfin' : 'Soup account' }}
        </p>
      </div>
      <div class="flex flex-col gap-2 border-t border-white/10 pt-4">
        <button
          type="button"
          :disabled="signingOut"
          class="h-11 shrink-0 self-start rounded-btn bg-ink px-5 text-[15px] font-extrabold text-canvas transition enabled:hover:bg-ink/80 disabled:opacity-60"
          @click="onLogout"
        >
          Sign out
        </button>
        <p v-if="switchError" role="alert" class="text-sm font-semibold text-accent">
          {{ switchError }}
        </p>
      </div>
    </section>

    <MultiUserSettings v-if="!isMockMode()" />

    <SoupDevices v-if="soupUserActive && !isMockMode()" :key="auth.soupEmail.value!" />

    <section v-if="!isMockMode()" aria-labelledby="settings-identity" class="flex flex-col gap-3 rounded-panel bg-surface p-6">
      <h2 id="settings-identity" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
        Identity server
      </h2>
      <p class="text-sm text-muted">
        Where sign-in happens. {{ identitySourceLabel }}. Changing it signs you out.
      </p>
      <form class="flex flex-col gap-3 sm:flex-row" @submit.prevent="applyIdentity(identityInput)">
        <input
          v-model="identityInput"
          type="url"
          inputmode="url"
          autocomplete="off"
          spellcheck="false"
          aria-label="Identity server URL"
          placeholder="https://identity.example.com"
          class="h-12 min-w-0 flex-1 rounded-btn border border-white/10 bg-elevated px-4 text-base font-semibold text-ink outline-none focus:border-accent"
        >
        <div class="flex gap-2">
          <button
            type="submit"
            :disabled="identityBusy || !identityDirty || !normalizeIdentityUrl(identityInput)"
            class="h-12 rounded-btn bg-ink px-5 text-base font-extrabold text-canvas transition hover:bg-ink/80 disabled:opacity-40"
          >
            Save
          </button>
          <button
            v-if="identity.source.value === 'override'"
            type="button"
            :disabled="identityBusy"
            class="h-12 rounded-btn bg-elevated px-5 text-base font-bold text-ink-2 transition hover:text-ink disabled:opacity-40"
            @click="applyIdentity(null)"
          >
            Reset
          </button>
        </div>
      </form>
    </section>
  </div>
</template>
