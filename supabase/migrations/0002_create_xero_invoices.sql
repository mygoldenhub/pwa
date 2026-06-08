-- Creates the table used by the app to display invoice history.
-- If you already have this table in Supabase, you can skip applying this migration.

create extension if not exists pgcrypto;

create table if not exists public.xero_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  xero_invoice_id text not null,

  -- Xero fields (commonly used by the UI)
  invoice_number text null,
  reference text null,
  contact_id text null,
  issue_date date null,
  due_date date null,
  status text null,
  type text null,
  currency text null,
  total numeric null,
  amount_due numeric null,
  amount_paid numeric null,

  raw jsonb null,
  synced_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists xero_invoices_contact_id_idx on public.xero_invoices (contact_id);
create index if not exists xero_invoices_issue_date_idx on public.xero_invoices (issue_date);
create index if not exists xero_invoices_due_date_idx on public.xero_invoices (due_date);

alter table public.xero_invoices enable row level security;

-- Allow the signed-in user to read only their invoices.
-- The app resolves the user's Xero contact id from public.users.xero_account_id.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'xero_invoices'
      and policyname = 'select_own_xero_invoices'
  ) then
    create policy select_own_xero_invoices
      on public.xero_invoices
      for select
      to authenticated
      using (
        contact_id is not null
        and contact_id = (
          select u.xero_account_id
          from public.users u
          where u.id = auth.uid()
          limit 1
        )
      );
  end if;
end $$;
