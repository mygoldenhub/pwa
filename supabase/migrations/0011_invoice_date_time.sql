-- invoice.date / date_string / due_date_string = the time the invoice was created.
-- Run this in the Supabase SQL editor (safe to re-run).
--
-- Rule (applies to every sync function, because it is a trigger):
--   * When an invoice row is first created in Supabase:
--       date            = created time (now(), stored in UTC)
--       date_string     = created time as UTC text, e.g. "2026-11-14T03:30:12.345Z"
--       due_date_string = created time + 7 days, same format
--   * Later updates/syncs never change these three fields.
-- Existing invoices are not changed.

-- Clean up the helper from the previous version of this migration, if it was run.
drop function if exists public.invoice_day(timestamptz);

create or replace function public.invoice_fill_date_time()
returns trigger
language plpgsql
as $$
declare
  fmt constant text := 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"';
begin
  if tg_op = 'INSERT' then
    new.date := now();
    new.date_string := to_char(new.date at time zone 'UTC', fmt);
    new.due_date_string := to_char((new.date + interval '7 days') at time zone 'UTC', fmt);
  else
    -- UPDATE (including upsert of an existing invoice): keep the created-time values.
    new.date := coalesce(old.date, new.date);
    new.date_string := coalesce(old.date_string, new.date_string);
    new.due_date_string := coalesce(old.due_date_string, new.due_date_string);
  end if;
  return new;
end;
$$;

drop trigger if exists invoice_fill_date_time on public.invoice;
create trigger invoice_fill_date_time
before insert or update on public.invoice
for each row
execute function public.invoice_fill_date_time();
