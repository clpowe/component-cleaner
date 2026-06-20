<script setup>
defineProps({ label: { type: String, default: "" } });
</script>

<template>
  <button class="base-button">{{ label }}<slot /></button>
</template>
