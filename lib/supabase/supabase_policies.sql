-- Row Level Security policies for the Dreamflow PWA (Supabase)
--
-- Apply this using the Supabase module in Dreamflow.

alter table public.users enable row level security;
alter table public.products enable row level security;
alter table public.xero_tokens enable row level security;
alter table public.xero_products enable row level security;

-- USERS
drop policy if exists "users_select_own" on public.users;
create policy "users_select_own"
on public.users
for select
to authenticated
using (auth.uid() = id);

-- IMPORTANT: Per Dreamflow guideline, allow inserts/updates during signup.
-- (You can tighten this later to: WITH CHECK (auth.uid() = id))
drop policy if exists "users_insert_any" on public.users;
create policy "users_insert_any"
on public.users
for insert
to authenticated
with check (true);

drop policy if exists "users_update_any" on public.users;
create policy "users_update_any"
on public.users
for update
to authenticated
using (auth.uid() = id)
with check (true);

drop policy if exists "users_delete_own" on public.users;
create policy "users_delete_own"
on public.users
for delete
to authenticated
using (auth.uid() = id);

-- PRODUCTS (authenticated users can manage catalog for now)
drop policy if exists "products_all_authenticated" on public.products;
create policy "products_all_authenticated"
on public.products
for all
to authenticated
using (true)
with check (true);

-- XERO TOKENS
-- IMPORTANT: These rows contain OAuth tokens. We intentionally do NOT allow SELECT from clients.
-- Edge Functions use the service role key and bypass RLS.

-- We do not create client-facing insert/update/delete policies for xero_tokens.
-- Only Edge Functions (service role) should write to this table.
drop policy if exists "xero_tokens_insert_own" on public.xero_tokens;
drop policy if exists "xero_tokens_update_own" on public.xero_tokens;
drop policy if exists "xero_tokens_delete_own" on public.xero_tokens;

-- XERO PRODUCTS
-- Shared admin-managed integration: any signed-in user may read the synced catalog.
drop policy if exists "xero_products_read" on public.xero_products;
create policy "xero_products_read"
on public.xero_products
for select
to authenticated
using (true);
