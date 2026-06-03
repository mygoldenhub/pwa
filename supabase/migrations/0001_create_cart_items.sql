-- Cart items table (per-user)
-- Run this in your Supabase SQL editor, or add as a migration in your Supabase workflow.

create table if not exists public.cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  xero_item_id text not null,
  product_name text not null,
  product_code text null,
  unit_price_cents integer null,
  quantity integer not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, xero_item_id)
);

create index if not exists cart_items_user_id_idx on public.cart_items (user_id);
create index if not exists cart_items_user_id_updated_at_idx on public.cart_items (user_id, updated_at desc);

-- Updated-at trigger
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at_on_cart_items on public.cart_items;
create trigger set_updated_at_on_cart_items
before update on public.cart_items
for each row
execute function public.set_updated_at();

-- RLS
alter table public.cart_items enable row level security;

drop policy if exists "cart_items_select_own" on public.cart_items;
create policy "cart_items_select_own"
on public.cart_items
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "cart_items_insert_own" on public.cart_items;
create policy "cart_items_insert_own"
on public.cart_items
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "cart_items_update_own" on public.cart_items;
create policy "cart_items_update_own"
on public.cart_items
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "cart_items_delete_own" on public.cart_items;
create policy "cart_items_delete_own"
on public.cart_items
for delete
to authenticated
using (user_id = auth.uid());
