/// Supabase Edge Function: xero_upsert_contact_cc
///
/// End-to-end flow:
/// 1) Validate request + parse { fullName, email, companyName, phoneNumber }
/// 2) Get stored refresh token from Postgres table public.xero_oauth_tokens
/// 3) Refresh -> access token (and rotate refresh token back into Postgres)
/// 4) Find contact by EmailAddress (across ALL contacts)
/// 5) If exists: UPDATE it (set IsCustomer=true + update fields)
///    Else: CREATE it (IsCustomer=true)
/// 6) Return { contactId }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type JsonRecord = Record<string, unknown>;

type UpsertRequestBody = {
  fullName?: string;
  email?: string;
  companyName?: string;
  phoneNumber?: string;
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

async function getSupabaseUserId(req: Request): Promise<string | null> {
  // Works only if verify_jwt=true in supabase/functions/config.toml.
  const auth = req.headers.get("authorization") || "";
  if (!auth.toLowerCase().startsWith("bearer ")) return null;
  const jwt = auth.slice("bearer ".length).trim();
  return decodeJwtPayloadSub(jwt);
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

    const contentType = req.headers.get("content-type") || "";
    if (!contentType.toLowerCase().includes("application/json")) {
      return jsonResponse(415, { error: "unsupported_media_type", message: "Use application/json" });
    }

    const body = (await req.json()) as UpsertRequestBody;

    const fullName = (body.fullName || "").trim();
    const emailRaw = (body.email || "").trim();
    const companyName = (body.companyName || "").trim();
    const phoneNumber = (body.phoneNumber || "").trim();

    if (!emailRaw) return jsonResponse(400, { error: "invalid_request", message: "email is required" });

    const email = normalizeEmail(emailRaw);
    const { firstName, lastName } = splitName(fullName || companyName || email);

    // Predetermined credentials (you can override by setting secrets in Supabase)
    const clientId = Deno.env.get("XERO_CLIENT_ID") || "3822E9EC26CC43AC804282846A7F0BFD";
    const clientSecret = Deno.env.get("XERO_CLIENT_SECRET") || "28amYbNd_0y3uahXnQu0IVLHurEZjPK-grRkQgfJCasFcZyN";
    const tenantId = Deno.env.get("XERO_TENANT_ID") || "9b0a4fda-f084-4da6-a5ea-d58b26035931";

    // Supabase DB connection for token storage
    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceRole = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

    // 1) Read refresh token from Postgres
    const tokenRow = await fetch(`${supabaseUrl}/rest/v1/xero_oauth_tokens?id=eq.default&select=refresh_token`, {
      method: "GET",
      headers: {
        apikey: serviceRole,
        authorization: `Bearer ${serviceRole}`,
      },
    });

    if (!tokenRow.ok) {
      const t = await tokenRow.text();
      throw new Error(`Failed to read refresh token from Supabase: ${tokenRow.status} :: ${t}`);
    }

    const tokenJson = (await tokenRow.json()) as Array<{ refresh_token?: string }>;
    const refreshToken = tokenJson?.[0]?.refresh_token;
    if (!refreshToken) {
      return jsonResponse(500, {
        error: "missing_refresh_token",
        message:
          "No refresh_token found in public.xero_oauth_tokens for id=default. Insert an initial refresh token first.",
      });
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

    if (rotatedRefreshToken && rotatedRefreshToken !== refreshToken) {
      const upsertRes = await fetch(`${supabaseUrl}/rest/v1/xero_oauth_tokens`, {
        method: "POST",
        headers: {
          apikey: serviceRole,
          authorization: `Bearer ${serviceRole}`,
          "content-type": "application/json",
          Prefer: "resolution=merge-duplicates",
        },
        body: JSON.stringify({ id: "default", refresh_token: rotatedRefreshToken, updated_at: new Date().toISOString() }),
      });
      if (!upsertRes.ok) {
        const t = await upsertRes.text();
        throw new Error(`Failed to rotate refresh token in Supabase: ${upsertRes.status} :: ${t}`);
      }
    }

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

    if (existing?.ContactID) {
      const updateBody: any = {
        Contacts: [
          {
            ContactID: existing.ContactID,
            Name: desiredName,
            FirstName: firstName,
            LastName: lastName,
            EmailAddress: email,
            IsCustomer: true,
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
    }

    // Optional user sync (best-effort)
    const userId = await getSupabaseUserId(req);
    if (userId) {
      try {
        const patchRes = await fetch(`${supabaseUrl}/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
          method: "PATCH",
          headers: {
            apikey: serviceRole,
            authorization: `Bearer ${serviceRole}`,
            "content-type": "application/json",
            Prefer: "return=minimal",
          },
          body: JSON.stringify({ xero_account_id: contactId }),
        });
        if (!patchRes.ok) {
          const t = await patchRes.text();
          console.warn(`Failed to sync users.xero_account_id: ${patchRes.status} :: ${t}`);
        }
      } catch (e) {
        console.warn(`Failed to sync users.xero_account_id: ${String(e)}`);
      }
    }

    return jsonResponse(200, { ok: true, contactId, updated: Boolean(existing?.ContactID) });
  } catch (e) {
    console.error(`xero_upsert_contact_cc failed: ${String(e)}`);
    return jsonResponse(500, { ok: false, error: "internal_error", message: String(e) });
  }
});
