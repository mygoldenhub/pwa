-- After a payment is added to credit_used, tell that customer when they
-- have used more than 90% of their credit plan.
-- record_credit_use is security definer, so it can insert the broadcast
-- even though only admins may insert announcements directly.

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
  first_name text;
  pct integer;
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

  if plan > 0 and used > plan * 0.9 then
    select split_part(
      coalesce(nullif(btrim(display_name), ''), split_part(coalesce(email, ''), '@', 1)),
      ' ',
      1
    )
    into first_name
    from public.users
    where id = uid;

    pct := round(used * 100.0 / plan);

    begin
      insert into public.announcements (title, body, created_by, recipient_ids, recipient_names)
      values (
        'Upgrade your credit plan',
        format('You already used %s%% of plan, please upgrade yourplan.', pct),
        uid,
        array[uid],
        case
          when first_name is null or btrim(first_name) = '' then null
          else array[btrim(first_name)]
        end
      );
    exception when others then
      raise warning 'credit plan notice was not sent: %', sqlerrm;
    end;
  end if;

  return used;
end;
$$;

revoke all on function public.record_credit_use(numeric) from public;
grant execute on function public.record_credit_use(numeric) to authenticated;
