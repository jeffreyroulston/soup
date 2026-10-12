/** HTML for Soup device-link browser pages, styled like the Soup web sign-in. */

export function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

type PageKind = "form" | "success" | "error" | "info";

type PageOptions = {
  title: string;
  eyebrow?: string;
  heading: string;
  bodyHtml: string;
  kind?: PageKind;
  status?: number;
};

const CSS = /* css */ `
:root {
  color-scheme: dark;
  --canvas: #0a0a0b;
  --surface: #1c1c1e;
  --elevated: #2c2c2e;
  --ink: #f5f5f7;
  --ink-2: #d2d2d7;
  --muted: #a1a1a6;
  --accent: #fc7814;
  --ok: #30d158;
  --radius-btn: 12px;
}
* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  min-height: 100%;
  font-family: Manrope, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
  font-size: 15px;
  line-height: 1.6;
  color: var(--ink);
  -webkit-font-smoothing: antialiased;
  background:
    radial-gradient(80% 60% at 85% -10%, rgb(252 120 20 / 0.16), transparent 60%),
    radial-gradient(70% 55% at 0% 110%, rgb(255 255 255 / 0.07), transparent 60%),
    var(--canvas);
}
.shell {
  min-height: 100%;
  display: grid;
  place-items: center;
  padding: 4rem 1rem;
}
.card {
  display: flex;
  flex-direction: column;
  gap: 20px;
  width: min(460px, 100%);
  padding: 32px;
  background: rgb(30 30 32 / 0.82);
  border: 1px solid rgb(255 255 255 / 0.1);
  border-radius: 28px;
  box-shadow: 0 40px 80px rgb(0 0 0 / 0.5);
  backdrop-filter: blur(40px);
  -webkit-backdrop-filter: blur(40px);
}
@media (min-width: 640px) { .card { padding: 44px; } }
.brand {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 1rem;
}
.brand-mark {
  margin: 0;
  font-size: 30px;
  font-weight: 800;
  line-height: 1;
  letter-spacing: -1.2px;
}
.brand-tag {
  font-size: 13px;
  font-weight: 700;
  color: var(--muted);
}
.heading { display: flex; flex-direction: column; gap: 10px; }
.eyebrow {
  margin: 0;
  font-size: 13px;
  font-weight: 800;
  letter-spacing: 0.6px;
  text-transform: uppercase;
  color: var(--muted);
}
h1 {
  margin: 0;
  font-size: 38px;
  font-weight: 800;
  line-height: 1.05;
  letter-spacing: -0.04em;
}
.lead { margin: 0; color: var(--ink-2); }
.lead strong, .lead code { color: var(--ink); }
.user-code {
  display: flex;
  gap: 8px;
  margin: 0;
}
.user-code span {
  display: grid;
  place-items: center;
  flex: 1;
  min-width: 0;
  height: 68px;
  border-radius: var(--radius-btn);
  background: rgb(255 255 255 / 0.1);
  font-size: clamp(1.5rem, 7vw, 2.25rem);
  font-weight: 800;
}
.user-code span.sep {
  flex: none;
  padding: 0 2px;
  background: none;
  color: var(--muted);
}
form { display: flex; flex-direction: column; gap: 16px; margin: 0; }
label {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 13px;
  font-weight: 700;
  color: var(--muted);
}
input {
  width: 100%;
  height: 48px;
  padding: 0 16px;
  font: inherit;
  font-size: 16px;
  font-weight: 600;
  color: var(--ink);
  background: rgb(255 255 255 / 0.1);
  border: 0;
  border-radius: var(--radius-btn);
  outline: none;
}
input::placeholder { color: rgb(161 161 166 / 0.7); }
input:focus { background: rgb(255 255 255 / 0.15); }
input:focus-visible { box-shadow: 0 0 0 2px var(--ink); }
button, .btn {
  appearance: none;
  display: inline-flex;
  justify-content: center;
  align-items: center;
  width: 100%;
  height: 52px;
  margin-top: 4px;
  padding: 0 1rem;
  font: inherit;
  font-size: 17px;
  font-weight: 800;
  text-decoration: none;
  color: var(--canvas);
  background: var(--ink);
  border: 0;
  border-radius: var(--radius-btn);
  cursor: pointer;
  transition: background-color 150ms;
}
button:hover, .btn:hover { background: rgb(245 245 247 / 0.8); }
:focus-visible {
  outline: 3px solid var(--ink);
  outline-offset: 3px;
}
.note {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--muted);
}
code, .mono {
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 0.9em;
}
.status {
  align-self: flex-start;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px 4px 10px;
  font-size: 13px;
  font-weight: 700;
  border-radius: 999px;
  background: rgb(255 255 255 / 0.1);
  color: var(--ink-2);
}
.status::before {
  content: "";
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: currentColor;
}
.status-success { color: var(--ok); background: rgb(48 209 88 / 0.14); }
.status-error { color: var(--accent); background: rgb(252 120 20 / 0.14); }
.status-info { color: var(--ink-2); }
pre.tokens {
  margin: 0;
  max-height: 14rem;
  overflow: auto;
  padding: 12px;
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 12px;
  line-height: 1.4;
  background: rgb(255 255 255 / 0.06);
  border-radius: var(--radius-btn);
  white-space: pre-wrap;
  word-break: break-all;
}
.providers { display: flex; flex-direction: column; gap: 10px; }
.providers button { gap: 12px; margin-top: 0; }
.providers svg { flex: none; width: 20px; height: 20px; }
.btn-secondary { color: var(--ink); background: rgb(255 255 255 / 0.1); }
.btn-secondary:hover { background: rgb(255 255 255 / 0.15); }
.note-error { color: var(--accent); }
@media (prefers-reduced-motion: reduce) {
  button, .btn { transition: none; }
}
`;

/** One tile per character like the web sign-in; dashes become a quiet separator. */
function userCodeTiles(code: string): string {
  const tiles = [...code]
    .map((char) =>
      char === "-"
        ? `<span class="sep" aria-hidden="true">-</span>`
        : `<span aria-hidden="true">${escapeHtml(char)}</span>`,
    )
    .join("");
  return `<div class="user-code" role="img" aria-label="Code ${escapeHtml(code)}">${tiles}</div>`;
}

export function deviceLinkPage(options: PageOptions): string {
  const kind = options.kind ?? "info";
  const statusLabel =
    kind === "success" ? "Linked" : kind === "error" ? "Needs attention" : kind === "form" ? "Device link" : "Soup identity";
  const statusClass =
    kind === "success" ? "status-success" : kind === "error" ? "status-error" : "status-info";
  const eyebrow = options.eyebrow
    ? `<p class="eyebrow">${escapeHtml(options.eyebrow)}</p>`
    : "";

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="dark" />
  <meta name="theme-color" content="#0a0a0b" />
  <title>${escapeHtml(options.title)}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;600;700;800&display=swap" rel="stylesheet" />
  <style>${CSS}</style>
</head>
<body>
  <main class="shell">
    <section class="card" aria-labelledby="page-heading">
      <header class="brand">
        <p class="brand-mark">soup</p>
        <span class="brand-tag">Identity</span>
      </header>
      <span class="status ${statusClass}">${escapeHtml(statusLabel)}</span>
      <div class="heading">
        ${eyebrow}
        <h1 id="page-heading">${escapeHtml(options.heading)}</h1>
      </div>
      ${options.bodyHtml}
    </section>
  </main>
</body>
</html>`;
}

export function deviceLinkDevForm(opts: {
  userCode: string;
  emailPlaceholder: string;
}): string {
  const codeBlock = opts.userCode
    ? userCodeTiles(opts.userCode)
    : "";
  return deviceLinkPage({
    title: "Soup · Link device",
    kind: "form",
    eyebrow: "Dev sign-in",
    heading: "Link this TV",
    bodyHtml: `
${codeBlock}
<form method="POST" action="/auth/dev/complete">
  <label>User code
    <input name="user_code" value="${escapeHtml(opts.userCode)}" autocomplete="one-time-code" required />
  </label>
  <label>Google email
    <input name="email" type="email" placeholder="${escapeHtml(opts.emailPlaceholder)}" />
  </label>
  <button type="submit">Approve device</button>
</form>
<p class="note">Leave email blank to use <code>DEV_GOOGLE_EMAIL</code> (${escapeHtml(opts.emailPlaceholder)}).</p>`,
  });
}

export function deviceLinkSuccess(opts: {
  heading: string;
  messageHtml: string;
  eyebrow?: string;
}): string {
  return deviceLinkPage({
    title: "Soup · Linked",
    kind: "success",
    eyebrow: opts.eyebrow ?? "You’re done",
    heading: opts.heading,
    bodyHtml: `<p class="lead">${opts.messageHtml}</p>
<p class="note">You can close this tab and return to Soup on the TV.</p>`,
  });
}

export function deviceLinkError(opts: {
  heading: string;
  messageHtml: string;
  eyebrow?: string;
}): string {
  return deviceLinkPage({
    title: "Soup · Device link",
    kind: "error",
    eyebrow: opts.eyebrow ?? "Couldn’t finish",
    heading: opts.heading,
    bodyHtml: `<p class="lead">${opts.messageHtml}</p>
<p class="note">Start again from the Soup app if the code expired.</p>`,
  });
}

/** Brand marks for known providers; unknown ids render a plain button. */
const PROVIDER_ICONS: Record<string, string> = {
  google: `<svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C36.9 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>`,
};

/** Entry page (/link): enter the TV code, then pick a sign-in method. */
export function deviceLinkStart(opts: {
  userCode: string;
  providers: { id: string; label: string }[];
  errorHtml?: string;
}): string {
  const codeBlock = opts.userCode && !opts.errorHtml ? userCodeTiles(opts.userCode) : "";
  const note = opts.errorHtml
    ? `<p class="note note-error" role="alert">${opts.errorHtml}</p>`
    : "";
  const buttons = opts.providers
    .map(
      (p, i) =>
        `<button type="submit" name="provider" value="${escapeHtml(p.id)}"${i > 0 ? ` class="btn-secondary"` : ""}>${PROVIDER_ICONS[p.id] ?? ""}${escapeHtml(p.label)}</button>`,
    )
    .join("\n    ");
  const actions = opts.providers.length
    ? `<div class="providers">
    ${buttons}
  </div>`
    : `<p class="note note-error" role="alert">No sign-in methods are configured on this server.</p>`;
  return deviceLinkPage({
    title: "Soup · Link device",
    kind: "form",
    eyebrow: "Link a device",
    heading: "Sign in to Soup",
    bodyHtml: `
<p class="lead">Enter the code shown on your TV, then sign in to link it to your account.</p>
${codeBlock}
<form method="POST" action="/link">
  <label>TV code
    <input name="user_code" value="${escapeHtml(opts.userCode)}" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false" required placeholder="ABCD-EFGH" />
  </label>
  ${note}
  ${actions}
</form>`,
  });
}

/** After Google SSO: collect the TV user code (no token dump). */
export function deviceLinkEnterCode(opts: {
  identity: string;
  linkToken: string;
  prefillUserCode?: string;
  noteHtml?: string;
}): string {
  const prefill = opts.prefillUserCode ?? "";
  const note =
    opts.noteHtml ??
    "Type the code shown on your TV (or scan the QR again with a fresh code).";
  return deviceLinkPage({
    title: "Soup · Enter TV code",
    kind: "form",
    eyebrow: "Almost there",
    heading: "Enter your TV code",
    bodyHtml: `
<p class="lead">Signed in as <strong>${escapeHtml(opts.identity)}</strong>. Finish linking with the code on your TV.</p>
<form method="POST" action="/auth/google/link-device">
  <input type="hidden" name="link_token" value="${escapeHtml(opts.linkToken)}" />
  <label>TV code
    <input name="user_code" value="${escapeHtml(prefill)}" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false" required placeholder="ABCD-EFGH" />
  </label>
  <button type="submit">Link TV</button>
</form>
<p class="note">${note}</p>`,
  });
}
