<script setup>
import { ref } from "vue";

const compDir = ref("");
const srcDir = ref("");
const report = ref(null);
const error = ref("");
const scanning = ref(false);

const checkName = ref("");
const single = ref(null);
const checking = ref(false);

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

async function checkOne() {
  error.value = "";
  single.value = null;
  checking.value = true;
  try {
    single.value = await window.zero.invoke("native.scanComponent", {
      componentName: checkName.value,
      scanDir: srcDir.value,
    });
  } catch (e) {
    error.value = `${e.code ?? "error"}: ${e.message ?? e}`;
  } finally {
    checking.value = false;
  }
}
</script>

<template>
  <main class="cc-main">
    <div class="cc-shell">
      <header class="cc-header">
        <span class="cc-eyebrow">Developer tools</span>
        <h1 class="cc-title">Component cleaner.</h1>
        <p class="cc-lede">
          Scan a project for components nothing imports — then delete with confidence.
        </p>
      </header>

      <section class="cc-section">
        <div class="cc-row">
          <div class="cc-row-text">
            <span class="cc-label">Components folder</span>
            <span class="cc-path">{{ compDir || "No folder selected" }}</span>
          </div>
          <button class="cc-btn cc-btn--outline cc-btn--sm" @click="pick('comp')">Choose…</button>
        </div>

        <div class="cc-row">
          <div class="cc-row-text">
            <span class="cc-label">Source root</span>
            <span class="cc-path">{{ srcDir || "No folder selected" }}</span>
          </div>
          <button class="cc-btn cc-btn--outline cc-btn--sm" @click="pick('src')">Choose…</button>
        </div>

        <button
          class="cc-btn cc-btn--primary cc-btn--lg cc-btn--block"
          :disabled="!compDir || !srcDir || scanning"
          @click="findUnused"
        >
          {{ scanning ? "Scanning…" : "Find unused" }}
        </button>
      </section>

      <div v-if="scanning" class="cc-scan">
        <span class="cc-label">Scanning source tree…</span>
        <div class="cc-bar"><div class="cc-bar-fill"></div></div>
      </div>

      <section v-if="report && !scanning" class="cc-section cc-report">
        <div class="cc-report-head">
          <span class="cc-muted">{{ report.total }} components scanned</span>
          <span v-if="report.unused.length" class="cc-badge">{{ report.unused.length }} unused</span>
        </div>

        <div v-if="report.unused.length" class="cc-list">
          <div v-for="c in report.unused" :key="c.path" class="cc-row">
            <div class="cc-row-text">
              <span class="cc-name">{{ c.name }}</span>
              <span class="cc-path">{{ c.path }}</span>
            </div>
            <span class="cc-tag">unused</span>
          </div>
        </div>

        <p v-else class="cc-body">Nothing to clean — every component is referenced.</p>
      </section>

      <div class="cc-divider"></div>

      <section class="cc-section">
        <span class="cc-eyebrow">Check one component</span>
        <p class="cc-muted">Searches the source root above for any reference.</p>
        <div class="cc-check">
          <input
            v-model="checkName"
            class="cc-input"
            placeholder="ComponentName"
            @keyup.enter="checkOne"
          />
          <button
            class="cc-btn cc-btn--outline cc-btn--lg"
            :disabled="!checkName || !srcDir || checking"
            @click="checkOne"
          >
            {{ checking ? "Checking…" : "Check" }}
          </button>
        </div>
        <div v-if="single && !checking" class="cc-row cc-row--single">
          <span class="cc-body">
            {{ single.used ? `Used — first reference in ${single.file}` : "Appears unused — safe to remove." }}
          </span>
        </div>
      </section>

      <p v-if="error" class="cc-error">{{ error }}</p>
    </div>
  </main>
</template>

<style scoped>
.cc-main {
  min-height: 100vh;
  box-sizing: border-box;
  display: flex;
  justify-content: center;
  padding: 80px 24px 96px;
  background: var(--color-canvas);
  color: var(--color-ink);
  font-family: var(--font-display);
}

.cc-shell {
  width: 100%;
  max-width: 600px;
  display: flex;
  flex-direction: column;
  gap: 32px;
}

.cc-header {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.cc-title {
  margin: 0;
  font-size: 52px;
  line-height: 1.02;
  letter-spacing: -0.025em;
  font-weight: 400;
  color: var(--color-ink);
}

.cc-lede {
  margin: 0;
  max-width: 46ch;
  font-size: 17px;
  line-height: 1.6;
  color: var(--color-body);
}

.cc-eyebrow {
  font-family: var(--font-mono);
  font-size: 12px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--color-mute);
}

.cc-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.cc-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 16px 18px;
  border: 1px solid var(--color-hairline);
  border-radius: var(--radius-sm);
  background: var(--color-canvas-card);
}

.cc-row--single { padding: 14px 18px; }

.cc-row-text {
  display: flex;
  flex-direction: column;
  gap: 5px;
  min-width: 0;
}

.cc-label {
  font-family: var(--font-mono);
  font-size: 11px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--color-mute);
}

.cc-path {
  font-family: var(--font-mono);
  font-size: 13px;
  color: var(--color-body);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cc-name {
  font-size: 15px;
  color: var(--color-ink);
}

.cc-tag {
  font-family: var(--font-mono);
  font-size: 11px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--color-mute);
  white-space: nowrap;
}

.cc-muted {
  font-size: 13px;
  color: var(--color-mute);
}

.cc-body {
  margin: 0;
  font-size: 15px;
  color: var(--color-body);
}

/* Buttons — pill, weight 400, hover fades to 0.75 */
.cc-btn {
  font-family: var(--font-display);
  font-size: 14px;
  font-weight: 400;
  line-height: 1;
  border-radius: var(--radius-pill);
  cursor: pointer;
  transition: opacity 0.15s ease;
  white-space: nowrap;
}

.cc-btn:hover:not(:disabled) { opacity: 0.75; }

.cc-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.cc-btn--outline {
  background: transparent;
  border: 1px solid var(--color-border-pill);
  color: var(--color-ink);
}

.cc-btn--primary {
  background: var(--color-ink);
  border: 1px solid var(--color-ink);
  color: var(--color-canvas);
}

.cc-btn--sm { padding: 0 16px; height: 28px; }
.cc-btn--lg { padding: 0 24px; height: 52px; font-size: 15px; }
.cc-btn--block { width: 100%; margin-top: 4px; }

/* Scan progress */
.cc-scan {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.cc-bar {
  position: relative;
  height: 2px;
  border-radius: var(--radius-pill);
  background: var(--color-canvas-soft);
  overflow: hidden;
}

.cc-bar-fill {
  position: absolute;
  top: 0;
  left: 0;
  height: 100%;
  width: 32%;
  border-radius: var(--radius-pill);
  background: rgba(255, 255, 255, 0.55);
  animation: ccbar 1s ease-in-out infinite;
}

/* Report */
.cc-report { gap: 16px; }

.cc-report-head {
  display: flex;
  align-items: center;
  gap: 12px;
}

.cc-report-head .cc-muted { font-size: 14px; }

.cc-badge {
  font-family: var(--font-mono);
  font-size: 12px;
  letter-spacing: 0.08em;
  color: var(--color-body);
  padding: 2px 10px;
  border: 1px solid var(--color-border-pill);
  border-radius: var(--radius-pill);
}

.cc-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.cc-list .cc-row { padding: 14px 18px; }
.cc-list .cc-row-text { gap: 4px; }

.cc-divider {
  height: 1px;
  background: var(--color-hairline);
}

/* Single check */
.cc-check {
  display: flex;
  align-items: flex-start;
  gap: 10px;
}

.cc-input {
  flex: 1;
  height: 52px;
  box-sizing: border-box;
  padding: 0 18px;
  font-family: var(--font-display);
  font-size: 15px;
  color: var(--color-ink);
  background: var(--color-canvas-soft);
  border: 1px solid var(--color-hairline);
  border-radius: var(--radius-sm);
  outline: none;
}

.cc-input::placeholder { color: var(--color-mute); }
.cc-input:focus { border-color: var(--color-border-pill); }

.cc-error {
  margin: 0;
  font-family: var(--font-mono);
  font-size: 13px;
  color: #ff7a17;
}
</style>
