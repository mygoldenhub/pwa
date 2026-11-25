-- Credit already spent against a user's plan. Starts at 0.
-- Also keeps credit_plan to the three admin tiers: Bronze 1000, Silver 3000, Gold 5000.

alter table public.users
  add column if not exists credit_used numeric not null default 0;

alter table public.users drop constraint if exists users_credit_used_check;
alter table public.users
  add constraint users_credit_used_check check (credit_used >= 0);

update public.users
set credit_plan = case
  when credit_plan >= 4000 then 5000
  when credit_plan >= 2000 then 3000
  else 1000
end
where credit_plan is distinct from 1000
  and credit_plan is distinct from 3000
  and credit_plan is distinct from 5000;

alter table public.users drop constraint if exists users_credit_plan_check;
alter table public.users
  add constraint users_credit_plan_check check (credit_plan in (1000, 3000, 5000));

create or replace function public.users_protect_pricing()
returns trigger
language plpgsql
set search_path = public
as $$
begin
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
