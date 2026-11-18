-- Per-user read state for broadcast announcements (customer notification bell).
-- An announcement is unread for a user until a row exists here for (user, announcement).

create table if not exists public.announcement_reads (
  user_id uuid not null references public.users (id) on delete cascade,
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, announcement_id)
);

create index if not exists announcement_reads_announcement_idx
  on public.announcement_reads (announcement_id);

alter table public.announcement_reads enable row level security;

drop policy if exists "announcement_reads_select_own" on public.announcement_reads;
create policy "announcement_reads_select_own"
on public.announcement_reads
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "announcement_reads_insert_own" on public.announcement_reads;
create policy "announcement_reads_insert_own"
on public.announcement_reads
for insert
to authenticated
with check (user_id = auth.uid());

-- Upsert (on conflict do update) also needs an update policy.
drop policy if exists "announcement_reads_update_own" on public.announcement_reads;
create policy "announcement_reads_update_own"
on public.announcement_reads
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Realtime: lets the bell light up as soon as an admin publishes.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'announcements'
    ) then
      execute 'alter publication supabase_realtime add table public.announcements';
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'announcement_reads'
    ) then
      execute 'alter publication supabase_realtime add table public.announcement_reads';
    end if;
  end if;
end $$;
