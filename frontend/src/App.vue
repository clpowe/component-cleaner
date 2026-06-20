<script setup>
import { ref } from "vue";

const compDir = ref("");
const srcDir = ref("");
const report = ref(null);
const error = ref("");
const scanning = ref(false);

async function pick(target) {
  const paths = await window.zero.dialogs.openFile({
    title: target === "comp" ? "Pick components directory" : "Pick source root to scan",
    allowDirectories: true,
    allowMultiple: false,
  });
  const p = paths?.[0];
  if (!p) return;
  if (target === "comp") compDir.value = p;
  else srcDir.value = p;
}

async function findUnused() {
  error.value = "";
  report.value = null;
  scanning.value = true;
  try {
    report.value = await window.zero.invoke("native.scanUnused", {
      componentsDir: compDir.value,
      scanDir: srcDir.value,
    });
  } catch (e) {
    error.value = `${e.code ?? "error"}: ${e.message ?? e}`;
  } finally {
    scanning.value = false;
  }
}
</script>

<template>
  <main style="font-family: system-ui; padding: 2rem; display: grid; gap: 0.75rem; max-width: 40rem;">
    <h1>Component Cleaner</h1>

    <div style="display: flex; gap: 0.5rem; align-items: center;">
      <button @click="pick('comp')">Components folder…</button>
      <span style="opacity: 0.7; font-size: 0.85rem;">{{ compDir || "none" }}</span>
    </div>
    <div style="display: flex; gap: 0.5rem; align-items: center;">
      <button @click="pick('src')">Source root…</button>
      <span style="opacity: 0.7; font-size: 0.85rem;">{{ srcDir || "none" }}</span>
    </div>

    <button :disabled="!compDir || !srcDir || scanning" @click="findUnused">
      {{ scanning ? "Scanning…" : "Find unused" }}
    </button>

    <template v-if="report">
      <p>{{ report.total }} components scanned — {{ report.unused.length }} unused.</p>
      <ul v-if="report.unused.length" style="display: grid; gap: 0.25rem; padding-left: 1rem;">
        <li v-for="c in report.unused" :key="c.path">
          <strong>{{ c.name }}</strong>
          <span style="opacity: 0.6; font-size: 0.8rem;"> — {{ c.path }}</span>
        </li>
      </ul>
      <p v-else style="color: green;">No unused components. 🎉</p>
    </template>

    <p v-if="error" style="color: crimson;">{{ error }}</p>
  </main>
</template>
