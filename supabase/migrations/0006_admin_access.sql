-- Let role = 1 users manage the admin dashboard.
-- Regular users cannot grant themselves admin.

alter table if exists public.users
  add column if not exists role integer not null default 0;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users
    where id = auth.uid()
      and role = 1
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "users_select_admin" on public.users;
create policy "users_select_admin"
on public.users
for select
to authenticated
using (public.is_admin());

drop policy if exists "users_update_admin" on public.users;
create policy "users_update_admin"
on public.users
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.users_protect_role()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- SQL editor and service-role jobs have no auth.uid(). Signed-in non-admins cannot change role.
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.role := 0;
    else
      new.role := old.role;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists users_protect_role on public.users;
create trigger users_protect_role
before insert or update on public.users
for each row
execute function public.users_protect_role();

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  created_by uuid null references public.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists announcements_created_at_idx
  on public.announcements (created_at desc);

alter table public.announcements enable row level security;

drop policy if exists "announcements_select_authenticated" on public.announcements;
create policy "announcements_select_authenticated"
on public.announcements
for select
to authenticated
using (true);

drop policy if exists "announcements_insert_admin" on public.announcements;
create policy "announcements_insert_admin"
on public.announcements
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "announcements_delete_admin" on public.announcements;
create policy "announcements_delete_admin"
on public.announcements
for delete
to authenticated
using (public.is_admin());

do $$
begin
  if to_regclass('public.invoice') is not null then
    execute 'drop policy if exists "invoice_select_admin" on public.invoice';
    execute 'create policy "invoice_select_admin" on public.invoice for select to authenticated using (public.is_admin())';
  end if;

  if to_regclass('public.xero_invoices') is not null then
    execute 'drop policy if exists "xero_invoices_select_admin" on public.xero_invoices';
    execute 'create policy "xero_invoices_select_admin" on public.xero_invoices for select to authenticated using (public.is_admin())';
  end if;

  if to_regclass('public.xero_contacts') is not null then
    execute 'drop policy if exists "xero_contacts_select_admin" on public.xero_contacts';
    execute 'create policy "xero_contacts_select_admin" on public.xero_contacts for select to authenticated using (public.is_admin())';
  end if;
end $$;
