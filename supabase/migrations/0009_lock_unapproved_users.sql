-- Database-level lock for unapproved accounts (users.status = 0).
-- Run this in the Supabase SQL editor AFTER 0008_users_status.sql.
--
-- After this runs:
--   * A signed-in user with status <> 1 cannot read or write ANY table protected by RLS,
--     except their own row in public.users (needed so sign-up can save the profile and PIN).
--   * Admin rights also require status = 1.
--   * The app checks status through public.current_user_status(); without this
--     migration the app refuses every login (it fails closed).
--
-- Edge Functions that use the service role key bypass RLS and are not affected.

-- 1) Helpers. SECURITY DEFINER so they read users.status without being blocked by RLS.
create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and status = 1
  );
$$;

revoke all on function public.is_active_user() from public;
grant execute on function public.is_active_user() to authenticated;

-- Returns the caller's status, or null when they have no profile row. The app treats
-- anything other than 1 as "not allowed".
create or replace function public.current_user_status()
returns smallint
language sql
stable
security definer
set search_path = public
as $$
  select status from public.users where id = auth.uid();
$$;

revoke all on function public.current_user_status() from public;
grant execute on function public.current_user_status() to authenticated;

-- Admins must also be approved.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 1 and status = 1
  );
$$;

-- 2) public.users: unapproved users may only touch their own row
--    (users_protect_status from 0008 still stops them changing status).
drop policy if exists "users_active_or_own_row" on public.users;
create policy "users_active_or_own_row"
on public.users
as restrictive
for all
to authenticated
using (id = auth.uid() or public.is_active_user())
with check (id = auth.uid() or public.is_active_user());

-- 3) Every other RLS-enabled table in public: require an approved account.
--    RESTRICTIVE policies are ANDed with the existing ones, so current rules still apply on top.
do $$
declare
  t record;
begin
  for t in
    select c.relname as name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relrowsecurity
      and c.relname <> 'users'
  loop
    execute format('drop policy if exists "active_users_only" on public.%I', t.name);
    execute format(
      'create policy "active_users_only" on public.%I as restrictive for all to authenticated '
      'using (public.is_active_user()) with check (public.is_active_user())',
      t.name
    );
  end loop;

  -- Tables without RLS are open to every client and cannot be locked by policies.
  for t in
    select c.relname as name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
  loop
    raise notice 'Table public.% has RLS disabled, so it is NOT locked. Enable RLS and add policies if it holds private data.', t.name;
  end loop;
end $$;

-- 4) Signed-in users must not be able to bypass RLS through the catalogue clean-up function.
do $$
begin
  if to_regprocedure('public.clean_xero_products_gnt()') is not null then
    execute 'revoke execute on function public.clean_xero_products_gnt() from public, anon, authenticated';
    -- Its only caller is the xero-products-exception-data Edge Function (service role).
    execute 'grant execute on function public.clean_xero_products_gnt() to service_role';
  end if;
end $$;
