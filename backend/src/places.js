const { config } = require("./config");
const { haversineDistanceM } = require("./utils");

const CACHE_TTL_MS = 30_000;
const MAX_REQ_PER_SEC = 5;

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
  if (cleaned.length < 2) {
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
  if (lat != null && lon != null && isMalaysiaCoordinate(Number(lat), Number(lon))) {
    const delta = 0.35;
    const clampedLat = Number(lat);
    const clampedLon = Number(lon);
    url.searchParams.set(
      "viewbox",
      `${clampedLon - delta},${clampedLat + delta},${clampedLon + delta},${clampedLat - delta}`
    );
  }

  const rows = knownPlaceRows(cleaned);
  let payload = [];
  try {
    const response = await fetch(url, {
      headers: { "User-Agent": "VoygoLocalDev/1.0" }
    });
    if (!response.ok) {
      throw new Error(`autocomplete_failed_${response.status}`);
    }
    payload = await response.json();
  } catch (error) {
    if (rows.length > 0) {
      cache.set(key, { rows, expiresAt: Date.now() + CACHE_TTL_MS });
      sweepCache();
      return rows.slice(0, boundedLimit);
    }
    throw error;
  }

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

function isMalaysiaCoordinate(lat, lon) {
  return lat >= 0.8 && lat <= 7.5 && lon >= 99.0 && lon <= 120.5;
}

function knownPlaceRows(query) {
  const normalized = normalize(query);
  if (!normalized) {
    return [];
  }

  return KNOWN_PLACES.filter((place) =>
    place.terms.some((term) => {
      const normalizedTerm = normalize(term);
      return normalizedTerm.includes(normalized) || normalized.includes(normalizedTerm);
    })
  ).map((place) => ({
    display_name: place.displayName,
    name: place.name,
    lat: place.lat,
    lon: place.lon,
    osm_type: "known",
    osm_id: place.id,
    class: "office",
    type: "workplace",
    address: place.address
  }));
}

function normalize(value) {
  return String(value || "")
    .toLowerCase()
    .split(/[^a-z0-9]+/g)
    .filter(Boolean)
    .join(" ");
}

const KNOWN_PLACES = [
  {
    id: "known-motorola-solutions-bayan-lepas",
    name: "Motorola Solutions",
    displayName: "Motorola Solutions, Bayan Lepas, Penang, Malaysia",
    lat: 5.28577,
    lon: 100.2688,
    terms: [
      "motorola solutions",
      "motorla solutions",
      "motorola",
      "innoplex",
      "technoplex",
      "medan bayan lepas",
      "bayan lepas"
    ],
    address: {
      road: "Medan Bayan Lepas",
      suburb: "Bayan Lepas",
      city: "Bayan Lepas",
      state: "Penang",
      postcode: "11900",
      country: "Malaysia",
      country_code: "my"
    }
  },
  {
    id: "known-klcc",
    name: "KLCC",
    displayName: "KLCC, Kuala Lumpur, Malaysia",
    lat: 3.1579,
    lon: 101.7116,
    terms: ["klcc", "petronas twin towers", "kuala lumpur city centre"],
    address: {
      suburb: "Kuala Lumpur City Centre",
      city: "Kuala Lumpur",
      state: "Kuala Lumpur",
      country: "Malaysia",
      country_code: "my"
    }
  },
  {
    id: "known-kl-sentral",
    name: "KL Sentral",
    displayName: "KL Sentral, Kuala Lumpur, Malaysia",
    lat: 3.134,
    lon: 101.6869,
    terms: ["kl sentral", "kuala lumpur sentral"],
    address: {
      suburb: "Brickfields",
      city: "Kuala Lumpur",
      state: "Kuala Lumpur",
      country: "Malaysia",
      country_code: "my"
    }
  },
  {
    id: "known-mid-valley",
    name: "Mid Valley City",
    displayName: "Mid Valley City, Kuala Lumpur, Malaysia",
    lat: 3.1183,
    lon: 101.6787,
    terms: ["mid valley", "mid valley city", "mid valley offices"],
    address: {
      suburb: "Mid Valley City",
      city: "Kuala Lumpur",
      state: "Kuala Lumpur",
      country: "Malaysia",
      country_code: "my"
    }
  },
  {
    id: "known-jb-sentral",
    name: "JB Sentral",
    displayName: "JB Sentral, Johor Bahru, Malaysia",
    lat: 1.4621,
    lon: 103.7646,
    terms: ["jb sentral", "johor bahru sentral", "johor bahru", "jb"],
    address: {
      city: "Johor Bahru",
      state: "Johor",
      country: "Malaysia",
      country_code: "my"
    }
  },
  {
    id: "known-kuching-waterfront",
    name: "Kuching Waterfront",
    displayName: "Kuching Waterfront, Sarawak, Malaysia",
    lat: 1.5589,
    lon: 110.344,
    terms: ["kuching waterfront", "kuching", "sarawak"],
    address: {
      city: "Kuching",
      state: "Sarawak",
      country: "Malaysia",
      country_code: "my"
    }
  }
];

module.exports = { autocompletePlaces };
