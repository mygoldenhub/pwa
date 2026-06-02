-- Initial schema for the Dreamflow PWA (Supabase)
--
-- Apply this using the Supabase module in Dreamflow.

create extension if not exists pgcrypto;

-- User profile table (1:1 with auth.users)
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  company_name text null,
  phone_number text null,
  xero_account_id text null,
  -- BCrypt hash produced by pgcrypto. Never store raw PINs.
  pin_hash text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_users_email_unique on public.users (lower(email));

-- Stores Xero OAuth2 tokens used by Edge Functions.
--
-- NOTE:
-- This project currently stores ONE shared Xero connection in this table
-- (no per-user linkage). Edge Functions always read the most recent row.
--
-- Required by xero_sync_products:
-- - refresh_token (rotates)
-- - tenant_id (optional if you set XERO_TENANT_ID secret instead)
create table if not exists public.xero_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id text null,
  tenant_name text null,
  access_token text null,
  refresh_token text not null,
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_xero_tokens_created_at on public.xero_tokens (created_at desc);

-- Functions to set/verify PIN for the authenticated user.
-- These run as SECURITY DEFINER so they can update even with strict RLS,
-- but they still only ever touch the row for auth.uid().

create or replace function public.set_user_pin(pin_input text)
returns void
language plpgsql
security definer
as $$
begin
  if pin_input is null or pin_input !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  update public.users
  set pin_hash = crypt(pin_input, gen_salt('bf')),
      updated_at = now()
  where id = auth.uid();

  if not found then
    raise exception 'Profile row not found for current user';
  end if;
end;
$$;

create or replace function public.verify_user_pin(pin_input text)
returns boolean
language plpgsql
security definer
as $$
declare
  stored_hash text;
begin
  if pin_input is null or pin_input !~ '^[0-9]{4}$' then
    return false;
  end if;

  select u.pin_hash into stored_hash
  from public.users u
  where u.id = auth.uid();

  if stored_hash is null then
    return false;
  end if;

  return stored_hash = crypt(pin_input, stored_hash);
end;
$$;

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

-- Xero Product & Services (Items) cache
-- Synced hourly by the xero_sync_products edge function.
create table if not exists public.xero_products (
  xero_item_id text primary key,
  code text null,
  name text null,
  sale_price_cents integer null,
  sales_account text null,
  tax_rate text null,
  description text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_xero_products_code_unique
on public.xero_products (code)
where code is not null;

create index if not exists idx_xero_products_updated_at
on public.xero_products (updated_at desc);
