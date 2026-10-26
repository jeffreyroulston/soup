<script setup lang="ts">
import type { SavedServer } from '~/composables/useAuthSession'
import type { ServerEntry } from '~/composables/useServers'

const auth = useAuthSession()
const { entries, currentKey, currentName, switchTo, switchingTo, switchError, rename, move } = useServers()

const currentHost = computed(() => (auth.jellyfin.value ? new URL(auth.jellyfin.value.baseUrl).host : ''))
const sharedCount = computed(() => entries.value.filter(entry => entry.kind === 'soup').length)

const editing = ref(false)
const adding = ref(false)
const connecting = ref(false)
const refreshing = ref(false)
const refreshError = ref('')
/** Key of the server just added or linked, highlighted until the next action. */
const justAdded = ref<string | null>(null)
/** Saved-server key waiting for a second click to confirm removal. */
const confirmingRemove = ref<string | null>(null)
const removing = ref<string | null>(null)

onMounted(() => void refresh())

async function refresh() {
  if (refreshing.value || !auth.soupEmail.value) return
  refreshing.value = true
  refreshError.value = ''
  try {
    await auth.loadServers(true)
  }
  catch (error) {
    refreshError.value = error instanceof Error ? error.message : 'Could not load your Soup servers'
  }
  finally {
    refreshing.value = false
  }
}

function startAdding() {
  adding.value = true
  editing.value = false
  justAdded.value = null
}

function toggleEditing() {
  editing.value = !editing.value
  confirmingRemove.value = null
  justAdded.value = null
}

function onAdded(server: SavedServer) {
  adding.value = false
  justAdded.value = `direct:${server.id}`
}

function onLinked() {
  connecting.value = false
  justAdded.value = entries.value.find(entry => entry.kind === 'soup')?.key ?? null
}

async function onSwitch(entry: ServerEntry) {
  justAdded.value = null
  await switchTo(entry)
}

async function onRemove(entry: ServerEntry) {
  if (confirmingRemove.value !== entry.key) {
    confirmingRemove.value = entry.key
    return
  }
  confirmingRemove.value = null
  removing.value = entry.key
  try {
    if (await auth.removeSaved(entry.id) !== 'switched') await navigateTo('/login')
  }
  finally {
    removing.value = null
  }
}
</script>

<template>
  <div class="flex flex-col gap-4">
    <section aria-labelledby="settings-current" class="flex items-center gap-4 rounded-panel bg-surface p-6">
      <span class="grid size-12 shrink-0 place-items-center rounded-[14px] bg-ok/15 text-ok">
        <svg viewBox="0 0 24 24" class="size-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <rect x="3" y="4" width="18" height="7" rx="2" /><rect x="3" y="13" width="18" height="7" rx="2" /><path d="M7 7.5h.01M7 16.5h.01" />
        </svg>
      </span>
      <div class="flex min-w-0 flex-col gap-0.5">
        <h2 id="settings-current" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
          Watching from
        </h2>
        <p class="truncate text-lg font-bold">
          {{ currentName || 'No server' }}
        </p>
        <p v-if="auth.jellyfin.value" class="truncate text-sm text-muted">
          {{ auth.jellyfin.value.direct ? `Signed in as ${auth.email.value}` : 'Through Soup' }} · {{ currentHost }}
        </p>
      </div>
    </section>

    <section aria-labelledby="settings-servers" class="flex flex-col gap-4 rounded-panel bg-surface p-6">
      <div class="flex items-center justify-between gap-3">
        <h2 id="settings-servers" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
          Your servers
        </h2>
        <div class="flex items-center gap-2">
          <button
            v-if="entries.length > 0 && !adding"
            type="button"
            :aria-pressed="editing"
            class="h-9 rounded-full px-4 text-[13px] font-bold transition"
            :class="editing ? 'bg-ok text-canvas' : 'text-ink-2 hover:bg-white/10 hover:text-ink'"
            @click="toggleEditing"
          >
            {{ editing ? 'Done' : 'Edit' }}
          </button>
          <button
            v-if="!adding && !editing && !isMockMode()"
            type="button"
            class="flex h-9 items-center gap-1.5 rounded-full bg-ink px-4 text-[13px] font-extrabold text-canvas transition hover:bg-ink/80"
            @click="startAdding"
          >
            <svg viewBox="0 0 24 24" class="size-4" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true">
              <path d="M12 5v14M5 12h14" />
            </svg>
            Add server
          </button>
        </div>
      </div>

      <AddServerForm v-if="adding" @added="onAdded" @cancel="adding = false" />

      <p v-if="switchError" role="alert" class="text-sm font-semibold text-accent">
        {{ switchError }}
      </p>

      <ul v-if="entries.length" class="flex flex-col gap-1">
        <li v-for="(entry, index) in entries" :key="entry.key">
          <ServerRow
            :entry="entry"
            :current="entry.key === currentKey"
            :switching="switchingTo === entry.key"
            :disabled="switchingTo !== null || removing !== null"
            :highlight="entry.key === justAdded"
            :editing="editing"
            :first="index === 0"
            :last="index === entries.length - 1"
            @switch="onSwitch(entry)"
            @rename="rename(entry.key, $event)"
            @move="move(entry.key, $event)"
          >
            <template #edit>
              <button
                v-if="entry.kind === 'direct'"
                type="button"
                :disabled="removing !== null"
                :aria-label="confirmingRemove === entry.key ? `Confirm removing ${entry.name}` : `Remove ${entry.name}`"
                class="grid h-9 min-w-9 shrink-0 place-items-center rounded-full text-[13px] font-bold transition disabled:opacity-50"
                :class="confirmingRemove === entry.key || removing === entry.key ? 'bg-accent px-3.5 text-canvas' : 'text-muted hover:bg-white/10 hover:text-ink'"
                @click="onRemove(entry)"
                @blur="confirmingRemove === entry.key && (confirmingRemove = null)"
              >
                <template v-if="removing === entry.key">Removing…</template>
                <template v-else-if="confirmingRemove === entry.key">Remove?</template>
                <svg v-else viewBox="0 0 24 24" class="size-[18px]" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3" />
                </svg>
              </button>
              <!-- Shared servers leave the list when the owner removes you; keep the columns aligned. -->
              <span v-else class="size-9 shrink-0" aria-hidden="true" />
            </template>
          </ServerRow>
        </li>
      </ul>
      <p v-else-if="!adding" class="text-sm text-muted">
        No servers yet. Add a Jellyfin server you have an account on, or connect a Soup account to see servers shared with you.
      </p>
      <p v-if="editing" class="text-[13px] leading-snug text-muted">
        Nicknames and order are saved in this browser and used in the account menu. Clear a nickname to go back to the server's own name.
      </p>
    </section>

    <section v-if="!isMockMode()" aria-labelledby="settings-soup" class="flex flex-col gap-4 rounded-panel bg-surface p-6">
      <div class="flex items-center justify-between gap-4">
        <h2 id="settings-soup" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
          Soup account
        </h2>
        <button
          v-if="auth.soupEmail.value"
          type="button"
          :disabled="refreshing"
          class="flex items-center gap-2 text-[13px] font-bold text-muted transition enabled:hover:text-ink"
          @click="refresh"
        >
          <span v-if="refreshing" class="size-3.5 animate-spin rounded-full border-2 border-muted/30 border-t-muted" />
          Refresh
        </button>
      </div>

      <template v-if="auth.soupEmail.value">
        <div class="flex flex-col gap-0.5">
          <p class="text-base font-bold">
            {{ auth.soupEmail.value }}
          </p>
          <p class="text-sm text-muted">
            {{ sharedCount || 'No' }} shared {{ sharedCount === 1 ? 'server' : 'servers' }}.
            Owners invite this email from Soup Invites in their Jellyfin dashboard.
          </p>
        </div>
        <p v-if="refreshError" role="alert" class="text-sm font-semibold text-accent">
          {{ refreshError }}
        </p>
      </template>
      <template v-else>
        <p class="text-sm text-muted">
          Connect a Soup account to watch servers people share with you, with no Jellyfin password.
          You'll stay on the server you're watching now.
        </p>
        <ConnectSoupForm v-if="connecting" @linked="onLinked" @cancel="connecting = false" />
        <button
          v-else
          type="button"
          class="h-11 self-start rounded-btn bg-ink px-5 text-[15px] font-extrabold text-canvas transition hover:bg-ink/80"
          @click="connecting = true"
        >
          Connect Soup account
        </button>
      </template>
    </section>
  </div>
</template>
