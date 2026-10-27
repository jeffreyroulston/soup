-- Device metadata: the TV reports what it is when it starts a link, and the
-- session it ends up with keeps that so users can see and manage their devices.

ALTER TABLE device_links
  ADD COLUMN IF NOT EXISTS device_name TEXT,
  ADD COLUMN IF NOT EXISTS platform TEXT,
  ADD COLUMN IF NOT EXISTS client_version TEXT;

ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS platform TEXT,
  ADD COLUMN IF NOT EXISTS client_version TEXT;

-- Every session so far came from the device link and was named after it.
UPDATE sessions SET device_name = NULL WHERE device_name = 'device-link';

CREATE INDEX IF NOT EXISTS idx_sessions_active
  ON sessions(email, last_used_at DESC)
  WHERE revoked_at IS NULL;
