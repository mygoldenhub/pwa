-- Credit plan, discount level, and invoice terms live on public.users.
-- This replaces the earlier customer_pricing table and customer_pricing_overview view.
-- If that older version was already applied, this script copies its values, then removes it.

alter table public.users
  add column if not exists credit_plan numeric not null default 1000,
  add column if not exists credit_used numeric not null default 0,
  add column if not exists discount_level numeric not null default 3,
  add column if not exists invoice_terms text not null default '7 days';

alter table public.users drop constraint if exists users_credit_plan_check;
alter table public.users
  add constraint users_credit_plan_check check (credit_plan >= 0);

alter table public.users drop constraint if exists users_discount_level_check;
alter table public.users
  add constraint users_discount_level_check check (discount_level >= 0 and discount_level <= 100);

do $$
begin
  if to_regclass('public.customer_pricing') is not null then
    update public.users u
    set
      credit_plan = p.credit_plan,
      discount_level = p.discount_level,
      invoice_terms = coalesce(nullif(btrim(p.invoice_terms), ''), '7 days')
    from public.customer_pricing p
    where p.user_id = u.id;
  end if;
end $$;

drop view if exists public.customer_pricing_overview;
drop table if exists public.customer_pricing;

-- Signed-in non-admins cannot change their own pricing. Admins and the SQL editor can.
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

drop trigger if exists users_protect_pricing on public.users;
create trigger users_protect_pricing
before insert or update on public.users
for each row
execute function public.users_protect_pricing();
