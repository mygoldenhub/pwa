/// Supabase Edge Function: xero_upsert_contact_cc
///
/// Find-or-create a Xero Contact (customer) by email and return its ContactID.
///
/// This function is configured with verify_jwt=false so it can be called before
/// a Supabase account exists.
///
/// Required secrets:
/// - XERO_CLIENT_ID
/// - XERO_CLIENT_SECRET
/// - XERO_TENANT_ID              (optional if stored in DB; DB value will be used if unset)
///
/// DB requirement:
/// - public.xero_tokens must contain at least one row with refresh_token (and ideally tenant_id)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type JsonRecord = Record<string, unknown>;

type UpsertRequestBody = {
  // Accept both camelCase and snake_case keys.
  fullName?: string;
  full_name?: string;
  email?: string;
  companyName?: string;
  company_name?: string;
  phoneNumber?: string;
  phone_number?: string;
};

function jsonResponse(status: number, body: JsonRecord) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required env var: ${name}`);
  return value;
}

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

async function readLatestTokenRow(
  supabaseUrl: string,
  serviceRole: string,
): Promise<{ id: string; refreshToken: string; tenantIdFromDb: string | null }> {
  const res = await fetch(
    `${supabaseUrl}/rest/v1/xero_tokens?select=id,refresh_token,tenant_id,created_at&order=created_at.desc&limit=1`,
    {
      method: "GET",
      headers: { apikey: serviceRole, authorization: `Bearer ${serviceRole}` },
    },
  );

  if (!res.ok) throw new Error(`Failed to read xero_tokens row from Supabase: ${res.status} :: ${await res.text()}`);

  const json = (await res.json()) as Array<{ id?: string; refresh_token?: string; tenant_id?: string }>;
  const row = json?.[0];
  const id = safeStr(row?.id);
  const refreshToken = safeStr(row?.refresh_token);
  if (!id || !refreshToken) throw new Error("No valid row found in public.xero_tokens for this request.");

  const tenantIdFromDb = safeStr(row?.tenant_id) || null;
  return { id, refreshToken, tenantIdFromDb };
}

async function rotateTokensInDb(
  supabaseUrl: string,
  serviceRole: string,
  tokenRowId: string,
  patch: { access_token?: string; refresh_token?: string; expires_at?: string },
) {
  const res = await fetch(`${supabaseUrl}/rest/v1/xero_tokens?id=eq.${encodeURIComponent(tokenRowId)}`, {
    method: "PATCH",
    headers: {
      apikey: serviceRole,
      authorization: `Bearer ${serviceRole}`,
      "content-type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({ ...patch, updated_at: new Date().toISOString() }),
  });

  if (!res.ok) throw new Error(`Failed to update xero_tokens in Supabase: ${res.status} :: ${await res.text()}`);
}

function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

function splitName(fullName: string): { firstName: string; lastName: string } {
  const cleaned = fullName.trim().replace(/\s+/g, " ");
  if (!cleaned) return { firstName: "", lastName: "" };
  const parts = cleaned.split(" ");
  if (parts.length === 1) return { firstName: parts[0], lastName: "" };
  return { firstName: parts[0], lastName: parts.slice(1).join(" ") };
}

function escapeXeroWhereString(value: string) {
  // Xero where clause uses double-quotes around string; inside, escape backslash and quotes.
  return value.replace(/\\/g, "\\\\").replace(/\"/g, "\\\"");
}

function base64UrlToBase64(input: string) {
  const base64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const pad = base64.length % 4;
  if (pad === 0) return base64;
  if (pad === 2) return base64 + "==";
  if (pad === 3) return base64 + "=";
  // If it's 1, it's invalid base64url
  return base64;
}

function decodeJwtPayloadSub(jwt: string): string | null {
  try {
    const parts = jwt.split(".");
    if (parts.length < 2) return null;
    const payloadB64 = base64UrlToBase64(parts[1]);
    const payloadJson = JSON.parse(atob(payloadB64));
    return typeof payloadJson?.sub === "string" ? payloadJson.sub : null;
  } catch {
    return null;
  }
}

async function xeroFetchJson(url: string, init: RequestInit) {
  const res = await fetch(url, init);
  const text = await res.text();
  let json: unknown = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }

  if (!res.ok) {
    throw new Error(
      `Xero API error ${res.status} ${res.statusText} for ${url} :: ${JSON.stringify(json)}`,
    );
  }
  return json as any;
}

// NOTE: verify_jwt=false, so callers may not have a JWT.
// We keep the JWT decoding helper above for potential future use.

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

    const contentType = req.headers.get("content-type") || "";
    if (!contentType.toLowerCase().includes("application/json")) {
      return jsonResponse(415, { error: "unsupported_media_type", message: "Use application/json" });
    }

    const body = (await req.json()) as UpsertRequestBody;

    // verify_jwt=false; tokens are stored globally in public.xero_tokens.

    const fullName = (body.fullName || body.full_name || "").trim();
    const emailRaw = (body.email || "").trim();
    const companyName = (body.companyName || body.company_name || "").trim();
    const phoneNumber = (body.phoneNumber || body.phone_number || "").trim();

    if (!emailRaw) return jsonResponse(400, { error: "invalid_request", message: "email is required" });

    const email = normalizeEmail(emailRaw);
    const { firstName, lastName } = splitName(fullName || companyName || email);

    const clientId = requireEnv("XERO_CLIENT_ID");
    const clientSecret = requireEnv("XERO_CLIENT_SECRET");
    const tenantIdEnv = safeStr(Deno.env.get("XERO_TENANT_ID"));

    // Supabase DB connection for token storage
    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceRole = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

    // 1) Read refresh token from Postgres
    const latest = await readLatestTokenRow(supabaseUrl, serviceRole);
    const refreshToken = latest.refreshToken;

    // Prefer DB tenant_id; allow env override for backwards compatibility.
    const tenantId = tenantIdEnv || latest.tenantIdFromDb;
    if (!tenantId) {
      throw new Error("Missing tenant_id. Set XERO_TENANT_ID secret or store tenant_id in public.xero_tokens.");
    }

    // 2) Refresh token -> access token (and rotate refresh token)
    const basic = btoa(`${clientId}:${clientSecret}`);

    const tokenRes = await fetch("https://identity.xero.com/connect/token", {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }),
    });

    const tokenText = await tokenRes.text();
    let tokenData: any = null;
    try {
      tokenData = tokenText ? JSON.parse(tokenText) : null;
    } catch {
      tokenData = { raw: tokenText };
    }

    if (!tokenRes.ok) {
      throw new Error(`Xero token refresh failed: ${tokenRes.status} :: ${JSON.stringify(tokenData)}`);
    }

    const accessToken: string | undefined = tokenData?.access_token;
    const rotatedRefreshToken: string | undefined = tokenData?.refresh_token;
    if (!accessToken) throw new Error(`Missing access_token in refresh response: ${JSON.stringify(tokenData)}`);

    const patch: { access_token?: string; refresh_token?: string; expires_at?: string } = { access_token: accessToken };
    if (rotatedRefreshToken && rotatedRefreshToken !== refreshToken) patch.refresh_token = rotatedRefreshToken;
    await rotateTokensInDb(supabaseUrl, serviceRole, latest.id, patch);

    const xeroHeaders = {
      Authorization: `Bearer ${accessToken}`,
      "Xero-tenant-id": tenantId,
      "content-type": "application/json",
      Accept: "application/json",
    };

    // 3) Find contact by EmailAddress across ALL contacts (not only customers)
    const where = `EmailAddress=="${escapeXeroWhereString(email)}"`;
    const findUrl = `https://api.xero.com/api.xro/2.0/Contacts?where=${encodeURIComponent(where)}`;

    const findJson = await xeroFetchJson(findUrl, { method: "GET", headers: xeroHeaders });
    const contacts: any[] = Array.isArray(findJson?.Contacts) ? findJson.Contacts : [];

    const existing = contacts.find((c) =>
      typeof c?.EmailAddress === "string" && normalizeEmail(c.EmailAddress) === email
    );

    // 4) Update or create contact as customer
    const desiredName = (companyName || fullName || email).trim();
    const phonePayload = phoneNumber ? [{ PhoneType: "MOBILE", PhoneNumber: phoneNumber }] : undefined;

    let contactId: string;
  let createdNew = false;

    if (existing?.ContactID) {
      const updateBody: any = {
        Contacts: [
          {
            ContactID: existing.ContactID,
            Name: desiredName,
            FirstName: firstName,
            LastName: lastName,
            EmailAddress: email,
            // NOTE: Xero's IsCustomer/IsSupplier fields are frequently treated as
            // computed/read-only by the API and may remain false until a sales
            // transaction exists. We still send it for forward-compat.
            IsCustomer: true,
            IsSupplier: false,
            ContactStatus: "ACTIVE",
          },
        ],
      };
      if (phonePayload) updateBody.Contacts[0].Phones = phonePayload;

      const updateRes = await xeroFetchJson("https://api.xero.com/api.xro/2.0/Contacts", {
        method: "POST",
        headers: xeroHeaders,
        body: JSON.stringify(updateBody),
      });

      const updated = Array.isArray(updateRes?.Contacts) ? updateRes.Contacts[0] : null;
      contactId = updated?.ContactID || existing.ContactID;
    } else {
      const createBody: any = {
        Contacts: [
          {
            Name: desiredName,
            FirstName: firstName,
            LastName: lastName,
            EmailAddress: email,
            IsCustomer: true,
            IsSupplier: false,
            ContactStatus: "ACTIVE",
          },
        ],
      };
      if (phonePayload) createBody.Contacts[0].Phones = phonePayload;

      const createdRes = await xeroFetchJson("https://api.xero.com/api.xro/2.0/Contacts", {
        method: "POST",
        headers: xeroHeaders,
        body: JSON.stringify(createBody),
      });

      const created = Array.isArray(createdRes?.Contacts) ? createdRes.Contacts[0] : null;
      contactId = created?.ContactID;
      if (!contactId) throw new Error(`Xero create did not return ContactID: ${JSON.stringify(createdRes)}`);
      createdNew = true;
    }

    // 5) (Optional) Force the contact to appear as a "Customer" in Xero.
    // In many Xero orgs, `IsCustomer` stays `false` until the contact is used on
    // a sales transaction (e.g., an ACCREC invoice). If you want that behavior,
    // set these Edge Function secrets:
    // - CREATE_DRAFT_SALES_INVOICE_ON_CONTACT_CREATE=true
    // - XERO_SALES_ACCOUNT_CODE=<a valid revenue account code in your org>
    // This will create a $0 draft invoice (if your org allows it).
    const shouldCreateDraftInvoice = (Deno.env.get("CREATE_DRAFT_SALES_INVOICE_ON_CONTACT_CREATE") || "").toLowerCase() === "true";
    const salesAccountCode = (Deno.env.get("XERO_SALES_ACCOUNT_CODE") || "").trim();

    let draftInvoiceId: string | undefined;
    if (createdNew && shouldCreateDraftInvoice) {
      if (!salesAccountCode) {
        console.warn("CREATE_DRAFT_SALES_INVOICE_ON_CONTACT_CREATE is true but XERO_SALES_ACCOUNT_CODE is not set; skipping invoice creation.");
      } else {
        try {
          const today = new Date().toISOString().slice(0, 10);
          const invoiceBody: any = {
            Invoices: [
              {
                Type: "ACCREC",
                Contact: { ContactID: contactId },
                Date: today,
                DueDate: today,
                Status: "DRAFT",
                LineItems: [
                  {
                    Description: "Trade account created",
                    Quantity: 1,
                    UnitAmount: 0,
                    AccountCode: salesAccountCode,
                  },
                ],
              },
            ],
          };

          const invoiceRes = await xeroFetchJson("https://api.xero.com/api.xro/2.0/Invoices", {
            method: "POST",
            headers: xeroHeaders,
            body: JSON.stringify(invoiceBody),
          });

          const createdInvoice = Array.isArray(invoiceRes?.Invoices) ? invoiceRes.Invoices[0] : null;
          draftInvoiceId = createdInvoice?.InvoiceID;
        } catch (e) {
          // Don't fail signup if invoice creation isn't allowed/configured.
          console.warn(`Failed to create draft invoice to force IsCustomer=true: ${String(e)}`);
        }
      }
    }

    return jsonResponse(200, {
      ok: true,
      contactId,
      updated: Boolean(existing?.ContactID),
      // Helpful for debugging Xero-side behavior; client can ignore.
      draftInvoiceId,
    });
  } catch (e) {
    console.error(`xero_upsert_contact_cc failed: ${String(e)}`);
    return jsonResponse(500, { ok: false, error: "internal_error", message: String(e) });
  }
});
