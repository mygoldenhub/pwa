-- Adds the paid amount to users.credit_used after a successful payment.
-- Non-admins still cannot edit credit fields themselves; only this function may increase credit_used.

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
      new.discount_level := old.discount_level;
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
      new.discount_level := 3;
      new.invoice_terms := '7 days';
    else
      new.credit_plan := old.credit_plan;
      new.credit_used := old.credit_used;
      new.discount_level := old.discount_level;
      new.invoice_terms := old.invoice_terms;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.record_credit_use(pay_amount numeric)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  plan numeric;
  used numeric;
begin
  if uid is null then
    raise exception 'Not signed in';
  end if;
  if pay_amount is null or pay_amount <= 0 then
    raise exception 'Invalid pay amount';
  end if;

  select credit_plan, credit_used
  into plan, used
  from public.users
  where id = uid
  for update;

  if not found then
    raise exception 'User not found';
  end if;

  if plan < used + pay_amount then
    raise exception 'Upgrade Credit Plan! You already used credit limit.';
  end if;

  perform set_config('app.allow_credit_use', '1', true);

  update public.users
  set credit_used = credit_used + pay_amount,
      updated_at = now()
  where id = uid
  returning credit_used into used;

  return used;
end;
$$;

revoke all on function public.record_credit_use(numeric) from public;
grant execute on function public.record_credit_use(numeric) to authenticated;
