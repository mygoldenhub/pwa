-- Store password reset verification codes on the user profile row.
-- This avoids needing a separate `password_reset_codes` table.

alter table if exists public.users
  add column if not exists reset_code_hash text;

alter table if exists public.users
  add column if not exists reset_code_expires_at timestamptz;

-- The app uses a 4-digit PIN. Many setups store a hash in `pin_hash`.
-- If your project already has `pin_hash`, this statement is a no-op.
alter table if exists public.users
  add column if not exists pin_hash text;

-- Ensure updated_at exists for consistent writes.
alter table if exists public.users
  add column if not exists updated_at timestamptz;
