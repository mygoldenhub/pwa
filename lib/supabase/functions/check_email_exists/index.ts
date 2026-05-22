// Supabase Edge Function: check_email_exists
// Purpose: Check whether an email already exists in Supabase Auth (auth.users).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type RequestBody = { email?: string };

type ResponseBody = {
  exists: boolean;
  normalized_email?: string;
  error?: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ exists: false, error: "Method not allowed" } satisfies ResponseBody), {
      status: 405,
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(JSON.stringify({ exists: false, error: "Missing Supabase env" } satisfies ResponseBody), {
        status: 500,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const body = (await req.json().catch(() => ({}))) as RequestBody;
    const rawEmail = (body.email ?? "").toString();
    const normalized = rawEmail.trim().toLowerCase();

    if (!normalized || !normalized.includes("@")) {
      return new Response(JSON.stringify({ exists: false, error: "Invalid email" } satisfies ResponseBody), {
        status: 400,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Query auth.users via PostgREST (requires service role).
    // Note: auth.users is in the "auth" schema.
    const { data, error } = await admin
      .schema("auth")
      .from("users")
      .select("id")
      .eq("email", normalized)
      .limit(1);

    if (error) {
      return new Response(JSON.stringify({ exists: false, normalized_email: normalized, error: error.message } satisfies ResponseBody), {
        status: 500,
        headers: { ...CORS_HEADERS, "content-type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ exists: (data?.length ?? 0) > 0, normalized_email: normalized } satisfies ResponseBody), {
      status: 200,
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ exists: false, error: (e as Error)?.message ?? String(e) } satisfies ResponseBody), {
      status: 500,
      headers: { ...CORS_HEADERS, "content-type": "application/json" },
    });
  }
});
