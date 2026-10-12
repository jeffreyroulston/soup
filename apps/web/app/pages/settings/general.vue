<script setup lang="ts">
const auth = useAuthSession()

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

async function onLogout() {
  await auth.logout()
  await navigateTo('/login')
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
          {{ auth.soupEmail.value || auth.email.value || 'Signed in' }}
        </p>
        <p class="text-sm text-muted">
          {{ auth.soupEmail.value ? 'Soup account' : 'Signed in directly to Jellyfin' }}
        </p>
      </div>
      <div class="flex flex-col gap-2 border-t border-white/10 pt-4 sm:flex-row sm:items-center sm:justify-between">
        <p class="text-sm text-muted">
          Signs this browser out of Soup and every server you've added.
        </p>
        <button
          type="button"
          class="h-11 shrink-0 self-start rounded-btn bg-ink px-5 text-[15px] font-extrabold text-canvas transition hover:bg-ink/80"
          @click="onLogout"
        >
          Sign out
        </button>
      </div>
    </section>

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
