<script setup lang="ts">
const auth = useAuthSession()
const { enabled, users, others, currentKey, switchTo, switchingTo, switchError } = useDeviceUsers()

/** Asking before turning off would sign the other users out. */
const confirmingOff = ref(false)
const turningOff = ref(false)

function toggle() {
  if (!enabled.value) {
    auth.enableMultiUser()
    return
  }
  if (others.value.length) confirmingOff.value = true
  else void turnOff()
}

async function turnOff() {
  turningOff.value = true
  try {
    await auth.disableMultiUser()
    confirmingOff.value = false
  }
  finally {
    turningOff.value = false
  }
}

async function onSwitch(key: string) {
  if (await switchTo(key) && !auth.jellyfin.value) await navigateTo('/login')
}
</script>

<template>
  <section aria-labelledby="settings-multi-user" class="flex flex-col gap-4 rounded-panel bg-surface p-6">
    <div class="flex items-center justify-between gap-4">
      <h2 id="settings-multi-user" class="text-[13px] font-extrabold uppercase tracking-[0.6px] text-muted">
        Multi-user
      </h2>
      <button
        type="button"
        role="switch"
        :aria-checked="enabled"
        aria-labelledby="settings-multi-user"
        :disabled="turningOff"
        class="relative h-8 w-[52px] shrink-0 rounded-full transition-colors disabled:opacity-50"
        :class="enabled ? 'bg-ok' : 'bg-elevated'"
        @click="toggle"
      >
        <span
          class="absolute left-1 top-1 size-6 rounded-full bg-white shadow transition-transform"
          :class="enabled ? 'translate-x-5' : ''"
        />
      </button>
    </div>

    <div v-if="confirmingOff" role="alert" class="flex flex-col gap-3 rounded-[18px] bg-elevated/60 p-5">
      <p class="text-sm font-semibold text-ink-2">
        Turning this off signs {{ others.length === 1 ? others[0]!.name : `${others.length} other users` }} out of this device.
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          :disabled="turningOff"
          class="h-11 rounded-btn bg-accent px-5 text-[15px] font-extrabold text-canvas transition enabled:hover:bg-accent/80 disabled:opacity-60"
          @click="turnOff"
        >
          Sign out and turn off
        </button>
        <button
          type="button"
          :disabled="turningOff"
          class="h-11 rounded-btn bg-white/10 px-5 text-[15px] font-bold text-ink transition enabled:hover:bg-white/15"
          @click="confirmingOff = false"
        >
          Keep on
        </button>
      </div>
    </div>

    <template v-if="enabled">
      <ul class="flex flex-col gap-1 border-t border-white/10 pt-3">
        <li
          v-for="user in users"
          :key="user.key"
          class="flex items-center gap-3 rounded-btn px-3 py-2.5 transition-colors hover:bg-white/[0.04]"
        >
          <span
            class="grid size-9 shrink-0 place-items-center rounded-full text-sm font-extrabold"
            :class="user.key === currentKey ? 'bg-ok text-canvas' : 'bg-white/15 text-ink'"
          >{{ user.name.charAt(0).toUpperCase() }}</span>
          <span class="flex min-w-0 flex-1 flex-col">
            <span class="truncate text-base font-bold">{{ user.name }}</span>
            <span class="truncate text-[13px] font-semibold text-muted">{{ user.detail }}</span>
          </span>
          <span v-if="user.key === currentKey" class="shrink-0 text-[13px] font-bold text-ok">Watching</span>
          <button
            v-else
            type="button"
            :disabled="switchingTo !== null"
            class="flex h-9 shrink-0 items-center gap-2 rounded-full bg-white/10 px-4 text-[13px] font-bold text-ink transition enabled:hover:bg-white/15 disabled:opacity-50"
            @click="onSwitch(user.key)"
          >
            <span v-if="switchingTo === user.key" class="size-3.5 animate-spin rounded-full border-2 border-ink/30 border-t-ink" />
            Switch
          </button>
        </li>
      </ul>

      <p v-if="switchError" role="alert" class="text-sm font-semibold text-accent">
        {{ switchError }}
      </p>

      <NuxtLink
        to="/login?add=user"
        class="inline-flex h-11 items-center self-start rounded-btn bg-ink px-5 text-[15px] font-extrabold text-canvas transition hover:bg-ink/80"
      >
        Add user
      </NuxtLink>
      <p class="text-[13px] leading-snug text-muted">
        Switch users from the account menu, or pick one when opening Soup. There's no PIN, so anyone using this device can open any user here.
      </p>
    </template>
  </section>
</template>
