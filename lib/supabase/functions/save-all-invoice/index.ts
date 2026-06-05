import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Global CORS headers to handle standard network requests safely
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export default {
  async fetch(req: Request): Promise<Response> {
    // 1. Handle browser preflight checks instantly
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    // 2. Enforce the requested HTTP GET invocation strategy restriction
    if (req.method !== "GET") {
      return Response.json(
        { success: false, error: `Method ${req.method} Not Allowed. Use GET to trigger sync.` },
        { status: 405, headers: corsHeaders }
      );
    }

    try {
      console.info("Starting historical invoice sync pull sequence...");

      // 3. Setup client environment configurations using built-in tokens
      const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
      const supabase = createClient(supabaseUrl, supabaseServiceKey);

      // 4. Fetch the Xero historical array directly from your Make.com endpoint via GET
      const makeUrl = "https://hook.eu1.make.com/bbs5vu5f4xaj4reomt40unic3bevr9sj";
      const response = await fetch(makeUrl, { method: "GET" });
      
      if (!response.ok) {
        throw new Error(`Failed to extract data from Make.com pipeline: ${response.statusText}`);
      }

      // 5. Load and parse payload data assets safely
      let rawData = await response.json();
      
      // If data arrives as double-nested arrays [[{}, {}]], flatten it cleanly down to [{}]
      if (Array.isArray(rawData) && rawData.length > 0 && Array.isArray(rawData[0])) {
        rawData = rawData.flat();
      }

      // Ensure we have a valid iterable collection array to execute logic loops against
      if (!Array.isArray(rawData)) {
        throw new Error("Invalid payload format received. Expected an array of invoices.");
      }

      const invoicesToUpsert: any[] = [];

      // 6. Map and process array assets into your single-table layout properties
      for (const item of rawData) {
        // Skip anomalies or malformed rows that lack a primary reference identifier key
        if (!item || !item.InvoiceID) {
          continue;
        }

        // Map invoice sub-object structures safely
        const cleanPayments = (item.Payments || []).map((p: any) => ({
          payment_id: p.PaymentID,
          data: p.Date,
          amount: p.Amount,
          reference: p.Reference,
          currency_rate: p.CurrencyRate,
          has_account: p.HasAccount,
          has_validation_errors: p.HasValidationErrors || false
        }));

        const cleanLineItems = (item.LineItems || []).map((li: any) => ({
          lineItem_id: li.LineItemID,
          item_code: li.ItemCode,
          description: li.Description,
          unit_amount: li.UnitAmount,
          tax_type: li.TaxType,
          tax_amount: li.TaxAmount,
          line_amount: li.LineAmount,
          account_code: li.AccountCode,
          item: li.Item ? { item_id: li.Item.ItemID, name: li.Item.Name, code: li.Item.Code } : null,
          tracking: li.Tracking || [],
          quantity: li.Quantity, 
          account_id: li.AccountID
        }));

        // Push clean mapped schema profile values into our database pipeline queue array
        invoicesToUpsert.push({
          invoice_id: item.InvoiceID,
          type: item.Type,
          invoice_num: item.InvoiceNumber,
          reference: item.Reference,
          amount_due: item.AmountDue,
          amount_paid: item.AmountPaid,
          amount_credited: item.AmountCredited,
          currency_rate: item.CurrencyRate,
          is_discounted: item.IsDiscounted,
          has_attachments: item.HasAttachments,
          contact: item.Contact ? { contact_id: item.Contact.ContactID, name: item.Contact.Name } : null,
          date_string: item.Date,
          date: item.Date,
          due_date_string: item.DueDate,
          due_date: item.DueDate,
          status: item.Status,
          line_amount_types: item.LineAmountTypes,
          sub_total: item.SubTotal,
          total_tax: item.TotalTax,
          total: item.Total,
          updated_date_utc: item.UpdatedDateUTC,
          currency_code: item.CurrencyCode,
          full_paid_on_date: item.FullyPaidOnDate,
          
          // Store sub-arrays as structured schema fields inside JSONB properties directly
          payments: cleanPayments,
          line_items: cleanLineItems
        });
      }

      // 7. Execute transaction upsert overwrite directly against the database 
      if (invoicesToUpsert.length > 0) {
        const { error } = await supabase
          .from("invoice")
          .upsert(invoicesToUpsert, { onConflict: "invoice_id" });
        
        if (error) {
          throw error;
        }
        console.info(`Database processing sequence complete. Synchronized ${invoicesToUpsert.length} invoice rows.`);
      }

      // 8. Return success metadata payload back to the browser invocation client
      return Response.json(
        { success: true, message: `Successfully loaded and synced ${invoicesToUpsert.length} records into invoice table.` }, 
        { status: 200, headers: corsHeaders }
      );

    } catch (err: any) {
      console.error("Critical execution crash failure captured:", err.message);
      return Response.json(
        { success: false, error: err.message }, 
        { status: 400, headers: corsHeaders }
      );
    }
  }
};
