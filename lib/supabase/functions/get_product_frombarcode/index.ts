// supabase/functions/get_product_frombarcode/index.ts
//
// POST { "barcode": "9315021004205" }
// 1) Read barcode Excel files from Storage bucket Barcode_Info
// 2) Map barcode -> product code:
//      ARDEX Barcodes.xlsx: EAN/UPC -> Material
//      ROBERTS DESIGN ...xlsx: Barcode -> SKU
// 3) Load public.xero_products where code = Material/SKU
//
// Storage:
//   bucket Barcode_Info /
//     ARDEX Barcodes.xlsx
//     ROBERTS DESIGN Tile and Stone Trade Supply 10.7.26.xlsx
//
// Deploy:
//   supabase functions deploy get_product_frombarcode --project-ref psvlvrdgwtnpwwhkbqfl

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { unzipSync } from "https://esm.sh/fflate@0.8.2";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
  "content-type": "application/json; charset=utf-8",
};

const CACHE_TTL_MS = 5 * 60 * 1000;
const DEFAULT_BUCKET = "Barcode_Info";
const DEFAULT_PATHS = [
  "ARDEX Barcodes.xlsx",
  "ROBERTS DESIGN Tile and Stone Trade Supply 10.7.26.xlsx",
];

type BarcodeRow = { material: string; name: string; source: string };
type BarcodeIndex = Map<string, BarcodeRow>;

let barcodeCache: { at: number; index: BarcodeIndex; sources: string[] } | null = null;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

function asText(raw: unknown): string {
  if (raw == null) return "";
  return String(raw).trim();
}

function digitsOnly(raw: string): string {
  return raw.replace(/\D/g, "");
}

function normalizeBarcode(raw: unknown): string | null {
  const text = asText(raw);
  if (!text) return null;
  const digits = digitsOnly(text);
  return digits.length >= 8 ? digits : text.replace(/\s+/g, "");
}

function barcodeLookupKeys(barcode: string): string[] {
  const keys = new Set<string>([barcode]);
  const digits = digitsOnly(barcode);
  if (digits) keys.add(digits);
  if (digits.length === 12) keys.add(`0${digits}`);
  if (digits.length === 13 && digits.startsWith("0")) keys.add(digits.slice(1));
  return [...keys];
}

function headerKey(raw: string): string {
  return raw.toLowerCase().replace(/[^a-z0-9]+/g, "");
}

function classifyHeader(raw: string): "material" | "name" | "barcode" | null {
  const key = headerKey(raw);
  if (!key) return null;
  if (
    key === "eanupc" ||
    key === "ean" ||
    key === "upc" ||
    key === "barcode" ||
    key === "eanupccode" ||
    key === "barcodes"
  ) {
    return "barcode";
  }
  if (key === "materialname" || key === "name" || key === "description") return "name";
  // ARDEX: Material | ROBERTS: SKU — both map to xero_products.code
  if (
    key === "material" ||
    key === "materialnumber" ||
    key === "materialno" ||
    key === "materialcode" ||
    key === "sku" ||
    key === "skucode" ||
    key === "itemcode" ||
    key === "productcode" ||
    key === "code"
  ) {
    return "material";
  }
  return null;
}

function parseSharedStrings(xml: string): string[] {
  const out: string[] = [];
  const siRe = /<si\b[^>]*>([\s\S]*?)<\/si>/gi;
  let siMatch: RegExpExecArray | null;
  while ((siMatch = siRe.exec(xml))) {
    const inner = siMatch[1];
    const texts: string[] = [];
    const tRe = /<t\b[^>]*>([\s\S]*?)<\/t>/gi;
    let tMatch: RegExpExecArray | null;
    while ((tMatch = tRe.exec(inner))) {
      texts.push(decodeXml(tMatch[1]));
    }
    out.push(texts.join(""));
  }
  return out;
}

function decodeXml(raw: string): string {
  return raw
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCharCode(parseInt(n, 16)));
}

function colLetters(ref: string): string {
  const m = ref.match(/^([A-Z]+)/i);
  return (m?.[1] ?? "").toUpperCase();
}

function parseXlsxBarcodeIndex(bytes: Uint8Array, source: string): BarcodeIndex {
  const files = unzipSync(bytes);
  const decoder = new TextDecoder("utf-8");
  const read = (name: string) => {
    const file = files[name];
    if (!file) return "";
    return decoder.decode(file);
  };

  const shared = parseSharedStrings(read("xl/sharedStrings.xml"));
  const sheetName = Object.keys(files).find((k) => k.startsWith("xl/worksheets/sheet") && k.endsWith(".xml"));
  const sheetXml = sheetName ? decoder.decode(files[sheetName]) : "";
  if (!sheetXml) throw new Error("xlsx_missing_sheet");

  const rows = sheetXml.match(/<row\b[^>]*>[\s\S]*?<\/row>/gi) ?? [];
  const index: BarcodeIndex = new Map();
  let materialCol = "A";
  let nameCol = "B";
  let barcodeCol = "C";
  let headerDone = false;

  for (const rowXml of rows) {
    const cells: Record<string, string> = {};
    const cellRe = /<c\b([^>]*)>([\s\S]*?)<\/c>/gi;
    let cellMatch: RegExpExecArray | null;
    while ((cellMatch = cellRe.exec(rowXml))) {
      const attrs = cellMatch[1];
      const body = cellMatch[2];
      const ref = (attrs.match(/\br="([^"]+)"/) ?? [])[1] ?? "";
      const type = (attrs.match(/\bt="([^"]+)"/) ?? [])[1] ?? "";
      const vMatch = body.match(/<v\b[^>]*>([\s\S]*?)<\/v>/i);
      const isInline = type === "inlineStr";
      let value = "";
      if (isInline) {
        const tMatch = body.match(/<t\b[^>]*>([\s\S]*?)<\/t>/i);
        value = decodeXml(tMatch?.[1] ?? "");
      } else if (vMatch) {
        const raw = decodeXml(vMatch[1]);
        if (type === "s") {
          const i = Number(raw);
          value = Number.isFinite(i) ? (shared[i] ?? raw) : raw;
        } else {
          value = raw;
        }
      }
      if (ref) cells[colLetters(ref)] = value.trim();
    }

    if (!headerDone) {
      const classified: Record<string, "material" | "name" | "barcode"> = {};
      for (const [col, val] of Object.entries(cells)) {
        const kind = classifyHeader(val);
        if (kind) classified[col] = kind;
      }
      const kinds = new Set(Object.values(classified));
      // Need product code (Material/SKU) + Barcode columns.
      if (kinds.has("material") && kinds.has("barcode")) {
        for (const [col, kind] of Object.entries(classified)) {
          if (kind === "material") materialCol = col;
          if (kind === "name") nameCol = col;
          if (kind === "barcode") barcodeCol = col;
        }
        headerDone = true;
        continue;
      }
    }

    if (!headerDone) continue;

    const material = asText(cells[materialCol]);
    const name = asText(cells[nameCol]);
    const barcode = normalizeBarcode(cells[barcodeCol]);
    if (!material || !barcode) continue;

    const row: BarcodeRow = { material, name, source };
    for (const key of barcodeLookupKeys(barcode)) {
      if (!index.has(key)) index.set(key, row);
    }
  }

  return index;
}

async function downloadWorkbook(
  admin: SupabaseClient,
  bucket: string,
  path: string,
): Promise<Uint8Array | null> {
  const { data, error } = await admin.storage.from(bucket).download(path);
  if (error || !data) return null;
  const bytes = new Uint8Array(await data.arrayBuffer());
  return bytes.byteLength > 0 ? bytes : null;
}

function workbookPaths(): string[] {
  const envPath = Deno.env.get("BARCODE_XLSX_PATH")?.trim();
  const envExtra = Deno.env.get("BARCODE_XLSX_PATHS")?.trim();
  const paths = [...DEFAULT_PATHS];
  if (envPath && !paths.includes(envPath)) paths.unshift(envPath);
  if (envExtra) {
    for (const p of envExtra.split(",").map((s) => s.trim()).filter(Boolean)) {
      if (!paths.includes(p)) paths.push(p);
    }
  }
  return paths;
}

async function loadBarcodeIndex(admin: SupabaseClient): Promise<{ index: BarcodeIndex; sources: string[] }> {
  if (barcodeCache && Date.now() - barcodeCache.at < CACHE_TTL_MS) {
    return { index: barcodeCache.index, sources: barcodeCache.sources };
  }

  const bucket = Deno.env.get("BARCODE_XLSX_BUCKET")?.trim() || DEFAULT_BUCKET;
  const paths = workbookPaths();
  const merged: BarcodeIndex = new Map();
  const sources: string[] = [];
  const tried: string[] = [];

  for (const path of paths) {
    const source = `${bucket}/${path}`;
    tried.push(source);
    const bytes = await downloadWorkbook(admin, bucket, path);
    if (!bytes) continue;

    try {
      const part = parseXlsxBarcodeIndex(bytes, source);
      let added = 0;
      for (const [key, row] of part) {
        if (!merged.has(key)) {
          merged.set(key, row);
          added++;
        }
      }
      if (part.size > 0) sources.push(source);
      console.log(`Loaded ${part.size} barcode keys from ${source} (${added} new)`);
    } catch (e) {
      console.error(`Failed to parse ${source}:`, e);
    }
  }

  if (merged.size === 0) {
    throw new Error(`xlsx_not_found: tried ${tried.join(", ")}`);
  }

  barcodeCache = { at: Date.now(), index: merged, sources };
  return { index: merged, sources };
}

function findMappedRow(index: BarcodeIndex, barcode: string): BarcodeRow | null {
  for (const key of barcodeLookupKeys(barcode)) {
    const row = index.get(key);
    if (row) return row;
  }
  return null;
}

async function findXeroProduct(admin: SupabaseClient, material: string) {
  const code = material.trim();
  if (!code) return null;

  const select =
    "item_id, code, name, description, purchase_description, is_tracked_as_inventory, quantity_on_hand, inventory_asset_account_code, sales_details, purchase_details, updated_date_utc";

  const exact = await admin.from("xero_products").select(select).eq("code", code).maybeSingle();
  if (!exact.error && exact.data) return exact.data;

  // Case-insensitive exact match (SKU casing can vary).
  const ilike = await admin.from("xero_products").select(select).ilike("code", code).maybeSingle();
  if (!ilike.error && ilike.data) return ilike.data;

  const noZeros = code.replace(/^0+/, "");
  if (noZeros && noZeros !== code) {
    const alt = await admin.from("xero_products").select(select).eq("code", noZeros).maybeSingle();
    if (!alt.error && alt.data) return alt.data;
  }

  const padded = code.padStart(5, "0");
  if (padded !== code) {
    const alt = await admin.from("xero_products").select(select).eq("code", padded).maybeSingle();
    if (!alt.error && alt.data) return alt.data;
  }

  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed", message: "Use POST." }, 405);
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      return json({
        ok: false,
        error: "missing_env",
        message: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.",
      }, 500);
    }

    let payload: Record<string, unknown> = {};
    try {
      payload = await req.json();
    } catch {
      payload = {};
    }

    const url = new URL(req.url);
    const barcode = normalizeBarcode(payload.barcode ?? payload.code ?? url.searchParams.get("barcode"));
    if (!barcode) {
      return json({
        ok: false,
        error: "invalid_barcode",
        message: "Provide a barcode in the JSON body.",
      }, 400);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { index, sources } = await loadBarcodeIndex(admin);
    const mapped = findMappedRow(index, barcode);
    if (!mapped) {
      return json({
        ok: false,
        error: "barcode_not_mapped",
        barcode,
        sources,
        message: "This barcode was not found in ARDEX or ROBERTS barcode files.",
      });
    }

    const product = await findXeroProduct(admin, mapped.material);
    if (!product) {
      return json({
        ok: false,
        error: "product_not_found",
        barcode,
        material: mapped.material,
        materialName: mapped.name,
        source: mapped.source,
        sources,
        message: `Code ${mapped.material} was found in the barcode file, but no matching Xero product code exists.`,
      });
    }

    return json({
      ok: true,
      barcode,
      material: mapped.material,
      materialName: mapped.name,
      source: mapped.source,
      sources,
      product,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return json({
      ok: false,
      error: message.startsWith("xlsx_") ? message.split(":")[0] : "unhandled_exception",
      message,
    }, 500);
  }
});
