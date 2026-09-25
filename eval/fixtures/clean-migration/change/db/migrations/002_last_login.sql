-- Nullable: existing rows have no login recorded yet.
ALTER TABLE users ADD COLUMN last_login_at timestamptz;
