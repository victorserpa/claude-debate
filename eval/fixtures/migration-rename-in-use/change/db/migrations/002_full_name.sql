-- Runs in the deploy, before the new code starts.
ALTER TABLE users RENAME COLUMN name TO full_name;
