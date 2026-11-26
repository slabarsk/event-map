// nl-search: "Bu akşam yakınımdaki ücretsiz konserler" gibi bir soruyu
// events_near RPC'sinin parametrelerine çevirir ve sonuçları döndürür.
//
// Claude ham SQL üretmez: yalnızca SearchFilter JSON'u üretir (structured
// output), bu filtre doğrulanır ve parametreli RPC'ye gider. Claude'a
// ulaşılamazsa (anahtar yok, zaman aşımı, ret) kural tabanlı ayrıştırıcı
// kullanılır; arama her durumda çalışır.
//
// İstek:  POST { query, lat?, lng?, default_radius_m? }  (Authorization: kullanıcı JWT'si)
// Yanıt:  { filter, labels, parser, needs_location, window, events }
//
// Kullanıcı konumu yalnızca bu sorguda kullanılır, saklanmaz ve loglanmaz.

import Anthropic from "npm:@anthropic-ai/sdk@1.14.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@1.14.0/helpers/zod";
import { createClient } from "npm:@supabase/supabase-js@2.119.2";
import { z } from "npm:zod@4.6.7";

import {
  CATEGORIES,
  clampRadius,
  DEFAULT_RADIUS_M,
  filterLabels,
  ruleBasedFilter,
  sanitizeFilter,
  type SearchFilter,
  TIME_WINDOWS,
  timeWindow,
} from "./filter.ts";

const MODEL = Deno.env.get("NL_SEARCH_MODEL") ?? "claude-haiku-5-5";
const MAX_QUERY_LENGTH = 300;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const FilterSchema = z.object({
  categories: z.array(z.enum(CATEGORIES)),
  free_only: z.boolean(),
  max_price: z.number().nullable(),
  time_window: z.enum(TIME_WINDOWS),
  near_me: z.boolean(),
  radius_m: z.number().nullable(),
});

const SYSTEM = `Sen İzmir etkinlik haritası uygulamasının arama ayrıştırıcısısın. Kullanıcının Türkçe (bazen İngilizce) sorusunu etkinlik filtresine çevirirsin. Yalnızca soruda açıkça istenen ya da güçlü biçimde ima edilen filtreleri doldur; tahmin yürütme.

Alanlar:
- categories: concert (konser, canlı müzik, caz, opera dışı müzik), theatre (tiyatro, opera, bale, müzikal), exhibition (sergi, müze, galeri), festival, standup (stand-up, komedi), workshop (atölye, kurs), cinema (film, gösterim), talk (söyleşi, konferans, panel), sports (spor, maç, koşu, yoga), family (çocuk, aile), party (parti, DJ), other. Kategori belirtilmemişse boş liste.
- free_only: "ücretsiz", "bedava", "parasız" gibi ifadelerde true.
- max_price: "200 TL altı", "en fazla 300 lira" gibi bir üst sınır varsa TL cinsinden sayı; yoksa null. "Ucuz" gibi belirsiz ifadeler için null.
- time_window: tonight (bu akşam, bu gece, akşam), today (bugün), tomorrow (yarın, yarın akşam), this_weekend (hafta sonu, cumartesi, pazar), this_week (bu hafta), upcoming (zaman belirtilmemiş).
- near_me: "yakınımda", "yakında", "civarda", "etrafımda", "yürüme mesafesinde" ya da bir mesafe verildiyse true. Bir semt adı (ör. Alsancak) tek başına near_me değildir.
- radius_m: mesafe verildiyse metre ("3 km" -> 3000, "yürüme mesafesi" -> 1500); yoksa null.`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/** İstanbul saatiyle "26 Kasım 2026 Perşembe 14:05" — "bu akşam" gibi ifadeler için bağlam. */
function istanbulNow(now: Date): string {
  return new Intl.DateTimeFormat("tr-TR", {
    timeZone: "Europe/Istanbul",
    dateStyle: "full",
    timeStyle: "short",
  }).format(now);
}

async function parseWithClaude(query: string, now: Date): Promise<SearchFilter | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return null;
  const client = new Anthropic({ apiKey, timeout: 8_000, maxRetries: 1 });
  try {
    const response = await client.messages.parse({
      model: MODEL,
      max_tokens: 2048,
      system: SYSTEM,
      output_config: { effort: "low", format: zodOutputFormat(FilterSchema) },
      messages: [{
        role: "user",
        content: `Şu an (İzmir): ${istanbulNow(now)}\nSoru: ${query}`,
      }],
    });
    if (response.stop_reason === "refusal" || !response.parsed_output) return null;
    return sanitizeFilter(response.parsed_output);
  } catch (error) {
    // Ayrıntı loglanır ama soru metni loglanmaz (kişisel veri içerebilir).
    if (error instanceof Anthropic.RateLimitError) {
      console.warn("nl-search: Claude rate limit, kural tabanlı ayrıştırıcıya geçiliyor");
    } else if (error instanceof Anthropic.APIError) {
      console.warn(`nl-search: Claude API hatası ${error.status}`);
    } else {
      console.warn("nl-search: Claude çağrısı başarısız", (error as Error).name);
    }
    return null;
  }
}

function coordinate(v: unknown, min: number, max: number): number | null {
  return typeof v === "number" && Number.isFinite(v) && v >= min && v <= max ? v : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const query = typeof body.query === "string" ? body.query.trim() : "";
  if (query.length === 0) return json({ error: "empty_query" }, 400);
  if (query.length > MAX_QUERY_LENGTH) return json({ error: "query_too_long" }, 400);

  const lat = coordinate(body.lat, -90, 90);
  const lng = coordinate(body.lng, -180, 180);
  const hasLocation = lat !== null && lng !== null;
  const defaultRadius = typeof body.default_radius_m === "number"
    ? clampRadius(body.default_radius_m)
    : DEFAULT_RADIUS_M;

  const now = new Date();
  const claude = await parseWithClaude(query, now);
  const filter = claude ?? ruleBasedFilter(query);
  const window = timeWindow(filter.time_window, now);
  const radius = filter.near_me ? (filter.radius_m ?? defaultRadius) : null;
  const useLocation = filter.near_me && hasLocation;

  // Kullanıcının JWT'siyle çağrılır: events_near security invoker, RLS geçerli.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data, error } = await supabase.rpc("events_near", {
    p_lat: useLocation ? lat : null,
    p_lng: useLocation ? lng : null,
    p_radius_m: radius ?? DEFAULT_RADIUS_M,
    p_from: window.from.toISOString(),
    p_to: window.to?.toISOString() ?? null,
    p_categories: filter.categories.length > 0 ? filter.categories : null,
    p_max_price: filter.free_only ? 0 : filter.max_price,
  });
  if (error) {
    console.error("nl-search: events_near hatası", error.code);
    return json({ error: "search_failed" }, 502);
  }

  return json({
    filter,
    labels: filterLabels(filter, useLocation ? radius : null),
    parser: claude ? "claude" : "rules",
    // Soru "yakınımda" diyor ama konum gelmedi: uygulama konum izni isteyip
    // aynı soruyu konumla tekrar gönderir. Bu arada şehir geneli sonuçlar döner.
    needs_location: filter.near_me && !hasLocation,
    radius_m: radius,
    window: { from: window.from.toISOString(), to: window.to?.toISOString() ?? null },
    events: data ?? [],
  });
});
