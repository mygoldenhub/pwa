-- Account approval: users.status
--   1 = allowed to log in
--   0 = waiting for / denied access (an admin must set it to 1)
--
-- Run this in the Supabase SQL editor after 0006_admin_access.sql.
-- Existing users are set to 1 so nobody who already has an account is locked out.
-- New sign-ups get 0 and must be approved in the admin dashboard.

alter table if exists public.users
  add column if not exists status smallint;

-- Approve everyone who already exists (also covers a status column added by hand).
update public.users set status = 1 where status is null;

-- Admins must always be able to log in.
update public.users set status = 1 where role = 1;

alter table public.users alter column status set default 0;
alter table public.users alter column status set not null;

alter table public.users drop constraint if exists users_status_check;
alter table public.users
  add constraint users_status_check check (status in (0, 1));

-- Signed-in non-admins cannot approve themselves: on insert status is forced to 0,
-- on update it keeps its old value. The SQL editor, service-role jobs and admins are unaffected.
create or replace function public.users_protect_status()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.status := 0;
    else
      new.status := old.status;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists users_protect_status on public.users;
create trigger users_protect_status
before insert or update on public.users
for each row
execute function public.users_protect_status();
