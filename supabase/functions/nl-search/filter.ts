// "Near me tonight" araması için saf mantık: filtre şeması, doğrulama,
// zaman pencereleri ve Claude'a ulaşılamadığında kullanılan kural tabanlı
// ayrıştırıcı. Deno API'si kullanmaz; filter.test.ts ile test edilir.

export const CATEGORIES = [
  "concert",
  "theatre",
  "exhibition",
  "festival",
  "standup",
  "workshop",
  "cinema",
  "talk",
  "sports",
  "family",
  "party",
  "other",
] as const;
export type Category = (typeof CATEGORIES)[number];

export const TIME_WINDOWS = [
  "tonight",
  "today",
  "tomorrow",
  "this_weekend",
  "this_week",
  "upcoming",
] as const;
export type TimeWindow = (typeof TIME_WINDOWS)[number];

/** Claude'un ürettiği ve events_near RPC'sine çevrilen filtre. */
export interface SearchFilter {
  categories: Category[];
  free_only: boolean;
  max_price: number | null;
  time_window: TimeWindow;
  near_me: boolean;
  radius_m: number | null;
}

export const DEFAULT_RADIUS_M = 5000;
export const MIN_RADIUS_M = 500;
export const MAX_RADIUS_M = 50000;

/**
 * "Bu akşam" tanımı: 17:00'den gece 03:00'e kadar (İzmir saati). O saatten
 * sonra açılan sorguda pencere şu andan başlar.
 */
export const TONIGHT_START_HOUR = 17;
export const NIGHT_END_HOUR = 3;

/** Türkiye 2016'dan beri sabit UTC+3. */
const ISTANBUL_OFFSET_MS = 3 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** Model çıktısını ya da istemci girdisini güvenli bir filtreye çevirir. */
export function sanitizeFilter(raw: unknown): SearchFilter {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const categories = Array.isArray(o.categories)
    ? [...new Set(o.categories.filter((c): c is Category => CATEGORIES.includes(c as Category)))]
    : [];
  const window = TIME_WINDOWS.includes(o.time_window as TimeWindow)
    ? (o.time_window as TimeWindow)
    : "upcoming";
  const price = typeof o.max_price === "number" && Number.isFinite(o.max_price) && o.max_price >= 0
    ? Math.round(o.max_price)
    : null;
  const radius = typeof o.radius_m === "number" && Number.isFinite(o.radius_m)
    ? clampRadius(o.radius_m)
    : null;
  const freeOnly = o.free_only === true || price === 0;
  return {
    categories,
    free_only: freeOnly,
    max_price: freeOnly ? 0 : price,
    time_window: window,
    near_me: o.near_me === true,
    radius_m: radius,
  };
}

export function clampRadius(m: number): number {
  return Math.min(MAX_RADIUS_M, Math.max(MIN_RADIUS_M, Math.round(m)));
}

/** İstanbul duvar saatiyle günün başlangıcı (UTC anı olarak). */
function istanbulDayStart(now: Date): number {
  const local = now.getTime() + ISTANBUL_OFFSET_MS;
  return Math.floor(local / DAY_MS) * DAY_MS - ISTANBUL_OFFSET_MS;
}

/** 0 = Pazar … 6 = Cumartesi, İstanbul saatine göre. */
function istanbulWeekday(now: Date): number {
  return new Date(now.getTime() + ISTANBUL_OFFSET_MS).getUTCDay();
}

export interface Window {
  from: Date;
  to: Date | null;
}

/**
 * Zaman penceresi. events_near'da `from`: bu andan sonra biten (ya da devam
 * eden) etkinlikler, `to`: bu andan önce başlayanlar.
 */
export function timeWindow(window: TimeWindow, now: Date): Window {
  const day = istanbulDayStart(now);
  const at = (t: number) => new Date(t);
  const later = (t: number) => new Date(Math.max(t, now.getTime()));
  // Gece 00:00–03:00 arası "bu akşam" hâlâ önceki akşamdır.
  const hour = new Date(now.getTime() + ISTANBUL_OFFSET_MS).getUTCHours();
  const evening = hour < NIGHT_END_HOUR ? day - DAY_MS : day;

  switch (window) {
    case "tonight":
      return {
        from: later(evening + TONIGHT_START_HOUR * HOUR_MS),
        to: at(evening + DAY_MS + NIGHT_END_HOUR * HOUR_MS),
      };
    case "today":
      return { from: now, to: at(day + DAY_MS) };
    case "tomorrow":
      return { from: at(day + DAY_MS), to: at(day + 2 * DAY_MS) };
    case "this_weekend": {
      // Cuma 17:00 – Pazartesi 00:00. Pazartesi–Perşembe ise gelecek hafta sonu.
      const wd = istanbulWeekday(now);
      const daysToMonday = wd === 0 ? 1 : 8 - wd;
      const monday = day + daysToMonday * DAY_MS;
      const fridayEvening = monday - 3 * DAY_MS + TONIGHT_START_HOUR * HOUR_MS;
      return { from: later(fridayEvening), to: at(monday) };
    }
    case "this_week": {
      const wd = istanbulWeekday(now);
      const daysToMonday = wd === 0 ? 1 : 8 - wd;
      return { from: now, to: at(day + daysToMonday * DAY_MS) };
    }
    case "upcoming":
      return { from: now, to: null };
  }
}

// ---------------------------------------------------------------------------
// Kural tabanlı ayrıştırıcı (yedek)
// ---------------------------------------------------------------------------

/** Türkçe küçük harf + aksan sadeleştirme (İ/I sorununu da çözer). */
export function normalize(text: string): string {
  return text
    .replaceAll("İ", "i")
    .replaceAll("I", "ı")
    .toLowerCase()
    .replaceAll("ı", "i")
    .replaceAll("ş", "s")
    .replaceAll("ğ", "g")
    .replaceAll("ü", "u")
    .replaceAll("ö", "o")
    .replaceAll("ç", "c")
    .replace(/\s+/g, " ")
    .trim();
}

const CATEGORY_WORDS: Array<[Category, RegExp]> = [
  ["concert", /\b(konser|muzik|caz|jazz|rock|canli muzik|resital|senfoni|orkestra)/],
  ["theatre", /\b(tiyatro|oyun(u|lar)?\b|sahne oyun|opera|bale|muzikal)/],
  ["exhibition", /\b(sergi|muze|resim|fotograf|galeri)/],
  ["festival", /\bfestival/],
  ["standup", /\b(stand[ -]?up|komedi|gosteri)/],
  ["workshop", /\b(atolye|workshop|kurs)/],
  ["cinema", /\b(sinema|film|gosterim)/],
  ["talk", /\b(soylesi|konferans|panel|seminer|konusma|imza gunu)/],
  ["sports", /\b(spor|mac|kosu|yoga|bisiklet)/],
  ["family", /\b(cocuk|aile|cocuklar)/],
  ["party", /\b(parti|dj|gece kulubu)/],
];

export function ruleBasedFilter(query: string): SearchFilter {
  const q = normalize(query);
  const categories = CATEGORY_WORDS.filter(([, re]) => re.test(q)).map(([c]) => c);

  // "yarın akşam" yarındır; gün adı içeren ifadeler "akşam"dan önce bakılır.
  let window: TimeWindow = "upcoming";
  if (/\b(yarin|tomorrow)\b/.test(q)) window = "tomorrow";
  else if (/\b(hafta ?sonu|cuma aksami|cumartesi|pazar|weekend)\b/.test(q)) window = "this_weekend";
  else if (/\b(bu ?aksam|bu ?gece|aksam|gece|tonight)\b/.test(q)) window = "tonight";
  else if (/\b(bugun|today)\b/.test(q)) window = "today";
  else if (/\bbu hafta\b/.test(q)) window = "this_week";

  const free = /\b(ucretsiz|bedava|free|parasiz)\b/.test(q);
  const priceMatch = q.match(/(\d+)\s*(?:(?:tl|lira)\b|₺)/);
  const radiusMatch = q.match(/(\d+(?:[.,]\d+)?)\s*(km|kilometre)\b/);
  const walking = /\byurume mesafesi/.test(q);
  const near = walking || radiusMatch !== null ||
    /\b(yakin|yakinimda|yakinimdaki|yakinlarda|civar|etrafimda|cevremde|near)/.test(q);

  return sanitizeFilter({
    categories,
    free_only: free,
    max_price: priceMatch ? Number(priceMatch[1]) : null,
    time_window: window,
    near_me: near,
    radius_m: radiusMatch
      ? Number(radiusMatch[1].replace(",", ".")) * 1000
      : walking
      ? 1500
      : null,
  });
}

// ---------------------------------------------------------------------------
// Kullanıcıya gösterilen özet
// ---------------------------------------------------------------------------

const WINDOW_LABELS: Record<TimeWindow, string> = {
  tonight: "Bu akşam",
  today: "Bugün",
  tomorrow: "Yarın",
  this_weekend: "Hafta sonu",
  this_week: "Bu hafta",
  upcoming: "Yaklaşan",
};

const CATEGORY_LABELS: Record<Category, string> = {
  concert: "Konser",
  theatre: "Tiyatro",
  exhibition: "Sergi",
  festival: "Festival",
  standup: "Stand-up",
  workshop: "Atölye",
  cinema: "Sinema",
  talk: "Söyleşi",
  sports: "Spor",
  family: "Çocuk & Aile",
  party: "Parti",
  other: "Diğer",
};

/** Filtrenin etiketleri: ["Bu akşam", "Konser", "Ücretsiz", "5 km içinde"]. */
export function filterLabels(f: SearchFilter, radiusM: number | null): string[] {
  const labels = [WINDOW_LABELS[f.time_window]];
  for (const c of f.categories) labels.push(CATEGORY_LABELS[c]);
  if (f.free_only) labels.push("Ücretsiz");
  else if (f.max_price !== null) labels.push(`${f.max_price} ₺ altı`);
  if (f.near_me && radiusM !== null) {
    const km = radiusM / 1000;
    labels.push(`${Number.isInteger(km) ? km : km.toFixed(1).replace(".", ",")} km içinde`);
  }
  return labels;
}
