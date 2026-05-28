// Supabase Edge Function: xero_upsert_contact
// - Requires an authenticated Supabase user (default verify_jwt=true).
// - Uses Xero OAuth2 refresh token flow to get an access token.
// - Searches for an existing Contact by EmailAddress, else creates it.
// - If found, can optionally update missing Company/Phone fields.
// - Returns { contactId, existed }.

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

function json(data: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(data), {
    status: init.status ?? 200,
    headers: { "content-type": "application/json; charset=utf-8", ...CORS_HEADERS, ...(init.headers ?? {}) },
  });
}

function requireEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v || v.trim() === "") throw new Error(`Missing environment variable: ${name}`);
  return v;
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

async function getXeroAccessToken(): Promise<string> {
  const clientId = requireEnv("XERO_CLIENT_ID");
  const clientSecret = requireEnv("XERO_CLIENT_SECRET");
  const refreshToken = requireEnv("XERO_REFRESH_TOKEN");

  const basic = btoa(`${clientId}:${clientSecret}`);

  const body = new URLSearchParams();
  body.set("grant_type", "refresh_token");
  body.set("refresh_token", refreshToken);

  const res = await fetch("https://identity.xero.com/connect/token", {
    method: "POST",
    headers: {
      authorization: `Basic ${basic}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body,
  });

  const raw = await res.text();
  if (!res.ok) {
    throw new Error(`Xero token request failed (${res.status}): ${raw}`);
  }

  let parsed: any;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`Xero token response was not JSON: ${raw}`);
  }

  const accessToken = parsed?.access_token;
  if (typeof accessToken !== "string" || accessToken.trim() === "") {
    throw new Error(`Xero token response missing access_token: ${raw}`);
  }

  // NOTE: Xero rotates refresh_token on refresh. For production you should store the new refresh_token.
  // Xero returns it as parsed.refresh_token. In this template, we keep a fixed refresh token.
  return accessToken;
}

async function xeroFetchJson(url: string, accessToken: string): Promise<any> {
  const tenantId = requireEnv("XERO_TENANT_ID");
  const res = await fetch(url, {
    headers: {
      authorization: `Bearer ${accessToken}`,
      "xero-tenant-id": tenantId,
      accept: "application/json",
    },
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`Xero API failed (${res.status}): ${raw}`);
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error(`Xero API response was not JSON: ${raw}`);
  }
}

async function xeroPostJson(url: string, accessToken: string, body: unknown): Promise<any> {
  const tenantId = requireEnv("XERO_TENANT_ID");
  const res = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "xero-tenant-id": tenantId,
      accept: "application/json",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`Xero API failed (${res.status}): ${raw}`);
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error(`Xero API response was not JSON: ${raw}`);
  }
}

function safeStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function pickContactId(resp: any): string | null {
  const contacts = Array.isArray(resp?.Contacts) ? resp.Contacts : [];
  const id = contacts[0]?.ContactID;
  return typeof id === "string" && id.trim() !== "" ? id.trim() : null;
}

function firstName(fullName: string): string {
  const parts = fullName.split(" ").filter(Boolean);
  return parts[0] ?? fullName;
}

function lastName(fullName: string): string {
  const parts = fullName.split(" ").filter(Boolean);
  return parts.length > 1 ? parts.slice(1).join(" ") : "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

  try {
    const payload = await req.json().catch(() => ({}));
    const fullName = safeStr(payload?.full_name);
    const email = normalizeEmail(safeStr(payload?.email));
    const companyName = safeStr(payload?.company_name);
    const phoneNumber = safeStr(payload?.phone_number);

    if (!fullName) return json({ error: "full_name is required" }, { status: 400 });
    if (!email || !email.includes("@")) return json({ error: "Valid email is required" }, { status: 400 });

    const accessToken = await getXeroAccessToken();

    // 1) Try find by email.
    // Xero 'where' syntax: EmailAddress=="test@example.com"
    const where = `EmailAddress==\"${email.replaceAll('"', '')}\"`;
    const searchUrl = `https://api.xero.com/api.xro/2.0/Contacts?where=${encodeURIComponent(where)}`;
    const found = await xeroFetchJson(searchUrl, accessToken);

    const contacts = Array.isArray(found?.Contacts) ? found.Contacts : [];
    if (contacts.length > 0 && typeof contacts[0]?.ContactID === "string") {
      const existing = contacts[0];
      const contactId = safeStr(existing?.ContactID);

      // Optionally enrich an existing contact with missing phone / name.
      // (We do NOT overwrite data if Xero already has it.)
      const existingPhones = Array.isArray(existing?.Phones) ? existing.Phones : [];
      const hasAnyPhone = existingPhones.some((p: any) => safeStr(p?.PhoneNumber) !== "");

      const shouldUpdate = (!safeStr(existing?.Name) && fullName) || (!hasAnyPhone && phoneNumber);
      if (shouldUpdate) {
        const updateBody = {
          Contacts: [
            {
              ContactID: contactId,
              // If Xero already has a Name we keep it; only fill if missing.
              ...(safeStr(existing?.Name) ? {} : { Name: companyName ? `${companyName} (${fullName})` : fullName }),
              ...(safeStr(existing?.FirstName) ? {} : { FirstName: firstName(fullName) }),
              ...(safeStr(existing?.LastName) ? {} : { LastName: lastName(fullName) }),
              ...(hasAnyPhone || !phoneNumber
                ? {}
                : {
                    Phones: [
                      {
                        PhoneType: "MOBILE",
                        PhoneNumber: phoneNumber,
                      },
                    ],
                  }),
            },
          ],
        };
        await xeroPostJson("https://api.xero.com/api.xro/2.0/Contacts", accessToken, updateBody);
      }

      return json({ contactId, existed: true });
    }

    // 2) Create new contact.
    const createBody = {
      Contacts: [
        {
          Name: companyName ? `${companyName} (${fullName})` : fullName,
          FirstName: firstName(fullName),
          LastName: lastName(fullName),
          EmailAddress: email,
          Phones: phoneNumber
            ? [
                {
                  PhoneType: "MOBILE",
                  PhoneNumber: phoneNumber,
                },
              ]
            : [],
        },
      ],
    };

    const created = await xeroPostJson("https://api.xero.com/api.xro/2.0/Contacts", accessToken, createBody);
    const contactId = pickContactId(created);
    if (!contactId) {
      throw new Error(`Xero did not return ContactID: ${JSON.stringify(created)}`);
    }

    return json({ contactId, existed: false });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // Avoid leaking secrets; message is already high-level.
    return json({ error: msg }, { status: 500 });
  }
});
