-- First names shown on the user broadcast modal.
-- Empty or null means the announcement was posted to everyone.

alter table public.announcements
  add column if not exists recipient_names text[] null;

update public.announcements a
set recipient_names = sub.names
from (
  select
    a2.id,
    array_agg(
      split_part(
        coalesce(nullif(btrim(u.display_name), ''), split_part(u.email, '@', 1)),
        ' ',
        1
      )
      order by u.display_name
    ) as names
  from public.announcements a2
  join public.users u on u.id = any (a2.recipient_ids)
  where a2.recipient_ids is not null
    and cardinality(a2.recipient_ids) > 0
  group by a2.id
) sub
where a.id = sub.id
  and (a.recipient_names is null or cardinality(a.recipient_names) = 0);
