-- A user can remove a broadcast from their own notification list.
-- The announcement stays available to everyone else and to the admin dashboard.

create table if not exists public.announcement_dismissals (
  user_id uuid not null references public.users (id) on delete cascade,
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  dismissed_at timestamptz not null default now(),
  primary key (user_id, announcement_id)
);

create index if not exists announcement_dismissals_announcement_idx
  on public.announcement_dismissals (announcement_id);

alter table public.announcement_dismissals enable row level security;

drop policy if exists "announcement_dismissals_select_own" on public.announcement_dismissals;
create policy "announcement_dismissals_select_own"
on public.announcement_dismissals
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "announcement_dismissals_insert_own" on public.announcement_dismissals;
create policy "announcement_dismissals_insert_own"
on public.announcement_dismissals
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "announcement_dismissals_delete_own" on public.announcement_dismissals;
create policy "announcement_dismissals_delete_own"
on public.announcement_dismissals
for delete
to authenticated
using (user_id = auth.uid());

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'announcement_dismissals'
    ) then
      execute 'alter publication supabase_realtime add table public.announcement_dismissals';
    end if;
  end if;
end $$;
