-- Password reset codes storage (used by Edge Function reset_password_code)

create extension if not exists pgcrypto;

create table if not exists public.password_reset_codes (
  email text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.password_reset_codes enable row level security;

-- No public RLS policies on purpose. Only service-role (Edge Functions) should access.
