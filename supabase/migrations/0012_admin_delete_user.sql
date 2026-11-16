-- Lets admins remove another user's account (login + profile).
-- Run this in the Supabase SQL editor after 0006_admin_access.sql.
--
-- Deletes the public.users row first, then the login (auth.users). The order matters: in the live
-- database users_id_fkey (public.users.id -> auth.users.id) is NOT "on delete cascade", so deleting
-- the login first fails. Both deletes run in one transaction: if either fails, nothing is deleted.
-- cart_items cascade from auth.users; announcements.created_by is set to null.
-- The app calls Make (to remove the account in Xero) before calling this function.

create or replace function public.admin_delete_user(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  removed_profile boolean;
  removed_login boolean;
begin
  if not public.is_admin() then
    raise exception 'Only admins can remove accounts.' using errcode = '42501';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'You cannot remove your own account.' using errcode = '42501';
  end if;

  -- 1) Profile row first (it references auth.users).
  delete from public.users where id = target_user_id;
  removed_profile := found;

  -- 2) Then the login, so they can't sign in again.
  delete from auth.users where id = target_user_id;
  removed_login := found;

  if not removed_profile and not removed_login then
    raise exception 'User not found.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.admin_delete_user(uuid) from public;
revoke all on function public.admin_delete_user(uuid) from anon;
grant execute on function public.admin_delete_user(uuid) to authenticated;
