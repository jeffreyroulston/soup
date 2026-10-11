import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "./auth.js";

type Bucket = { count: number; resetAt: number };

/**
 * Simple per-IP rate limiter (in-memory). Fine for a single Node/PM2 process;
 * multi-instance deploys need a shared store.
 */
export function rateLimit(opts: {
  windowMs: number;
  max: number;
}): MiddlewareHandler<AppEnv> {
  const buckets = new Map<string, Bucket>();

  return async (c, next) => {
    const forwarded = c.req.header("x-forwarded-for");
    const ip =
      forwarded?.split(",")[0]?.trim() ||
      c.req.header("x-real-ip") ||
      "unknown";
    const now = Date.now();
    let bucket = buckets.get(ip);
    if (!bucket || bucket.resetAt <= now) {
      bucket = { count: 0, resetAt: now + opts.windowMs };
      buckets.set(ip, bucket);
    }
    bucket.count += 1;
    if (bucket.count > opts.max) {
      const retryAfter = Math.max(1, Math.ceil((bucket.resetAt - now) / 1000));
      c.header("Retry-After", String(retryAfter));
      return c.json(
        { error: "rate_limited", message: "Too many requests" },
        429,
      );
    }
    // Opportunistic cleanup of stale buckets
    if (buckets.size > 10_000) {
      for (const [key, value] of buckets) {
        if (value.resetAt <= now) buckets.delete(key);
      }
    }
    await next();
  };
}
