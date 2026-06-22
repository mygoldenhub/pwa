create or replace function sync_xero_products(items_data jsonb)
returns void as $$
begin
    -- 1. Insert new products or update existing ones based on item_id
    insert into public.xero_products (
        item_id, 
        code, 
        name, 
        description, 
        purchase_description, 
        is_tracked_as_inventory, 
        quantity_on_hand, 
        inventory_asset_account_code, 
        sales_details, 
        purchase_details,
        updated_date_utc
    )
    select 
        (x->>'item_id'),
        (x->>'code'),
        (x->>'name'),
        (x->>'description'),
        (x->>'purchase_description'),
        (x->>'is_tracked_as_inventory')::boolean,
        coalesce((x->>'quantity_on_hand')::numeric, 0),
        (x->>'inventory_asset_account_code')::numeric,
        coalesce((x->'sales_details'), '{}'::jsonb),
        coalesce((x->'purchase_details'), '{}'::jsonb),
        (x->>'updated_date_utc')::timestamp with time zone -- Reads the date from your Edge Function payload
    from jsonb_array_elements(items_data) as x
    on conflict (item_id) do update set
        code = excluded.code,
        name = excluded.name,
        description = excluded.description,
        purchase_description = excluded.purchase_description,
        is_tracked_as_inventory = excluded.is_tracked_as_inventory,
        quantity_on_hand = excluded.quantity_on_hand,
        inventory_asset_account_code = excluded.inventory_asset_account_code,
        sales_details = excluded.sales_details,
        purchase_details = excluded.purchase_details,
        updated_date_utc = excluded.updated_date_utc; -- Updates the date column to match Xero

    -- 2. Delete products from Supabase that are no longer present in Xero
    delete from public.xero_products
    where item_id not in (
        select (x->>'item_id')
        from jsonb_array_elements(items_data) as x
    );
end;
$$ language plpgsql security definer;
