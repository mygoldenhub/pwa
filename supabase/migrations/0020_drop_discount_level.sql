-- Discount level is no longer stored on users.
-- Invoice terms stay, limited to 7, 14, or 30 days.
-- Replace the pricing guard before dropping the column so inserts and updates
-- do not still write discount_level.

create or replace function public.users_protect_pricing()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Set only by record_credit_use, in the same transaction.
  if coalesce(current_setting('app.allow_credit_use', true), '') = '1' then
    if tg_op = 'UPDATE' then
      new.credit_plan := old.credit_plan;
      new.invoice_terms := old.invoice_terms;
      if new.credit_used < old.credit_used then
        new.credit_used := old.credit_used;
      end if;
    end if;
    return new;
  end if;

  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.credit_plan := 1000;
      new.credit_used := 0;
      new.invoice_terms := '7 days';
    else
      new.credit_plan := old.credit_plan;
      new.credit_used := old.credit_used;
      new.invoice_terms := old.invoice_terms;
    end if;
  end if;
  return new;
end;
$$;

alter table public.users drop constraint if exists users_discount_level_check;
alter table public.users drop column if exists discount_level;

update public.users
set invoice_terms = case
  when lower(btrim(invoice_terms)) in ('14', '14 days') then '14 days'
  when lower(btrim(invoice_terms)) in ('30', '30 days') then '30 days'
  else '7 days'
end
where invoice_terms is distinct from '7 days'
  and invoice_terms is distinct from '14 days'
  and invoice_terms is distinct from '30 days';

alter table public.users drop constraint if exists users_invoice_terms_check;
alter table public.users
  add constraint users_invoice_terms_check check (invoice_terms in ('7 days', '14 days', '30 days'));
