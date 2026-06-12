// supabase/functions/create_stripe_checkout_session/index.ts

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type CreateSessionRequest = {
  currency?: string;
  reference?: string;
  invoiceId?: string;
  // URL to return to after Stripe completes/cancels.
  // If not provided, the function will attempt to infer from Origin header,
  // falling back to CHECKOUT_BASE_URL env.
  successUrl?: string;
  cancelUrl?: string;
  // Optional precomputed totals (cents). If provided, will be used to create a single line item.
  amountCents?: number;
  // Preferred: pass cart line items for clearer Stripe UI.
  lineItems?: Array<{ name: string; unitAmountCents: number; quantity: number }>;
  customerEmail?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

function pickBaseUrl(req: Request): string | null {
  const origin = req.headers.get("origin")?.trim();
  if (origin) return origin;
  const referer = req.headers.get("referer")?.trim();
  if (referer) {
    try {
      const u = new URL(referer);
      return u.origin;
    } catch {
      // ignore
    }
  }
  const fallback = Deno.env.get("CHECKOUT_BASE_URL")?.trim();
  return fallback && fallback.length > 0 ? fallback : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
    if (!STRIPE_SECRET_KEY) return jsonResponse({ error: "Missing STRIPE_SECRET_KEY" }, 500);

    const payload = (await req.json()) as CreateSessionRequest;
    const currency = (payload.currency ?? "AUD").toLowerCase();

    const baseUrl = pickBaseUrl(req);
    // Bring the user back into the app after payment so we can show the Stripe receipt/invoice.
    // NOTE: go_router is hash-based on web here, so we use /#/...
    const inferredSuccess = baseUrl ? `${baseUrl}/#/app/stripe/success?session_id={CHECKOUT_SESSION_ID}` : null;
    const inferredCancel = baseUrl ? `${baseUrl}/#/app/cart` : null;

    const successUrl = payload.successUrl?.trim() || inferredSuccess;
    const cancelUrl = payload.cancelUrl?.trim() || inferredCancel;
    if (!successUrl || !cancelUrl) {
      return jsonResponse(
        {
          error:
            "Missing successUrl/cancelUrl and could not infer base URL. Provide successUrl/cancelUrl in request, or set CHECKOUT_BASE_URL secret.",
        },
        400,
      );
    }

    const stripe = new (await import("https://esm.sh/stripe@14.25.0?target=deno"))
      .default(STRIPE_SECRET_KEY, { apiVersion: "2023-10-16" });

    const metadata: Record<string, string> = {};
    if (payload.reference?.trim()) metadata.reference = payload.reference.trim();
    if (payload.invoiceId?.trim()) metadata.invoice_id = payload.invoiceId.trim();

    const line_items = (() => {
      const items = payload.lineItems?.filter((i) => i && i.name && i.unitAmountCents > 0 && i.quantity > 0) ?? [];
      if (items.length > 0) {
        return items.map((i) => ({
          quantity: i.quantity,
          price_data: {
            currency,
            unit_amount: i.unitAmountCents,
            product_data: { name: i.name.slice(0, 120) },
          },
        }));
      }
      const amount = Math.floor(payload.amountCents ?? 0);
      if (amount <= 0) throw new Error("Either lineItems or a positive amountCents is required.");
      return [
        {
          quantity: 1,
          price_data: {
            currency,
            unit_amount: amount,
            product_data: { name: payload.reference?.trim() ? `Invoice: ${payload.reference.trim()}` : "Invoice payment" },
          },
        },
      ];
    })();

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      success_url: successUrl,
      cancel_url: cancelUrl,
      line_items,
      metadata,
      customer_email: payload.customerEmail?.trim() || undefined,
      // Let Stripe collect address if needed later; keep minimal for now.
      billing_address_collection: "auto",
    });

    if (!session.url) return jsonResponse({ error: "Stripe session missing url" }, 500);

    return jsonResponse({ url: session.url, id: session.id });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("create_stripe_checkout_session error:", msg);
    return jsonResponse({ error: msg }, 500);
  }
});
