-- Lets admins reset ("format") another user's login password to the default 12345678.
-- Run this in the Supabase SQL editor after 0006_admin_access.sql.
--
-- The default password is fixed here, not passed from the app, so this function
-- cannot be used to set an arbitrary password.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.admin_format_user_password(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can format passwords.' using errcode = '42501';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'You cannot format your own password here.' using errcode = '42501';
  end if;

  -- Supabase Auth stores bcrypt hashes, which pgcrypto's bf salt produces.
  update auth.users
  set encrypted_password = extensions.crypt('12345678', extensions.gen_salt('bf')),
      updated_at = now()
  where id = target_user_id;

  if not found then
    raise exception 'User not found.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.admin_format_user_password(uuid) from public;
revoke all on function public.admin_format_user_password(uuid) from anon;
grant execute on function public.admin_format_user_password(uuid) to authenticated;
