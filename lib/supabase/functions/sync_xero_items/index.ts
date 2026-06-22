import { createClient } from "npm:@supabase/supabase-js@2";

// 1. Define the incoming PascalCase structure from ://make.com
interface XeroItem {
  ItemID: string;
  Code: string;
  Name: string;
  Description?: string;
  PurchaseDescription?: string;
  IsTrackedAsInventory?: boolean;
  QuantityOnHand?: number;
  InventoryAssetAccountCode?: string | number;
  SalesDetails?: Record<string, unknown>;
  PurchaseDetails?: Record<string, unknown>;
  UpdatedDateUTC?: string;
}

Deno.serve(async (req) => {
  // Handle CORS Preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    // 2. Fetch raw data from the Make.com webhook URL
    const makeUrl = "https://hook.eu1.make.com/tp6ve8k5n2tu1puyx7nr8sce0li2r1hr";
    const webhookResponse = await fetch(makeUrl, { method: "GET" });

    if (!webhookResponse.ok) {
      throw new Error(`Failed to fetch from Make.com: ${webhookResponse.statusText}`);
    }

    const xeroData: XeroItem[] = await webhookResponse.json();

    if (!Array.isArray(xeroData)) {
      throw new Error("Data received from Make.com is not an array");
    }

    // 3. Map PascalCase keys to snake_case objects matching what the Postgres function expects
    const cleanedItems = xeroData.map((item) => {
      const assetAccount = item.InventoryAssetAccountCode 
        ? Number(item.InventoryAssetAccountCode) 
        : null;

      return {
        item_id: item.ItemID,
        code: item.Code,
        name: item.Name,
        description: item.Description || null,
        purchase_description: item.PurchaseDescription || null,
        is_tracked_as_inventory: item.IsTrackedAsInventory ?? false,
        quantity_on_hand: item.QuantityOnHand ?? 0,
        inventory_asset_account_code: isNaN(assetAccount as number) ? null : assetAccount,
        sales_details: item.SalesDetails || {},
        purchase_details: item.PurchaseDetails || {},
        updated_date_utc: item.UpdatedDateUTC || new Date().toISOString()
      };
    });

    // 4. Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "" 
    );

    // 5. Pass the cleanly mapped array to our zero-downtime Postgres function
    const { error } = await supabase.rpc("sync_xero_products", {
      items_data: cleanedItems,
    });

    if (error) throw error;

    // 6. Return successful response
    return new Response(
      JSON.stringify({ success: true, message: `Successfully synchronized ${cleanedItems.length} products with zero downtime.` }),
      {
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        status: 200,
      }
    );

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("Sync failed:", err);
    return new Response(JSON.stringify({ success: false, error: message }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      status: 400,
    });
  }
});
