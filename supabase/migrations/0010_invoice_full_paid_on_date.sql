-- Fill invoice.full_paid_on_date when an invoice is paid but Xero/Make did not send FullyPaidOnDate
-- (e.g. a new invoice paid immediately with Stripe "Pay now").
-- Run this in the Supabase SQL editor.
--
-- Rule (applies to every insert/update, from any sync function):
--   * Invoice is paid (status PAID, or nothing left to pay) and full_paid_on_date is empty
--       -> keep the previously stored date, if any
--       -> otherwise use the latest payment date in `payments`
--       -> otherwise use the current time.

-- 1) Parse the date formats Xero/Make send: "/Date(1700000000000+0000)/", ISO strings,
--    and Make's "YYYY-MM-DDTHH:mm:ss+00:00 ; UTC". Returns null when it cannot parse.
create or replace function public.parse_xero_date(v text)
returns timestamptz
language plpgsql
immutable
as $$
declare
  ms text;
  cleaned text;
begin
  if v is null or btrim(v) = '' then
    return null;
  end if;

  ms := substring(v from '/Date\((-?[0-9]+)');
  if ms is not null then
    return to_timestamp(ms::bigint / 1000.0);
  end if;

  cleaned := btrim(regexp_replace(v, '\s*;\s*UTC\s*$', '', 'i'));
  begin
    return cleaned::timestamptz;
  exception when others then
    return null;
  end;
end;
$$;

-- 2) Trigger that fills the date.
create or replace function public.invoice_fill_full_paid_on_date()
returns trigger
language plpgsql
as $$
declare
  latest_payment timestamptz;
begin
  if new.full_paid_on_date is not null then
    return new;
  end if;

  if not (
    upper(coalesce(new.status, '')) = 'PAID'
    or (coalesce(new.amount_paid, 0) > 0 and coalesce(new.amount_due, 1) <= 0)
  ) then
    return new;
  end if;

  -- A later sync without the date must not wipe a date we already have.
  if tg_op = 'UPDATE' and old.full_paid_on_date is not null then
    new.full_paid_on_date := old.full_paid_on_date;
    return new;
  end if;

  -- Payments keep the date under "Date" (sync-invoice) or "data" (save-all-invoice).
  select max(coalesce(
           public.parse_xero_date(p->>'Date'),
           public.parse_xero_date(p->>'data'),
           public.parse_xero_date(p->>'date')
         ))
    into latest_payment
    from jsonb_array_elements(
           case when jsonb_typeof(new.payments) = 'array' then new.payments else '[]'::jsonb end
         ) as p;

  new.full_paid_on_date := coalesce(latest_payment, now());
  return new;
end;
$$;

drop trigger if exists invoice_fill_full_paid_on_date on public.invoice;
create trigger invoice_fill_full_paid_on_date
before insert or update on public.invoice
for each row
execute function public.invoice_fill_full_paid_on_date();

-- 3) Backfill invoices that are already paid but have no date (the trigger fills them).
update public.invoice
set status = status
where full_paid_on_date is null
  and (
    upper(coalesce(status, '')) = 'PAID'
    or (coalesce(amount_paid, 0) > 0 and coalesce(amount_due, 1) <= 0)
  );
