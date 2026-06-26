// lib/supabase/functions/xero_upsert_contact_cc/index.ts
//
// Updated logic (webhook-driven signup):
// 1) Receive { name, email, company, phone, pin, password }
// 2) Call Make.com webhook to create Xero contact/account and return xero_account_id
// 3) Create Supabase Auth user (email+password)
// 4) Upsert public.users profile with { name/email/company/phone/xero_account_id }
// 5) Save PIN via RPC (set_user_pin) using the new user's session
//
// IMPORTANT:
// - This function is intended to run with verify_jwt = false.
// - It uses the service role key only for user creation.
// - Profile upsert + PIN save are attempted as the newly-created user to respect RLS.
//
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type JsonRecord = Record<string, unknown>;

type SignupBody = {
  user_id?: string;
  userId?: string;
  userID?: string;

  name?: string;
  fullName?: string;
  full_name?: string;

  email?: string;

  company?: string;
  companyName?: string;
  company_name?: string;

  phone?: string;
  phoneNumber?: string;
  phone_number?: string;

  pin?: string;
  password?: string;
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

function normalizeEmail(raw: string) {
  return raw.trim().toLowerCase();
}

function pickFirstString(...values: unknown[]): string {
  for (const v of values) {
    if (typeof v === "string") {
      const s = v.trim();
      if (s) return s;
    }
  }
  return "";
}

function validatePin(pin: string) {
  const p = pin.trim();
  if (p.length < 4) throw new Error("pin must be at least 4 digits");
  if (!/^\d+$/.test(p)) throw new Error("pin must be numeric");
  return p;
}

function validatePassword(password: string) {
  const p = password.trim();
  if (p.length < 8) throw new Error("password must be at least 8 characters");

  const hasLetter = /[A-Za-z]/.test(p);
  const hasNumber = /\d/.test(p);
  if (!hasLetter || !hasNumber) throw new Error("password is too easy; use both letters and numbers");

  const common = new Set([
    "password",
    "password1",
    "qwerty",
    "qwerty123",
    "letmein",
    "admin123",
    "welcome",
    "iloveyou",
    "12345678",
    "87654321",
    "00000000",
    "11111111",
  ]);
  if (common.has(p.toLowerCase())) throw new Error("password is too easy; choose a stronger password");

  return p;
}

function safeParseJson(text: string): unknown {
  try {
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

type MakeHookResult = { status?: unknown; xero_account_id?: unknown };

function _asBoolLike(v: unknown): boolean | null {
  if (typeof v === "boolean") return v;
  if (typeof v === "number") return v !== 0;
  if (typeof v === "string") {
    const s = v.trim().toLowerCase();
    if (s === "true" || s === "1" || s === "ok" || s === "success") return true;
    if (s === "false" || s === "0" || s === "fail" || s === "failed" || s === "error") return false;
  }
  return null;
}

async function callMakeHook(params: { name: string; email: string; company: string; phone: string }): Promise<{ status: boolean | null; xeroAccountId: string }> {
  // Default to the user-provided Make.com hook base URL (without query params).
  const base =
    Deno.env.get("MAKE_HOOK_BASE_URL") ??
    "https://hook.eu1.make.com/jyjva8k9i6avqx011y3kcqf5jksrwd34";

  const url = new URL(base);
  url.searchParams.set("name", params.name);
  url.searchParams.set("email", params.email);
  url.searchParams.set("company", params.company);
  url.searchParams.set("phone", params.phone);

  const res = await fetch(url.toString(), { method: "GET" });
  const text = (await res.text()).trim();

  if (!res.ok) {
    // Avoid echoing PII; include only status and a small snippet.
    const snippet = text.length > 200 ? text.slice(0, 200) + "..." : text;
    throw new Error(`make_hook_failed status=${res.status} body=${snippet}`);
  }

  // Expected JSON: { status: "true"|"false", xero_account_id: "..." }
  // Legacy JSON variants: { xero_account_id: "..." }
  // Or plain text containing the ID.
  const parsed = safeParseJson(text);
  if (parsed && typeof parsed === "object") {
    const m = parsed as Record<string, unknown>;

    const rawStatus = (m as MakeHookResult)["status"];
    const status = _asBoolLike(rawStatus);

    const idCandidates = [
      (m as MakeHookResult)["xero_account_id"],
      m["xeroAccountId"],
      m["contact_id"],
      m["ContactID"],
      m["id"],
    ];
    for (const c of idCandidates) {
      const s = typeof c === "string" ? c.trim() : "";
      if (s) return { status, xeroAccountId: s };
    }
  }

  if (text && text.length < 200) return { status: true, xeroAccountId: text };
  throw new Error("make_hook_missing_xero_account_id");
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    if (req.method !== "POST") return jsonResponse(405, { ok: false, error: "method_not_allowed" });

    const contentType = req.headers.get("content-type") || "";
    if (!contentType.toLowerCase().includes("application/json")) {
      return jsonResponse(415, { ok: false, error: "unsupported_media_type", message: "Use application/json" });
    }

    let body: SignupBody = {};
    try {
      body = (await req.json()) as SignupBody;
    } catch {
      body = {};
    }

    const name = pickFirstString(body.name, body.fullName, body.full_name);
    const existingUserId = pickFirstString(body.user_id, body.userId, body.userID);
    const emailRaw = pickFirstString(body.email);
    const company = pickFirstString(body.company, body.companyName, body.company_name);
    const phone = pickFirstString(body.phone, body.phoneNumber, body.phone_number);
    const pin = pickFirstString(body.pin);
    const password = pickFirstString(body.password);

    if (!name) return jsonResponse(400, { ok: false, error: "invalid_request", message: "name is required" });
    if (!emailRaw) return jsonResponse(400, { ok: false, error: "invalid_request", message: "email is required" });
    if (!company) return jsonResponse(400, { ok: false, error: "invalid_request", message: "company is required" });
    if (!phone) return jsonResponse(400, { ok: false, error: "invalid_request", message: "phone is required" });

    const email = normalizeEmail(emailRaw);
    if (!email.includes("@")) return jsonResponse(400, { ok: false, error: "invalid_email" });

    const pinValidated = validatePin(pin);
    const passwordValidated = validatePassword(password);

    const supabaseUrl = requireEnv("SUPABASE_URL");
    const anonKey = requireEnv("SUPABASE_ANON_KEY");
    const serviceRole = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

    // A) Call Make webhook first, so we don't create a Supabase user if Xero fails.
    const hook = await callMakeHook({ name, email, company, phone });
    const xeroAccountId = hook.xeroAccountId;

    // If Make.com indicates a failure and specifically that the contact already exists,
    // return a deterministic error that Flutter can show to the user.
    const isHookSuccess = hook.status !== false;
    const normalizedId = (xeroAccountId ?? "").trim().toLowerCase();
    if (!isHookSuccess && (normalizedId === "contact_already_exist" || normalizedId === "contact_already_exists")) {
      return jsonResponse(409, {
        ok: false,
        error: "contact_already_exist",
        message: "Contact already exist",
        xero_account_id: xeroAccountId,
        status: hook.status,
      });
    }

    // B) Create auth user via service role (admin).
    const admin = createClient(supabaseUrl, serviceRole, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // If the client already created an Auth user via OTP (common when using
    // signInWithOtp(shouldCreateUser: true)), we'll receive the user id and we
    // should *update* that user with a password rather than trying to create
    // a new one.
    let userId = existingUserId;
    if (userId) {
      const { error: updateErr } = await admin.auth.admin.updateUserById(userId, {
        password: passwordValidated,
        email_confirm: true,
        user_metadata: { display_name: name },
      });
      if (updateErr) return jsonResponse(500, { ok: false, error: "auth_update_failed", message: updateErr.message });
    } else {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password: passwordValidated,
        email_confirm: true,
        user_metadata: { display_name: name },
      });
      if (createErr) return jsonResponse(409, { ok: false, error: "auth_create_failed", message: createErr.message });
      userId = created?.user?.id ?? "";
      if (!userId) throw new Error("auth_create_missing_user_id");
    }

    // C) Sign in as the newly-created user (anon client) to upsert profile and set PIN via RPC.
    const client = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: signInData, error: signInErr } = await client.auth.signInWithPassword({ email, password: passwordValidated });
    if (signInErr) {
      // We still created the auth user; caller can log in later.
      return jsonResponse(500, { ok: false, error: "signin_failed", message: signInErr.message, user_id: userId, xero_account_id: xeroAccountId });
    }

    // D) Upsert public.users profile (as the user, so RLS can enforce ownership).
    const now = new Date().toISOString();
    const { error: upsertErr } = await client
      .from("users")
      .upsert({
        id: userId,
        email,
        display_name: name,
        company_name: company,
        phone_number: phone,
        xero_account_id: xeroAccountId,
        updated_at: now,
      });

    // E) Save PIN (as the user) via RPC.
    const { error: pinErr } = await client.rpc("set_user_pin", { pin_input: pinValidated });

    const ok = !upsertErr && !pinErr;

    return jsonResponse(200, {
      ok,
      user_id: userId,
      xero_account_id: xeroAccountId,
      profile_saved: !upsertErr,
      pin_saved: !pinErr,
      // For debugging only; messages are safe-ish, but still avoid echoing user input.
      profile_error: upsertErr?.message ?? null,
      pin_error: pinErr?.message ?? null,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`xero_upsert_contact_cc failed: ${message}`);
    return jsonResponse(500, { ok: false, error: "unhandled_exception", message });
  }
});
