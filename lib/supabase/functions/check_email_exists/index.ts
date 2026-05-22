// supabase/functions/check_email_exists/index.ts
// Checks if an email is already registered in Supabase Auth.
// Returns: { ok: true, email: string, exists: boolean }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
  "content-type": "application/json; charset=utf-8",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const normalized = raw.trim().toLowerCase();
  if (!normalized) return null;
  if (!normalized.includes("@")) return null;
  return normalized;
}

async function emailExistsByListingUsers(admin: any, email: string): Promise<boolean> {
  // Paginate listUsers() and match exact email.
  const perPage = 1000;
  const maxPages = 10; // scans up to 10k users.

  for (let page = 1; page <= maxPages; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;

    const users = data?.users ?? [];
    if (users.some((u: any) => (u.email ?? "").toLowerCase() === email)) return true;
    if (users.length < perPage) return false;
  }

  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed", message: "Use POST." }, 405);

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      return json(
        {
          ok: false,
          error: "missing_env",
          message: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in Edge Function environment.",
        },
        500,
      );
    }

    let payload: any = {};
    try {
      payload = await req.json();
    } catch {
      payload = {};
    }

    const url = new URL(req.url);
    const email = normalizeEmail(payload?.email ?? url.searchParams.get("email"));

    if (!email) {
      return json(
        {
          ok: false,
          error: "invalid_email",
          message: "Provide a valid 'email' in JSON body or query string.",
        },
        400,
      );
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const exists = await emailExistsByListingUsers(admin, email);
    return json({ ok: true, email, exists });
  } catch (e) {
    return json(
      {
        ok: false,
        error: "unhandled_exception",
        message: e instanceof Error ? e.message : String(e),
      },
      500,
    );
  }
});
