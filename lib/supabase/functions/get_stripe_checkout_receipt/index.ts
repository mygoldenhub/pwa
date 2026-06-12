// supabase/functions/get_stripe_checkout_receipt/index.ts

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type GetReceiptRequest = {
  sessionId?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
    if (!STRIPE_SECRET_KEY) return jsonResponse({ error: "Missing STRIPE_SECRET_KEY" }, 500);

    const payload = (await req.json()) as GetReceiptRequest;
    const sessionId = payload.sessionId?.trim();
    if (!sessionId) return jsonResponse({ error: "Missing sessionId" }, 400);

    const stripe = new (await import("https://esm.sh/stripe@14.25.0?target=deno")).default(STRIPE_SECRET_KEY, {
      apiVersion: "2023-10-16",
    });

    const session = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ["payment_intent"],
    });

    const paymentIntentId = typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id;

    // For standard one-off Checkout payments, Stripe produces a Charge with a receipt_url.
    // It may or may not produce a Stripe Invoice unless you explicitly enable invoice creation.
    let receiptUrl: string | null = null;
    let hostedInvoiceUrl: string | null = null;

    if (paymentIntentId) {
      const pi = await stripe.paymentIntents.retrieve(paymentIntentId, {
        expand: ["charges"],
      });

      const charges = (pi.charges?.data ?? []).filter(Boolean);
      if (charges.length > 0) {
        receiptUrl = charges[0].receipt_url ?? null;
      }

      // If invoice was created (optional Stripe feature), it will be on the payment intent.
      // @ts-ignore - stripe types vary across versions for this field.
      const invoiceId = (pi as any).invoice as string | undefined;
      if (invoiceId) {
        const invoice = await stripe.invoices.retrieve(invoiceId);
        hostedInvoiceUrl = (invoice as any).hosted_invoice_url ?? null;
      }
    }

    return jsonResponse({
      sessionId,
      paymentIntentId: paymentIntentId ?? null,
      receiptUrl,
      hostedInvoiceUrl,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("get_stripe_checkout_receipt error:", msg);
    return jsonResponse({ error: msg }, 500);
  }
});
