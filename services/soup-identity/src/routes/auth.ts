import { Hono } from "hono";
import type { Env } from "../env.js";
import type { Db } from "../db/client.js";
import {
  signDeviceLinkProof,
  signOAuthState,
  verifyDeviceLinkProof,
  verifyOAuthState,
  type SigningKeys,
} from "../lib/crypto.js";
import type { AppEnv } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rate_limit.js";
import { linkProviders } from "../auth/link_providers.js";
import {
  approveDeviceLink,
  checkDeviceLinkCode,
  exchangeGoogleCode,
  googleAuthUrl,
  isValidEmail,
  normalizeEmail,
  normalizeUserCode,
  parseDeviceInfo,
  pollDeviceLink,
  refreshSession,
  revokeSession,
  startDeviceLink,
  upsertSubject,
} from "../auth/sessions.js";
import {
  deviceLinkDevForm,
  deviceLinkEnterCode,
  deviceLinkError,
  deviceLinkStart,
  deviceLinkSuccess,
  escapeHtml,
} from "../lib/device_link_html.js";

export function buildAuthRoutes(deps: {
  db: Db;
  env: Env;
  keys: SigningKeys;
}) {
  const app = new Hono<AppEnv>();

  async function renderEnterCode(opts: {
    email: string;
    googleSub?: string | null;
    name?: string | null;
    prefillUserCode?: string;
    noteHtml?: string;
  }) {
    const linkToken = await signDeviceLinkProof(deps.keys, deps.env, {
      email: opts.email,
      googleSub: opts.googleSub,
      name: opts.name,
    });
    return deviceLinkEnterCode({
      identity: opts.email,
      linkToken,
      prefillUserCode: opts.prefillUserCode,
      noteHtml: opts.noteHtml,
    });
  }

  // Public device-link / session endpoints — per-IP limits (in-memory; single process).
  const linkStartLimit = rateLimit({ windowMs: 60_000, max: 20 });
  const linkPollLimit = rateLimit({ windowMs: 60_000, max: 120 });
  const linkApproveLimit = rateLimit({ windowMs: 60_000, max: 30 });
  const refreshLimit = rateLimit({ windowMs: 60_000, max: 60 });
  // /link answers "is this code live?", so keep guessing slow.
  const linkPageLimit = rateLimit({ windowMs: 60_000, max: 30 });

  /** Render /link, validating the code when one was supplied. */
  async function renderLinkPage(rawUserCode: string, providerError?: string) {
    const providers = linkProviders(deps.env);
    const userCode = rawUserCode ? normalizeUserCode(rawUserCode) : "";
    let errorHtml = providerError;
    let device: { name: string | null; platform: string | null } | undefined;
    if (userCode && !errorHtml) {
      const check = await checkDeviceLinkCode(deps.db, userCode);
      if (!check.ok) {
        errorHtml =
          check.reason === "not_found"
            ? "That code wasn’t found. Check the TV and try again."
            : "That code has expired or was already used. Get a new code on the TV.";
      } else {
        device = { name: check.deviceName, platform: check.platform };
      }
    }
    const status = !providers.length ? 503 : errorHtml ? 400 : 200;
    return {
      html: deviceLinkStart({ userCode, providers, errorHtml, device }),
      status: status as 200 | 400 | 503,
      ok: status === 200,
      userCode,
      providers,
    };
  }

  // Browser entry point the TV QR points at: enter code, pick a sign-in method.
  app.get("/link", linkPageLimit, async (c) => {
    const page = await renderLinkPage(c.req.query("user_code")?.trim() ?? "");
    return c.html(page.html, page.status);
  });

  app.post("/link", linkPageLimit, async (c) => {
    const form = await c.req.parseBody();
    const rawUserCode = String(form.user_code ?? "").trim();
    const providerId = String(form.provider ?? "");
    const provider = linkProviders(deps.env).find((p) => p.id === providerId);
    if (!rawUserCode) {
      const page = await renderLinkPage("", "Enter the code shown on your TV.");
      return c.html(page.html, 400);
    }
    const page = await renderLinkPage(
      rawUserCode,
      provider ? undefined : "Choose a sign-in method.",
    );
    if (!page.ok || !provider) return c.html(page.html, page.status);
    return c.redirect(provider.startPath(page.userCode), 303);
  });

  app.post("/auth/device/link", linkStartLimit, async (c) => {
    // The body is optional: older clients start a link without describing themselves.
    const body = await c.req.json().catch(() => null);
    const started = await startDeviceLink(deps.db, deps.env, parseDeviceInfo(body));
    return c.json(started);
  });

  app.get("/auth/device/link/:deviceCode", linkPollLimit, async (c) => {
    const result = await pollDeviceLink(
      deps.db,
      deps.keys,
      deps.env,
      c.req.param("deviceCode"),
    );
    if (result.kind === "missing") {
      return c.json({ error: "not_found", message: "Unknown device code" }, 404);
    }
    if (result.kind === "pending") return c.json({ status: "pending" });
    if (result.kind === "expired") return c.json({ status: "expired" });
    return c.json({ status: "approved", ...result.tokens });
  });

  app.post("/auth/device/approve", linkApproveLimit, async (c) => {
    const body = await c.req.json<{
      user_code: string;
      link_token: string;
    }>();
    if (!body.user_code || !body.link_token) {
      return c.json(
        { error: "bad_request", message: "user_code and link_token required" },
        400,
      );
    }
    let proof: Awaited<ReturnType<typeof verifyDeviceLinkProof>>;
    try {
      proof = await verifyDeviceLinkProof(deps.keys, deps.env, body.link_token);
    } catch {
      return c.json(
        { error: "unauthorized", message: "Invalid or expired link_token" },
        401,
      );
    }
    const result = await approveDeviceLink(deps.db, {
      userCode: body.user_code,
      email: proof.email,
      googleSub: proof.googleSub,
      name: proof.name,
    });
    if (!result.ok && result.reason === "not_found") {
      return c.json({ error: "not_found", message: "Unknown user code" }, 404);
    }
    if (!result.ok) {
      return c.json({ error: "bad_request", message: "Code invalid or expired" }, 400);
    }
    return c.json({ status: "approved", email: result.email });
  });

  app.get("/auth/google/start", async (c) => {
    const userCode = c.req.query("user_code") ?? undefined;
    if (deps.env.googleConfigured) {
      const state = await signOAuthState(deps.keys, deps.env, userCode);
      return c.redirect(googleAuthUrl(deps.env, state), 302);
    }
    if (!deps.env.ALLOW_DEV_LOGIN) {
      return c.json(
        {
          error: "unavailable",
          message: "Google OIDC not configured and ALLOW_DEV_LOGIN is false",
        },
        503,
      );
    }
    return c.html(
      deviceLinkDevForm({
        userCode: userCode ?? "",
        emailPlaceholder: deps.env.DEV_GOOGLE_EMAIL,
      }),
    );
  });

  app.get("/auth/google/callback", async (c) => {
    const err = c.req.query("error");
    if (err) {
      return c.html(
        deviceLinkError({
          heading: "Google sign-in failed",
          messageHtml: `Google returned <code class="mono">${escapeHtml(err)}</code>.`,
        }),
        400,
      );
    }
    const code = c.req.query("code");
    const state = c.req.query("state") ?? "";
    if (!code) {
      return c.html(
        deviceLinkError({
          heading: "Missing code",
          messageHtml: "Google did not return an authorization code.",
        }),
        400,
      );
    }
    let oauthState: { user_code: string | null };
    try {
      oauthState = await verifyOAuthState(deps.keys, deps.env, state);
    } catch {
      return c.html(
        deviceLinkError({
          heading: "Invalid sign-in state",
          messageHtml:
            "This Google callback could not be verified. Open the link from the Soup app and try again.",
        }),
        400,
      );
    }
    if (!deps.env.googleConfigured) {
      return c.html(
        deviceLinkError({
          heading: "Google not configured",
          messageHtml: "This identity server has no Google OIDC client configured.",
        }),
        400,
      );
    }
    try {
      const profile = await exchangeGoogleCode(deps.env, code);
      await upsertSubject(deps.db, {
        email: profile.email,
        googleSub: profile.sub,
        name: profile.name,
        pictureUrl: profile.picture,
      });
      const { user_code } = oauthState;
      if (user_code) {
        const approved = await approveDeviceLink(deps.db, {
          userCode: user_code,
          email: profile.email,
          googleSub: profile.sub,
          name: profile.name,
        });
        if (approved.ok) {
          return c.html(
            deviceLinkSuccess({
              heading: "Device linked",
              messageHtml: `Linked <strong>${escapeHtml(profile.email)}</strong> to the Soup device.`,
            }),
          );
        }
        return c.html(
          await renderEnterCode({
            email: profile.email,
            googleSub: profile.sub,
            name: profile.name,
            noteHtml:
              "That TV code was invalid or expired. Enter a fresh code from the Soup app.",
          }),
          400,
        );
      }
      return c.html(
        await renderEnterCode({
          email: profile.email,
          googleSub: profile.sub,
          name: profile.name,
        }),
      );
    } catch (e) {
      const message = e instanceof Error ? e.message : "oauth_failed";
      return c.html(
        deviceLinkError({
          heading: "Sign-in failed",
          messageHtml: escapeHtml(message),
        }),
        400,
      );
    }
  });

  app.post("/auth/google/link-device", async (c) => {
    const form = await c.req.parseBody();
    const linkToken = String(form.link_token ?? "");
    const userCode = String(form.user_code ?? "").trim();
    if (!linkToken || !userCode) {
      return c.html(
        deviceLinkError({
          heading: "Missing code",
          messageHtml: "TV code and Google sign-in proof are required.",
        }),
        400,
      );
    }
    let proof: Awaited<ReturnType<typeof verifyDeviceLinkProof>>;
    try {
      proof = await verifyDeviceLinkProof(deps.keys, deps.env, linkToken);
    } catch {
      return c.html(
        deviceLinkError({
          heading: "Sign-in expired",
          messageHtml:
            "Your Google sign-in proof expired. Open the link from the TV again and sign in.",
        }),
        400,
      );
    }

    await upsertSubject(deps.db, {
      email: proof.email,
      googleSub: proof.googleSub,
      name: proof.name,
    });

    const result = await approveDeviceLink(deps.db, {
      userCode,
      email: proof.email,
      googleSub: proof.googleSub,
      name: proof.name ?? undefined,
    });
    if (result.ok) {
      return c.html(
        deviceLinkSuccess({
          heading: "Device linked",
          messageHtml: `Linked <strong>${escapeHtml(proof.email)}</strong> to the Soup device.`,
        }),
      );
    }

    return c.html(
      await renderEnterCode({
        email: proof.email,
        googleSub: proof.googleSub,
        name: proof.name,
        prefillUserCode: userCode,
        noteHtml:
          result.reason === "not_found"
            ? "That code was not found. Check the TV and try again."
            : "That code is invalid or expired. Get a new code on the TV.",
      }),
      400,
    );
  });

  app.get("/auth/dev/start", (c) => {
    if (!deps.env.ALLOW_DEV_LOGIN) {
      return c.json({ error: "forbidden", message: "Dev login disabled" }, 403);
    }
    return c.html(
      deviceLinkDevForm({
        userCode: c.req.query("user_code") ?? "",
        emailPlaceholder: deps.env.DEV_GOOGLE_EMAIL,
      }),
    );
  });

  app.post("/auth/dev/complete", linkApproveLimit, async (c) => {
    if (!deps.env.ALLOW_DEV_LOGIN) {
      return c.json({ error: "forbidden", message: "Dev login disabled" }, 403);
    }
    const contentType = c.req.header("content-type") ?? "";
    let userCode: string;
    let email: string | undefined;
    if (contentType.includes("application/json")) {
      const body = await c.req.json<{
        user_code: string;
        email?: string;
      }>();
      userCode = body.user_code;
      email = body.email;
    } else {
      const form = await c.req.parseBody();
      userCode = String(form.user_code ?? "");
      email = form.email ? String(form.email) : undefined;
    }
    if (!userCode) {
      return c.json({ error: "bad_request", message: "user_code required" }, 400);
    }
    const mail = normalizeEmail(email || deps.env.DEV_GOOGLE_EMAIL);
    if (!isValidEmail(mail)) {
      return c.json({ error: "bad_request", message: "email required" }, 400);
    }
    const result = await approveDeviceLink(deps.db, {
      userCode,
      email: mail,
      name: "Dev User",
    });
    if (!result.ok && result.reason === "not_found") {
      return c.html(
        deviceLinkError({
          heading: "Unknown code",
          messageHtml: "That user code was not found. Check the TV screen and try again.",
        }),
        404,
      );
    }
    if (!result.ok) {
      return c.html(
        deviceLinkError({
          heading: "Code expired",
          messageHtml: "This user code is invalid or has expired.",
        }),
        400,
      );
    }
    if (contentType.includes("application/json")) {
      return c.json({ status: "approved", email: mail });
    }
    return c.html(
      deviceLinkSuccess({
        heading: "Device approved",
        messageHtml: `Approved for <code class="mono">${escapeHtml(mail)}</code>. Return to the Soup app.`,
      }),
    );
  });

  app.post("/v1/sessions/refresh", refreshLimit, async (c) => {
    const body = await c.req.json<{ refresh_token: string }>();
    if (!body.refresh_token) {
      return c.json({ error: "bad_request", message: "refresh_token required" }, 400);
    }
    const tokens = await refreshSession(
      deps.db,
      deps.keys,
      deps.env,
      body.refresh_token,
    );
    if (!tokens) {
      return c.json({ error: "unauthorized", message: "Invalid refresh token" }, 401);
    }
    return c.json(tokens);
  });

  app.post("/v1/sessions/revoke", async (c) => {
    const body = await c.req.json<{ refresh_token: string }>();
    if (!body.refresh_token) {
      return c.json({ error: "bad_request", message: "refresh_token required" }, 400);
    }
    await revokeSession(deps.db, body.refresh_token);
    return c.body(null, 204);
  });

  return app;
}
