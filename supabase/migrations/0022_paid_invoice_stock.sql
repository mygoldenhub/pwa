-- When an invoice is created, subtract each line quantity from xero_products.quantity_on_hand.
-- The result is never below 0. Paying an invoice does not change quantity_on_hand.
-- Signed-in users cannot update xero_products directly.

create or replace function public.apply_paid_invoice_stock(lines jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  line jsonb;
  item_id text;
  item_code text;
  qty numeric;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if lines is null or jsonb_typeof(lines) <> 'array' then
    return;
  end if;

  for line in select value from jsonb_array_elements(lines)
  loop
    item_id := nullif(btrim(coalesce(line->>'item_id', '')), '');
    item_code := nullif(btrim(coalesce(line->>'item_code', '')), '');
    begin
      qty := (line->>'quantity')::numeric;
    exception when others then
      qty := null;
    end;
    if qty is null or qty <= 0 then
      continue;
    end if;

    if item_id is not null then
      update public.xero_products
      set quantity_on_hand = greatest(0, coalesce(quantity_on_hand, 0) - qty)
      where public.xero_products.item_id = apply_paid_invoice_stock.item_id;
    elsif item_code is not null then
      update public.xero_products
      set quantity_on_hand = greatest(0, coalesce(quantity_on_hand, 0) - qty)
      where code = item_code;
    end if;
  end loop;
end;
$$;

revoke all on function public.apply_paid_invoice_stock(jsonb) from public;
grant execute on function public.apply_paid_invoice_stock(jsonb) to authenticated;
