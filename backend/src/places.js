const { config } = require("./config");
const { haversineDistanceM } = require("./utils");

const CACHE_TTL_MS = 30_000;
const MAX_REQ_PER_SEC = 2;

const cache = new Map();
const hitsByIp = new Map();

function cacheKey(query, limit, lat, lon) {
  const latKey = lat == null ? "none" : Number(lat).toFixed(2);
  const lonKey = lon == null ? "none" : Number(lon).toFixed(2);
  return `${query.trim().toLowerCase()}|${limit}|${latKey}|${lonKey}`;
}

function enforceRateLimit(clientIp) {
  const now = Date.now();
  const hits = hitsByIp.get(clientIp) || [];
  const freshHits = hits.filter((hit) => now - hit <= 1000);
  if (freshHits.length >= MAX_REQ_PER_SEC) {
    const error = new Error("rate_limited");
    error.code = "rate_limited";
    throw error;
  }
  freshHits.push(now);
  hitsByIp.set(clientIp, freshHits);
}

function sweepCache() {
  const now = Date.now();
  for (const [key, value] of cache.entries()) {
    if (value.expiresAt <= now) {
      cache.delete(key);
    }
  }
}

async function autocompletePlaces({ query, limit = 8, lat = null, lon = null, clientIp }) {
  const cleaned = String(query || "").trim();
  if (cleaned.length < 3) {
    return [];
  }

  enforceRateLimit(clientIp || "unknown");
  const boundedLimit = Math.max(1, Math.min(Number(limit) || 8, 8));
  const key = cacheKey(cleaned, boundedLimit, lat, lon);

  const existing = cache.get(key);
  if (existing && existing.expiresAt > Date.now()) {
    return existing.rows;
  }

  const url = new URL(`${config.nominatimBaseUrl.replace(/\/$/, "")}/search`);
  url.searchParams.set("q", cleaned);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("limit", String(boundedLimit));
  url.searchParams.set("countrycodes", "my");
  if (lat != null && lon != null) {
    const delta = 0.35;
    const clampedLat = Number(lat);
    const clampedLon = Number(lon);
    url.searchParams.set(
      "viewbox",
      `${clampedLon - delta},${clampedLat + delta},${clampedLon + delta},${clampedLat - delta}`
    );
  }

  const response = await fetch(url, {
    headers: { "User-Agent": "VoygoLocalDev/1.0" }
  });
  if (!response.ok) {
    throw new Error(`autocomplete_failed_${response.status}`);
  }

  const payload = await response.json();
  const rows = [];
  if (Array.isArray(payload)) {
    for (const row of payload) {
      try {
        rows.push({
          display_name: row.display_name || "",
          name: row.name || null,
          lat: Number(row.lat),
          lon: Number(row.lon),
          osm_type: row.osm_type || null,
          osm_id: row.osm_id != null ? String(row.osm_id) : null,
          class: row.class || null,
          type: row.type || null,
          address: row.address && typeof row.address === "object" ? row.address : null
        });
      } catch (_error) {
        // Skip malformed records from upstream.
      }
    }
  }

  if (lat != null && lon != null) {
    const fromLat = Number(lat);
    const fromLon = Number(lon);
    rows.sort(
      (a, b) =>
        haversineDistanceM(fromLat, fromLon, a.lat, a.lon) -
        haversineDistanceM(fromLat, fromLon, b.lat, b.lon)
    );
  }

  cache.set(key, { rows, expiresAt: Date.now() + CACHE_TTL_MS });
  sweepCache();
  return rows;
}

module.exports = { autocompletePlaces };
