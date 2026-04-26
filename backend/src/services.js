const OpenAI = require("openai");
const { config } = require("./config");
const { haversineDistanceM } = require("./utils");

async function geocodeQuery(query) {
  const url = new URL(`${config.nominatimBaseUrl.replace(/\/$/, "")}/search`);
  url.searchParams.set("q", query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "1");

  const response = await fetch(url, {
    headers: { "User-Agent": "VoygoLocalDev/1.0" }
  });
  if (!response.ok) {
    throw new Error(`Geocode failed: ${response.status}`);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return { query, lat: null, lng: null, display_name: null };
  }

  const item = rows[0];
  return {
    query,
    lat: Number(item.lat),
    lng: Number(item.lon),
    display_name: item.display_name || null
  };
}

async function estimateRoute(payload) {
  const { origin, destination } = payload;
  const url =
    `${config.osrmBaseUrl.replace(/\/$/, "")}` +
    `/route/v1/driving/${origin.lng},${origin.lat};${destination.lng},${destination.lat}?overview=false`;

  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`OSRM failed: ${response.status}`);
    }
    const data = await response.json();
    const route = Array.isArray(data.routes) && data.routes[0] ? data.routes[0] : null;
    if (!route) {
      throw new Error("OSRM route not found");
    }
    return {
      distance_m: Number(route.distance || 0),
      duration_s: Number(route.duration || 0),
      source: "osrm"
    };
  } catch (_error) {
    const distanceM = haversineDistanceM(
      Number(origin.lat),
      Number(origin.lng),
      Number(destination.lat),
      Number(destination.lng)
    );
    return {
      distance_m: distanceM,
      duration_s: distanceM / (35000 / 3600),
      source: "haversine"
    };
  }
}

async function generateSupportReply(message) {
  if (!config.openAiApiKey) {
    return "OPENAI_API_KEY is not configured in local dev.";
  }
  const client = new OpenAI({ apiKey: config.openAiApiKey });
  const response = await client.responses.create({
    model: "gpt-4o-mini",
    input: [
      {
        role: "system",
        content:
          "You are Voygo support for recurring commute rides. Be concise and practical."
      },
      {
        role: "user",
        content: message
      }
    ]
  });
  return (response.output_text || "").trim() || "I could not generate a reply right now.";
}

module.exports = { estimateRoute, geocodeQuery, generateSupportReply };
