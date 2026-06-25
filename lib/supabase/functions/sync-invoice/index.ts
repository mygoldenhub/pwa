// supabase/functions/sync-invoices/index.ts
import { createClient } from "npm:@supabase/supabase-js@2";

type IncomingInvoice = {
  Type?: string;
  InvoiceID: string;
  InvoiceNumber?: string;
  Reference?: string;

  Payments?: Array<{
    PaymentID: string;
    Date?: string;
    Amount?: number;
    Reference?: string;
    CurrencyRate?: number;
    HasAccount?: boolean;
  }>;

  Prepayments?: any[];
  Overpayments?: any[];

  AmountDue?: number;
  AmountPaid?: number;
  CurrencyRate?: number;

  // Make.com sends "No" as a string for boolean fields
  IsDiscounted?: boolean | string;
  HasAttachments?: boolean | string;
  Attachments?: any[];

  InvoicePaymentServices?: any[];

  Contact?: {
    ContactID?: string;
    Name?: string;
    ContactStatus?: string;
    FirstName?: string;
    LastName?: string;
    EmailAddress?: string;
    Addresses?: any[];
    Phones?: any[];
    UpdatedDateUTC?: string;
    ContactGroups?: any[];
    IsSupplier?: boolean;
    IsCustomer?: boolean;
    DefaultCurrency?: string;
    SalesTrackingCategories?: any[];
    PurchasesTrackingCategories?: any[];
    ContactPersons?: any[];
  };

  Date?: string;
  DueDate?: string;

  BrandingThemeID?: string;
  Status?: string;

  LineAmountTypes?: string;

  LineItems?: Array<{
    ItemCode?: string;
    Description?: string;
    UnitAmount?: number;
    TaxType?: string;
    TaxAmount?: number;
    LineAmount?: number;
    AccountCode?: string;
    Item?: { ItemID?: string; Name?: string; Code?: string };
    Tracking?: any[];
    Quantity?: number;
    LineItemID?: string;
    AccountID?: string;
  }>;

  SubTotal?: number;
  TotalTax?: number;
  Total?: number;

  // Make.com formats this as "YYYY-MM-DDTHH:mm:ss+00:00 ; UTC"
  // so we need to handle both raw and formatted strings
  UpdatedDateUTC?: string;

  CurrencyCode?: string;
  FullyPaidOnDate?: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const rawSecretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");

if (!SUPABASE_URL) throw new Error("SUPABASE_URL is required");
if (!rawSecretKeys) throw new Error("SUPABASE_SECRET_KEYS is required");

const secretKeys = JSON.parse(rawSecretKeys) as Record<string, string>;

const SECRET_KEY_NAME = "default";
const SERVICE_ROLE_KEY = secretKeys[SECRET_KEY_NAME];

if (!SERVICE_ROLE_KEY) {
  throw new Error(`Missing secret key "${SECRET_KEY_NAME}". Update SECRET_KEY_NAME in the function code.`);
}

const CONFIG = {
  table: "invoice",
  conflictColumn: "invoice_id",
};

/**
 * Make.com formats dates as "YYYY-MM-DDTHH:mm:ss+00:00 ; UTC"
 * This strips the trailing " ; UTC" if present and parses safely.
 */
function parseDate(dateStr?: string): Date | null {
  if (!dateStr) return null;
  // Strip Make.com's " ; UTC" suffix if present
  const cleaned = dateStr.replace(/\s*;\s*UTC\s*$/i, "").trim();
  const d = new Date(cleaned);
  return isNaN(d.getTime()) ? null : d;
}

function toDateKeepString(dateStr?: string): string | null {
  if (!dateStr) return null;
  // Strip Make.com's " ; UTC" suffix if present, return just date portion
  const cleaned = dateStr.replace(/\s*;\s*UTC\s*$/i, "").trim();
  return cleaned || null;
}

/**
 * Make.com sends boolean fields as the string "No" or "Yes"
 * when a radio button is selected. Normalise to boolean | null.
 */
function parseBool(val?: boolean | string): boolean | null {
  if (val === null || val === undefined) return null;
  if (typeof val === "boolean") return val;
  if (typeof val === "string") {
    if (val.toLowerCase() === "yes" || val === "true" || val === "1") return true;
    if (val.toLowerCase() === "no" || val === "false" || val === "0") return false;
  }
  return null;
}

function paymentsForDB(payments: IncomingInvoice["Payments"]) {
  return payments ?? [];
}

function lineItemsForDB(lineItems: IncomingInvoice["LineItems"]) {
  if (!lineItems) return [];
  return lineItems.map((li) => ({
    item: li.Item
      ? {
          code: li.Item.Code ?? null,
          name: li.Item.Name ?? null,
          item_id: li.Item.ItemID ?? null,
        }
      : null,
    quantity: li.Quantity ?? null,
    tax_type: li.TaxType ?? null,
    tracking: li.Tracking ?? [],
    item_code: li.ItemCode ?? null,
    account_id: li.AccountID ?? null,
    tax_amount: li.TaxAmount ?? null,
    description: li.Description ?? null,
    lineItem_id: li.LineItemID ?? null,
    line_amount: li.LineAmount ?? null,
    unit_amount: li.UnitAmount ?? null,
    account_code: li.AccountCode ?? null,
  }));
}

function contactForDB(contact?: IncomingInvoice["Contact"]) {
  if (!contact) return null;
  return {
    name: contact.Name ?? null,
    contact_id: contact.ContactID ?? null,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method must be POST" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(SUPABASE_URL!, SERVICE_ROLE_KEY);

  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Accept either a single invoice object OR an array (Make.com may send one at a time)
  const invoices: IncomingInvoice[] = Array.isArray(payload)
    ? (payload as IncomingInvoice[])
    : [payload as IncomingInvoice];

  let rows;
  try {
    rows = invoices.map((invoice) => {
      const invoice_id = invoice.InvoiceID;
      if (!invoice_id) throw new Error("Each invoice must include InvoiceID");
      return {
        invoice_id,

        type: invoice.Type ?? null,
        invoice_num: invoice.InvoiceNumber ?? null,
        reference: invoice.Reference ?? null,

        amount_due: invoice.AmountDue ?? null,
        amount_paid: invoice.AmountPaid ?? null,
        amount_credited: 0,

        currency_rate: invoice.CurrencyRate ?? null,

        // Handle Make.com "Yes"/"No" string values for booleans
        is_discounted: parseBool(invoice.IsDiscounted),
        has_attachments: parseBool(invoice.HasAttachments),

        contact: contactForDB(invoice.Contact),
        contact_id: contactForDB(invoice.Contact).contact_id,

        date_string: toDateKeepString(invoice.Date),
        date: parseDate(invoice.Date),

        due_date_string: toDateKeepString(invoice.DueDate),
        due_date: parseDate(invoice.DueDate),

        status: invoice.Status ?? null,
        line_amount_types: invoice.LineAmountTypes ?? null,

        sub_total: invoice.SubTotal ?? null,
        total_tax: invoice.TotalTax ?? null,
        total: invoice.Total ?? null,

        // Make.com formats as "YYYY-MM-DDTHH:mm:ss+00:00 ; UTC"
        updated_date_utc: parseDate(invoice.UpdatedDateUTC),

        currency_code: invoice.CurrencyCode ?? null,
        full_paid_on_date: invoice.FullyPaidOnDate ?? null,

        payments: paymentsForDB(invoice.Payments),
        line_items: lineItemsForDB(invoice.LineItems),
      };
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data, error } = await supabase
    .from(CONFIG.table)
    .upsert(rows, { onConflict: CONFIG.conflictColumn })
    .select();

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({
      ok: true,
      upserted: data?.length ?? rows.length,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    },
  );
});