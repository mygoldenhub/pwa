-- Initial schema for the Dreamflow PWA (Supabase)
--
-- Apply this using the Supabase module in Dreamflow.

create extension if not exists pgcrypto;

-- User profile table (1:1 with auth.users)
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_users_email_unique on public.users (lower(email));

-- Product catalog
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  barcode text null,
  stock_qty integer not null default 0,
  price_cents integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_products_updated_at on public.products (updated_at desc);
create index if not exists idx_products_barcode on public.products (barcode);
