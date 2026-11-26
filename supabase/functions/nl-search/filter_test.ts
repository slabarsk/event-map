// Çalıştırma: deno test supabase/functions
import { assertEquals } from "jsr:@std/assert@1";

import { filterLabels, normalize, ruleBasedFilter, sanitizeFilter, timeWindow } from "./filter.ts";

// İzmir saatiyle (UTC+3) bir an.
const ist = (iso: string) => new Date(`${iso}+03:00`);

Deno.test("normalize Türkçe harfleri sadeleştirir", () => {
  assertEquals(normalize("  Bu AKŞAM İzmir'de ÜCRETSİZ "), "bu aksam izmir'de ucretsiz");
});

Deno.test("demo sorgusu: bu akşam yakınımdaki ücretsiz konserler", () => {
  assertEquals(ruleBasedFilter("Bu akşam yakınımdaki ücretsiz konserler"), {
    categories: ["concert"],
    free_only: true,
    max_price: 0,
    time_window: "tonight",
    near_me: true,
    radius_m: null,
  });
});

Deno.test("yarın akşam yarın olarak okunur", () => {
  const f = ruleBasedFilter("yarın akşam tiyatro");
  assertEquals(f.time_window, "tomorrow");
  assertEquals(f.categories, ["theatre"]);
  assertEquals(f.near_me, false);
});

Deno.test("fiyat, mesafe ve hafta sonu", () => {
  const f = ruleBasedFilter("hafta sonu 3 km içinde 200 TL altı çocuk etkinliği");
  assertEquals(f.time_window, "this_weekend");
  assertEquals(f.categories, ["family"]);
  assertEquals(f.max_price, 200);
  assertEquals(f.free_only, false);
  assertEquals(f.near_me, true);
  assertEquals(f.radius_m, 3000);
});

Deno.test("₺ işaretiyle fiyat", () => {
  assertEquals(ruleBasedFilter("300₺ altı stand-up").max_price, 300);
  assertEquals(ruleBasedFilter("300₺ altı stand-up").categories, ["standup"]);
});

Deno.test("pazartesi hafta sonu sayılmaz", () => {
  assertEquals(ruleBasedFilter("pazartesi sergi").time_window, "upcoming");
});

Deno.test("sanitizeFilter bilinmeyen değerleri atar ve sınırlar", () => {
  assertEquals(
    sanitizeFilter({
      categories: ["concert", "concert", "opera", 3],
      free_only: "evet",
      max_price: -5,
      time_window: "next_year",
      near_me: true,
      radius_m: 999999,
    }),
    {
      categories: ["concert"],
      free_only: false,
      max_price: null,
      time_window: "upcoming",
      near_me: true,
      radius_m: 50000,
    },
  );
  assertEquals(sanitizeFilter(null).time_window, "upcoming");
  assertEquals(sanitizeFilter({ max_price: 0 }).free_only, true);
});

Deno.test("bu akşam: öğleden sonra 17:00–03:00", () => {
  const w = timeWindow("tonight", ist("2026-11-26T14:00:00"));
  assertEquals(w.from, ist("2026-11-26T17:00:00"));
  assertEquals(w.to, ist("2026-11-27T03:00:00"));
});

Deno.test("bu akşam: 21:00'de şu andan başlar", () => {
  const now = ist("2026-11-26T21:00:00");
  const w = timeWindow("tonight", now);
  assertEquals(w.from, now);
  assertEquals(w.to, ist("2026-11-27T03:00:00"));
});

Deno.test("bu akşam: gece 01:00'de önceki akşamın devamı", () => {
  const now = ist("2026-11-27T01:00:00");
  const w = timeWindow("tonight", now);
  assertEquals(w.from, now);
  assertEquals(w.to, ist("2026-11-27T03:00:00"));
});

Deno.test("yarın ve bugün", () => {
  const now = ist("2026-11-26T10:00:00");
  assertEquals(timeWindow("today", now), { from: now, to: ist("2026-11-27T00:00:00") });
  assertEquals(timeWindow("tomorrow", now), {
    from: ist("2026-11-27T00:00:00"),
    to: ist("2026-11-28T00:00:00"),
  });
});

Deno.test("hafta sonu: perşembe günü cuma 17:00–pazartesi", () => {
  // 26 Kasım 2026 Perşembe.
  const w = timeWindow("this_weekend", ist("2026-11-26T10:00:00"));
  assertEquals(w.from, ist("2026-11-27T17:00:00"));
  assertEquals(w.to, ist("2026-11-30T00:00:00"));
});

Deno.test("hafta sonu: cumartesi günü şu andan pazartesiye", () => {
  const now = ist("2026-11-28T12:00:00");
  const w = timeWindow("this_weekend", now);
  assertEquals(w.from, now);
  assertEquals(w.to, ist("2026-11-30T00:00:00"));
});

Deno.test("hafta sonu: pazar günü", () => {
  const now = ist("2026-11-29T12:00:00");
  assertEquals(timeWindow("this_weekend", now).to, ist("2026-11-30T00:00:00"));
});

Deno.test("bu hafta pazar gecesine kadar", () => {
  const now = ist("2026-11-24T09:00:00"); // Salı
  assertEquals(timeWindow("this_week", now).to, ist("2026-11-30T00:00:00"));
  assertEquals(timeWindow("upcoming", now), { from: now, to: null });
});

Deno.test("etiketler", () => {
  const f = ruleBasedFilter("bu akşam yakınımdaki ücretsiz konserler");
  assertEquals(filterLabels(f, 5000), ["Bu akşam", "Konser", "Ücretsiz", "5 km içinde"]);
  assertEquals(filterLabels({ ...f, near_me: false }, null), ["Bu akşam", "Konser", "Ücretsiz"]);
  assertEquals(filterLabels({ ...f, free_only: false, max_price: 250 }, 1500), [
    "Bu akşam",
    "Konser",
    "250 ₺ altı",
    "1,5 km içinde",
  ]);
});
