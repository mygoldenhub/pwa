-- Numeric role on the user profile. Typical value is 0.
alter table if exists public.users
  add column if not exists role integer not null default 0;
