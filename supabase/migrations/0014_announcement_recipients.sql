-- Targeted broadcasts. Null or empty recipient_ids means everyone.
-- A non-empty list is visible only to those users and to admins.

alter table public.announcements
  add column if not exists recipient_ids uuid[] null;

drop policy if exists "announcements_select_authenticated" on public.announcements;
create policy "announcements_select_authenticated"
on public.announcements
for select
to authenticated
using (
  public.is_admin()
  or recipient_ids is null
  or cardinality(recipient_ids) = 0
  or auth.uid() = any (recipient_ids)
);
