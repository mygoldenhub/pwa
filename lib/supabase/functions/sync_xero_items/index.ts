import { createClient } from "npm:@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// 1. Define the incoming PascalCase structure from make.com.
//    NOTE: the webhook returns a bare array of items directly:
//      [ XeroItem, XeroItem, ... ]
//    Each item's own `body` field holds Xero metadata (Id, Status,
//    HistoryRecords, etc) - it is NOT an envelope wrapper around the array.
interface HistoryRecord {
  Changes?: string;
  DateUTCString?: string; // e.g. "2026-05-27T22:45:18" (naive, treated as UTC)
  DateUTC?: string; // e.g. "/Date(1779921918000+0000)/"
  User?: string;
  Details?: string;
}

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
  body?: {
    Id?: string;
    Status?: string;
    ProviderName?: string;
    DateTimeUTC?: string;
    HistoryRecords?: HistoryRecord[];
  };
}

interface MakeWebhookEnvelope {
  body: XeroItem[];
  status?: number;
  headers?: unknown[];
}

interface CleanedItem {
  item_id: string;
  code: string;
  name: string;
  description: string | null;
  purchase_description: string | null;
  is_tracked_as_inventory: boolean;
  quantity_on_hand: number;
  inventory_asset_account_code: number | null;
  sales_details: Record<string, unknown>;
  purchase_details: Record<string, unknown>;
  updated_date_utc: string;
}

// ---------------------------------------------------------------------------
// Constants / helpers
// ---------------------------------------------------------------------------

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-max-age": "86400",
};

const LOOKBACK_MS = 2 * 60 * 60 * 1000; // last 2 hours

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

async function fetchWithTimeout(input: string, init: RequestInit & { timeoutMs?: number } = {}) {
  const controller = new AbortController();
  const timeoutMs = init.timeoutMs ?? 30_000;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const { timeoutMs: _timeoutMs, ...rest } = init;
    return await fetch(input, { ...rest, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

// Parses a HistoryRecord timestamp into a JS Date (UTC).
// Prefers `DateUTCString` (e.g. "2026-05-27T22:45:18"), treating it as UTC
// since it carries no timezone offset. Falls back to the .NET-style
// `DateUTC` field (e.g. "/Date(1779921918000+0000)/") if needed.
function parseHistoryDate(record: HistoryRecord): Date | null {
  if (record.DateUTCString) {
    const iso = record.DateUTCString.endsWith("Z")
      ? record.DateUTCString
      : `${record.DateUTCString}Z`;
    const d = new Date(iso);
    if (!isNaN(d.getTime())) return d;
  }
  if (record.DateUTC) {
    const match = record.DateUTC.match(/\/Date\((\d+)([+-]\d{4})?\)\//);
    if (match) {
      const ms = Number(match[1]);
      if (!isNaN(ms)) return new Date(ms);
    }
  }
  return null;
}

type HistoryDecision = "delete" | "add" | "none";

// Scans HistoryRecords (assumed newest-first, matching Xero's API ordering)
// for records within the last 2 hours, and returns the decision based on the
// most recent matching record found.
function getHistoryDecision(records: HistoryRecord[] | undefined, now: Date): HistoryDecision {
  if (!records || records.length === 0) return "none";

  for (const record of records) {
    const recordDate = parseHistoryDate(record);
    if (!recordDate) continue;

    const ageMs = now.getTime() - recordDate.getTime();
    // Only consider records from "start" (oldest) up to 2 hours ago, i.e.
    // records that happened within the last 2 hours.
    if (ageMs < 0 || ageMs > LOOKBACK_MS) continue;

    const details = record.Details ?? "";
    console.log(details);
    // if (details.includes(ACTIVE_TO_INACTIVE_PHRASE)) return "delete";
    // if (details.includes(INACTIVE_TO_ACTIVE_PHRASE)) return "add";
    if (details.toLowerCase().includes("item changed from active to inactive.")) return "delete";
    if (details.toLowerCase().includes("item changed from inactive to active.")) return "add";
  }

  return "none";
}

function cleanItem(item: XeroItem): CleanedItem {
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
    updated_date_utc: item.UpdatedDateUTC || new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  // Handle CORS Preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    // 1. Fetch raw data from the Make.com webhook URL.
    const makeUrl = Deno.env.get("MAKE_XERO_PRODUCTS_HOOK_URL") ??
      "https://hook.eu1.make.com/isyhhjp14013a762d3ggm5om6dri1u9g";

    const webhookResponse = await fetchWithTimeout(makeUrl, {
      method: "GET",
      timeoutMs: 60_000,
      headers: { "cache-control": "no-cache" },
    });

    if (!webhookResponse.ok) {
      throw new Error(`Failed to fetch from Make.com: ${webhookResponse.statusText}`);
    }

    // Read as text first so a non-JSON response (e.g. Make.com's default
    // "Accepted" immediate-response acknowledgment) produces a clear,
    // actionable error instead of a raw JSON.parse crash.
    const webhookText = await webhookResponse.text();
    let rawResponse: unknown;
    try {
      rawResponse = JSON.parse(webhookText);
    } catch {
      throw new Error(
        `Make.com did not return JSON (got: "${webhookText.slice(0, 200)}"). ` +
          "This usually means the scenario's webhook is set to 'Immediately respond' " +
          "instead of using a 'Webhook response' module at the end of the scenario, " +
          "or the scenario errored before reaching that module.",
      );
    }

    // 2. The webhook is expected to return a bare array of items:
    //    [ XeroItem, XeroItem, ... ]
    // where each item's own `body` field holds Xero metadata (Id, Status,
    // HistoryRecords, etc) - NOT an envelope wrapper. For resilience, also
    // accept the older `[{ body: XeroItem[], status, headers }]` envelope
    // shape, in case the Make.com "Webhook response" module ever gets
    // reconfigured to wrap the array that way.
    if (!Array.isArray(rawResponse) || rawResponse.length === 0) {
      throw new Error("Data received from Make.com is not a non-empty array");
    }

    let xeroData: XeroItem[];
    const first = rawResponse[0] as unknown;
    if (first && typeof first === "object" && "ItemID" in (first as Record<string, unknown>)) {
      // Bare array of items (each item's `body` is Xero metadata, not an envelope).
      xeroData = rawResponse as XeroItem[];
    } else if (first && typeof first === "object" && "body" in (first as Record<string, unknown>)) {
      const envelope = first as MakeWebhookEnvelope;
      if (!Array.isArray(envelope.body)) {
        throw new Error("Data received from Make.com has a `body` field that is not an array");
      }
      xeroData = envelope.body;
    } else {
      throw new Error(
        "Data received from Make.com does not match the expected shape " +
          "(neither `[{ body: [...] }]` nor a bare array of items)",
      );
    }

    // 3. Initialize Supabase client.
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY env vars");
    }
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 4. For each item, inspect HistoryRecords from the last 2 hours to decide
    //    whether it should be deleted, added/updated, or left to a normal
    //    upsert based on the most recent matching history record.
    const now = new Date();

    const toUpsert: CleanedItem[] = [];
    const toDelete: string[] = [];
    const itemDecisions: { item_id: string; code: string; decision: HistoryDecision }[] = [];

    for (const item of xeroData) {
      const decision = getHistoryDecision(item.body?.HistoryRecords, now);
      itemDecisions.push({ item_id: item.ItemID, code: item.Code, decision });

      if (decision === "delete") {
        toDelete.push(item.ItemID);
      } else {
        // "add" (inactive -> active) and "none" (no relevant history) both
        // result in the row being upserted with the latest item data.
        toUpsert.push(cleanItem(item));
      }
    }

    // 5. Apply deletes (items that just went active -> inactive).
    let deletedCount = 0;
    if (toDelete.length > 0) {
      const { error: deleteError, count } = await supabase
        .from("xero_products")
        .delete({ count: "exact" })
        .in("item_id", toDelete);

      if (deleteError) throw deleteError;
      deletedCount = count ?? toDelete.length;
    }

    // 6. Apply upserts (items that just went inactive -> active, or had no
    //    relevant active/inactive history change in the last 2 hours).
    let upsertedCount = 0;
    if (toUpsert.length > 0) {
      const { error: upsertError, count } = await supabase
        .from("xero_products")
        .upsert(toUpsert, { onConflict: "item_id", count: "exact" });

      if (upsertError) throw upsertError;
      upsertedCount = count ?? toUpsert.length;
    }

    // 7. After update completes, run the exception cleanup function.
    //    The function uses the service role key, so we call it with
    //    Authorization + apikey.
    const exceptionUrl = `${supabaseUrl}/functions/v1/xero-products-exception-data`;
    const exceptionRes = await fetchWithTimeout(exceptionUrl, {
      method: "POST",
      timeoutMs: 60_000,
      headers: {
        authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        triggered_by: "sync_xero_items",
        synced_count: toUpsert.length,
        deleted_count: toDelete.length,
      }),
    });

    const exceptionText = await exceptionRes.text();
    if (!exceptionRes.ok) {
      // The main sync succeeded; surface this as a partial failure so it can be monitored.
      return jsonResponse(
        {
          success: true,
          upserted_count: upsertedCount,
          deleted_count: deletedCount,
          item_decisions: itemDecisions,
          exception_cleanup: { success: false, status: exceptionRes.status, body: exceptionText },
          message: "Products synced, but exception cleanup failed.",
        },
        200,
      );
    }

    let exceptionBody: unknown = exceptionText;
    try {
      exceptionBody = exceptionText ? JSON.parse(exceptionText) : null;
    } catch {
      // Keep raw text.
    }

    // 8. Return successful response.
    return jsonResponse({
      success: true,
      upserted_count: upsertedCount,
      deleted_count: deletedCount,
      item_decisions: itemDecisions,
      exception_cleanup: { success: true, body: exceptionBody },
      message:
        `Successfully synced ${upsertedCount} product(s) and removed ${deletedCount} product(s) based on recent active/inactive history.`,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("Sync failed:", err);
    return jsonResponse({ success: false, error: message }, 400);
  }
});
