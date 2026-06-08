import { createClient } from "npm:@supabase/supabase-js@2";

// Define the incoming item structure from Make.com
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
}

Deno.serve(async (req) => {
  // 1. Handle CORS Preflight requests
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
    // 2. Fetch data from the Make.com webhook URL
    const makeUrl = "https://hook.eu1.make.com/tp6ve8k5n2tu1puyx7nr8sce0li2r1hr";
    const webhookResponse = await fetch(makeUrl, { method: "GET" });

    if (!webhookResponse.ok) {
      throw new Error(`Failed to fetch from Make.com: ${webhookResponse.statusText}`);
    }

    const xeroData: XeroItem[] = await webhookResponse.json();

    if (!Array.isArray(xeroData)) {
      throw new Error("Data received from Make.com is not an array");
    }

    // 3. Map the Make.com payload keys to your snake_case Supabase table columns
    const rowsToUpsert = xeroData.map((item) => {
      // Safely parse account code to number or null if blank/missing
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
        updated_date_utc: new Date().toISOString(), // Fallback since sample data UTC object is empty
      };
    });

    // 4. Initialize Supabase client using internal Environment Variables
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "" 
    );

    // 5. Upsert data into public.xero_products table
    const { data, error } = await supabase
      .from("xero_products")
      .upsert(rowsToUpsert, { onConflict: "item_id" })
      .select();

    if (error) throw error;

    // 6. Return successful response
    return new Response(
      JSON.stringify({ success: true, message: `Successfully upserted ${rowsToUpsert.length} products.` }),
      {
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        status: 200,
      }
    );

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("get-all-xero-items failed:", err);
    return new Response(JSON.stringify({ success: false, error: message }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      status: 400,
    });
  }
});
