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

function safeErrorMessage(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (typeof e === "string") return e;
  if (typeof e === "number" || typeof e === "boolean") return String(e);
  try {
    return JSON.stringify(e);
  } catch {
    return String(e);
  }
}

function asError(e: unknown, context?: string): Error {
  const msg = safeErrorMessage(e);
  return new Error(context ? `${context}: ${msg}` : msg);
}

function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const normalized = raw.trim().toLowerCase();
  if (!normalized) return null;
  if (!normalized.includes("@")) return null;
  return normalized;
}

function is4DigitCode(raw: unknown): raw is string {
  return typeof raw === "string" && /^\d{4}$/.test(raw.trim());
}

function randomFourDigitCode(): string {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  const n = arr[0] % 10000;
  return String(n).padStart(4, "0");
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const hashBuf = await crypto.subtle.digest("SHA-256", bytes);
  const hashArr = Array.from(new Uint8Array(hashBuf));
  return hashArr.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function generatePassword(length = 12): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const digits = "23456789";
  const all = upper + lower + digits;

  const bytes = new Uint32Array(length);
  crypto.getRandomValues(bytes);

  // Ensure at least one from each group.
  const pick = (chars: string, b: number) => chars[b % chars.length];
  const out: string[] = [
    pick(upper, bytes[0]),
    pick(lower, bytes[1]),
    pick(digits, bytes[2]),
  ];

  for (let i = out.length; i < length; i++) out.push(pick(all, bytes[i]));

  // Shuffle.
  for (let i = out.length - 1; i > 0; i--) {
    const j = bytes[i] % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }

  return out.join("");
}

async function sendResendEmail({ to, subject, text }: { to: string; subject: string; text: string }) {
  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
  const RESEND_FROM_EMAIL = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
  const APP_NAME = (Deno.env.get("APP_NAME") ?? "App").trim();

  if (!RESEND_API_KEY || !RESEND_FROM_EMAIL) {
    throw new Error("Missing RESEND_API_KEY or RESEND_FROM_EMAIL in Edge Function environment.");
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: `${APP_NAME} <${RESEND_FROM_EMAIL}>`,
      to: [to],
      subject,
      text,
    }),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    throw new Error(`Resend email failed (${res.status}): ${errText}`);
  }
}

async function sendSendgridEmail({ to, subject, text }: { to: string; subject: string; text: string }) {
  // Env vars expected to be set in Supabase Edge Function secrets.
  // - SENDGRID_API_KEY: SendGrid API key
  // - SENDGRID_FROM_EMAIL: Verified sender email in SendGrid
  // - APP_NAME (optional): used as sender name
  const SENDGRID_API_KEY = Deno.env.get("SENDGRID_API_KEY") ?? "";
  const SENDGRID_FROM_EMAIL = Deno.env.get("SENDGRID_FROM_EMAIL") ?? "";
  const APP_NAME = (Deno.env.get("APP_NAME") ?? "App").trim();

  if (!SENDGRID_API_KEY || !SENDGRID_FROM_EMAIL) {
    throw new Error("Missing SENDGRID_API_KEY or SENDGRID_FROM_EMAIL in Edge Function environment.");
  }

  const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      authorization: `Bearer ${SENDGRID_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: SENDGRID_FROM_EMAIL, name: APP_NAME },
      subject,
      content: [{ type: "text/plain", value: text }],
    }),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    throw new Error(`SendGrid email failed (${res.status}): ${errText}`);
  }
}

async function sendEmail({ to, subject, text }: { to: string; subject: string; text: string }) {
  // Prefer SendGrid if configured, otherwise fall back to Resend.
  // This makes the function work in projects that already use SendGrid.
  const hasSendgrid = !!(Deno.env.get("SENDGRID_API_KEY") && Deno.env.get("SENDGRID_FROM_EMAIL"));
  if (hasSendgrid) return await sendSendgridEmail({ to, subject, text });
  return await sendResendEmail({ to, subject, text });
}

async function loadUserRowByEmail(admin: any, email: string): Promise<{ id: string; email: string } | null> {
  const { data, error } = await admin.from("users").select("id,email").eq("email", email).maybeSingle();
  if (error) throw asError(error, 'Failed to read from "users" table');
  if (!data) return null;
  const id = (data as any).id?.toString() ?? "";
  const em = (data as any).email?.toString() ?? "";
  if (!id || !em) return null;
  return { id, email: em };
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

    const action = (payload?.action ?? "").toString().trim();
    const email = normalizeEmail(payload?.email);

    if (!email) {
      return json({ ok: false, error: "invalid_email", message: "Provide a valid 'email'." }, 400);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    if (action === "send_code") {
      const userRow = await loadUserRowByEmail(admin, email);
      if (!userRow) {
        return json({ ok: false, error: "not_found", message: "No account found for this email." }, 404);
      }

      const code = randomFourDigitCode();
      const codeHash = await sha256Hex(code);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

      // Store the code hash on the user's profile row (no separate password_reset_codes table).
      const { error: updErr } = await admin
        .from("users")
        .update({ reset_code_hash: codeHash, reset_code_expires_at: expiresAt, updated_at: new Date().toISOString() })
        .eq("id", userRow.id);
      if (updErr) throw asError(updErr, 'Failed to update reset_code fields in "users"');

      await sendEmail({
        to: email,
        subject: "Your password reset code",
        text: `Your verification code is: ${code}\n\nThis code expires in 10 minutes.`,
      });

      return json({ ok: true, email });
    }

    if (action === "reset_password") {
      const codeRaw = payload?.code;
      const code = typeof codeRaw === "string" ? codeRaw.trim() : "";
      if (!is4DigitCode(code)) {
        return json({ ok: false, error: "invalid_code", message: "Please provide the 4-digit code." }, 400);
      }

      const userRow = await loadUserRowByEmail(admin, email);
      if (!userRow) return json({ ok: false, error: "not_found", message: "No account found for this email." }, 404);

      const { data: row, error: rowError } = await admin
        .from("users")
        .select("id,email,reset_code_hash,reset_code_expires_at")
        .eq("id", userRow.id)
        .maybeSingle();

      if (rowError) throw asError(rowError, 'Failed to load reset code fields from "users"');
      if (!row) return json({ ok: false, error: "not_found", message: "No account found for this email." }, 404);

      const codeHashStored = (row as any).reset_code_hash?.toString() ?? "";
      const expiresAtIso = (row as any).reset_code_expires_at?.toString() ?? "";
      if (!codeHashStored || !expiresAtIso) {
        return json({ ok: false, error: "code_missing", message: "Please request a new code." }, 400);
      }

      const expiresAtMs = Date.parse(expiresAtIso);
      if (!Number.isFinite(expiresAtMs) || Date.now() > expiresAtMs) {
        await admin
          .from("users")
          .update({ reset_code_hash: null, reset_code_expires_at: null, updated_at: new Date().toISOString() })
          .eq("id", userRow.id);
        return json({ ok: false, error: "expired", message: "Code expired. Please request a new code." }, 400);
      }

      const hash = await sha256Hex(code);
      if (hash !== codeHashStored) {
        return json({ ok: false, error: "mismatch", message: "Incorrect code." }, 400);
      }

      const newPassword = generatePassword(12);

      // Keep Supabase Auth in sync (login uses supabase auth).
      const { error: updError } = await admin.auth.admin.updateUserById(userRow.id, { password: newPassword });
      if (updError) throw asError(updError, "Failed to update Supabase Auth password");

      // Generate a new 4-digit PIN and update the profile row.
      // NOTE: This project verifies PIN via an RPC (`verify_user_pin`). In most setups,
      // pin_hash is SHA-256 hex of the 4-digit PIN. If your RPC uses a different
      // hashing scheme, update this accordingly.
      const newPin = randomFourDigitCode();
      const newPinHash = await sha256Hex(newPin);

      const { error: profileUpdError } = await admin
        .from("users")
        .update({
          // Optional columns; they must exist in the DB.
          pin_hash: newPinHash,
          reset_code_hash: null,
          reset_code_expires_at: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", userRow.id);
      if (profileUpdError) throw asError(profileUpdError, 'Failed to update "users" profile (pin_hash/reset_code fields)');

      await sendEmail({
        to: email,
        subject: "Your new password and PIN",
        text:
          `Your password has been reset.\n\n` +
          `New password: ${newPassword}\n` +
          `New PIN: ${newPin}\n\n` +
          `Please sign in and change them in Account settings.`,
      });

      return json({ ok: true, email });
    }

    // New flow: code is sent/verified by Supabase Auth email OTP (SMTP).
    // After the client verifies OTP, it calls this action to generate+email
    // the new password and PIN.
    if (action === "finalize_reset") {
      const userRow = await loadUserRowByEmail(admin, email);
      if (!userRow) return json({ ok: false, error: "not_found", message: "No account found for this email." }, 404);

      const newPassword = generatePassword(12);

      // Keep Supabase Auth in sync (login uses supabase auth).
      const { error: updError } = await admin.auth.admin.updateUserById(userRow.id, { password: newPassword });
      if (updError) throw asError(updError, "Failed to update Supabase Auth password");

      const newPin = randomFourDigitCode();
      const newPinHash = await sha256Hex(newPin);

      const { error: profileUpdError } = await admin
        .from("users")
        .update({
          pin_hash: newPinHash,
          // Best-effort cleanup if those columns exist.
          reset_code_hash: null,
          reset_code_expires_at: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", userRow.id);
      if (profileUpdError) throw asError(profileUpdError, 'Failed to update "users" profile (pin_hash)');

      await sendEmail({
        to: email,
        subject: "Your new password and PIN",
        text:
          `Your password has been reset.\n\n` +
          `New password: ${newPassword}\n` +
          `New PIN: ${newPin}\n\n` +
          `Please sign in and change them in Account settings.`,
      });

      return json({ ok: true, email });
    }

    return json({ ok: false, error: "invalid_action", message: "Invalid action." }, 400);
  } catch (e) {
    // Ensure the client receives a readable message (and not "[object Object]").
    console.error("reset_password_code unhandled error", e);
    return json(
      {
        ok: false,
        error: "unhandled_exception",
        message: safeErrorMessage(e),
      },
      500,
    );
  }
});
