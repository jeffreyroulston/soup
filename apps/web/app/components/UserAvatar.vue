<script setup lang="ts">
const props = withDefaults(defineProps<{
  src?: string | null
  label?: string | null
}>(), {
  src: null,
  label: null,
})

const failed = ref(false)
watch(() => props.src, () => {
  failed.value = false
})

const initial = computed(() => (props.label?.trim() || 'S').charAt(0).toUpperCase())
const showImage = computed(() => Boolean(props.src) && !failed.value)
</script>

<template>
  <span class="relative grid place-items-center overflow-hidden">
    {{ initial }}
    <img
      v-if="showImage"
      :src="src!"
      alt=""
      class="absolute inset-0 size-full object-cover"
      @error="failed = true"
    >
    <slot />
  </span>
</template>
