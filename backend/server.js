const http = require("http");
const crypto = require("crypto");
const { URL } = require("url");

const PORT = Number(process.env.PORT || 8000);

const p1 = point("p1", "Downtown Station", "cluster-downtown", 3.1478, 101.7101);
const p2 = point("p2", "Civic Centre", "cluster-downtown", 3.1525, 101.7065);
const p3 = point("p3", "Masjid Jamek Hub", "cluster-central", 3.1490, 101.6967);
const d1 = point("d1", "KLCC Office Park", "cluster-klcc", 3.1571, 101.7123);
const d2 = point("d2", "Mid Valley Offices", "cluster-midvalley", 3.1183, 101.6787);
const p4 = point("p4", "Putrajaya Sentral", "cluster-putra", 2.9291, 101.6967);
const d3 = point("d3", "Cerdas Tech Hub", "cluster-cerdas", 3.0880, 101.6890);

const weekdays = {
  monday: true,
  tuesday: true,
  wednesday: true,
  thursday: true,
  friday: true,
  saturday: false,
  sunday: false
};

const routes = [
  {
    id: "rr-1",
    driverId: "driver-1",
    driverName: "Nina Cruz",
    startLocation: "Damansara",
    endLocation: "KLCC",
    pickupPoints: [p1, p2, p3],
    dropPoints: [d1, d2],
    departureTime: "08:15",
    daysOfWeek: weekdays,
    seatCount: 3,
    pricePerSeat: 8,
    carType: "SEDAN",
    activeStatus: "ACTIVE",
    reliability: reliability(0.95, 0.03, 21, 4.8)
  },
  {
    id: "rr-2",
    driverId: "driver-2",
    driverName: "Evan Brooks",
    startLocation: "Putrajaya",
    endLocation: "Mid Valley",
    pickupPoints: [p4],
    dropPoints: [d2, d3],
    departureTime: "08:00",
    daysOfWeek: weekdays,
    seatCount: 4,
    pricePerSeat: 7,
    carType: "EV",
    activeStatus: "ACTIVE",
    reliability: reliability(0.91, 0.05, 14, 4.6)
  }
];

const subscriptions = [
  {
    id: "sub-1",
    routeId: "rr-1",
    riderId: "rider-me",
    riderName: "You",
    startDate: isoDate(-10),
    endDate: isoDate(90),
    selectedPickupPoint: p1,
    selectedDropPoint: d1,
    status: "ACTIVE"
  },
  {
    id: "sub-2",
    routeId: "rr-1",
    riderId: "rider-2",
    riderName: "Aria",
    startDate: isoDate(-2),
    endDate: isoDate(60),
    selectedPickupPoint: p2,
    selectedDropPoint: d2,
    status: "ACTIVE"
  }
];

const threads = [
  {
    id: "c1",
    tripId: "rr-1",
    title: "Commute with Nina",
    lastMessage: "See you at Downtown Station.",
    unreadCount: 0
  },
  {
    id: "c2",
    tripId: "rr-2",
    title: "Putrajaya Route",
    lastMessage: "Running 5 mins late",
    unreadCount: 1
  }
];

const messages = [
  chat("m1", "c1", "OTHER", "Hi, still picking up?", -100000),
  chat("m2", "c1", "ME", "Yes, confirmed.", -90000),
  chat("m3", "c1", "OTHER", "See you at Downtown Station.", -87000),
  chat("m4", "c2", "OTHER", "Running 5 mins late", -50000)
];

const places = [
  ["KLCC Office Park", 3.1571, 101.7123],
  ["KLCC LRT Station", 3.1590, 101.7130],
  ["Damansara Uptown", 3.1346, 101.6225],
  ["Damansara Heights", 3.1470, 101.6678],
  ["Downtown Station", 3.1478, 101.7101],
  ["Masjid Jamek Hub", 3.1490, 101.6967],
  ["Mid Valley Offices", 3.1183, 101.6787],
  ["Putrajaya Sentral", 2.9291, 101.6967],
  ["Cerdas Tech Hub", 3.0880, 101.6890]
];

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const path = url.pathname;

  if (req.method === "OPTIONS") {
    sendNoContent(res);
    return;
  }

  try {
    if (req.method === "GET" && path === "/health") {
      sendJson(res, { status: "ok" });
      return;
    }

    if (req.method === "GET" && path === "/places/autocomplete") {
      const query = String(url.searchParams.get("q") || "").toLowerCase();
      const limit = clamp(Number(url.searchParams.get("limit") || 8), 1, 8);
      const rows = places
        .filter(([name]) => !query || name.toLowerCase().includes(query))
        .slice(0, limit)
        .map(([displayName, lat, lon]) => ({ displayName, lat, lon }));
      sendJson(res, rows);
      return;
    }

    if (req.method === "POST" && path === "/commute/search") {
      const body = await readJson(req);
      const matches = makeMatches(body);
      sendJson(res, { matches, candidates: matches });
      return;
    }

    let match = path.match(/^\/commute\/routes\/driver\/([^/]+)$/);
    if (req.method === "GET" && match) {
      sendJson(res, routes.filter((route) => route.driverId === decodeURIComponent(match[1])));
      return;
    }

    match = path.match(/^\/commute\/routes\/([^/]+)\/subscriptions$/);
    if (req.method === "GET" && match) {
      sendJson(res, subscriptions.filter((sub) => sub.routeId === decodeURIComponent(match[1])));
      return;
    }

    match = path.match(/^\/commute\/routes\/([^/]+)\/rides$/);
    if (req.method === "GET" && match) {
      sendJson(
        res,
        ridesForRoute(
          decodeURIComponent(match[1]),
          url.searchParams.get("fromDate"),
          Number(url.searchParams.get("days") || 30)
        )
      );
      return;
    }

    match = path.match(/^\/commute\/routes\/([^/]+)$/);
    if (req.method === "GET" && match) {
      const route = routes.find((item) => item.id === decodeURIComponent(match[1]));
      route ? sendJson(res, route) : sendJson(res, { detail: "Route not found" }, 404);
      return;
    }

    if (req.method === "POST" && path === "/commute/routes") {
      const body = await readJson(req);
      const routeId = `rr-${crypto.randomUUID()}`;
      const pickupPoints = normalizeInputPoints(value(body, "pickupPoints", "pickup_points"), "p");
      const dropPoints = normalizeInputPoints(value(body, "dropPoints", "drop_points"), "d");
      const route = {
        id: routeId,
        driverId: value(body, "driverId", "driver_id") || "driver-1",
        driverName: value(body, "driverName", "driver_name") || "You",
        startLocation: value(body, "startLocation", "start_location") || "Start",
        endLocation: value(body, "endLocation", "end_location") || "Destination",
        pickupPoints: pickupPoints.length ? pickupPoints : [p1],
        dropPoints: dropPoints.length ? dropPoints : [d1],
        departureTime: value(body, "departureTime", "departure_time") || "08:00",
        daysOfWeek: value(body, "daysOfWeek", "days_of_week") || weekdays,
        seatCount: Number(value(body, "seatCount", "seat_count") || 3),
        pricePerSeat: Number(value(body, "pricePerSeat", "price_per_seat") || 8),
        carType: value(body, "carType", "car_type") || "SEDAN",
        activeStatus: "ACTIVE",
        reliability: reliability(0.9, 0.04, 0, 4.7)
      };
      routes.push(route);
      sendJson(res, { id: routeId, routeId });
      return;
    }

    match = path.match(/^\/commute\/routes\/([^/]+)\/status$/);
    if (req.method === "PUT" && match) {
      const body = await readJson(req);
      const route = routes.find((item) => item.id === decodeURIComponent(match[1]));
      if (!route) {
        sendJson(res, { detail: "Route not found" }, 404);
        return;
      }
      const active = value(body, "activeStatus", "active_status");
      route.activeStatus = active === false || active === "PAUSED" ? "PAUSED" : "ACTIVE";
      sendNoContent(res);
      return;
    }

    match = path.match(/^\/commute\/routes\/([^/]+)\/schedule$/);
    if (req.method === "PUT" && match) {
      const body = await readJson(req);
      const route = routes.find((item) => item.id === decodeURIComponent(match[1]));
      if (!route) {
        sendJson(res, { detail: "Route not found" }, 404);
        return;
      }
      route.departureTime = value(body, "departureTime", "departure_time") || route.departureTime;
      route.daysOfWeek = value(body, "daysOfWeek", "days_of_week") || route.daysOfWeek;
      sendNoContent(res);
      return;
    }

    match = path.match(/^\/commute\/subscriptions\/rider\/([^/]+)$/);
    if (req.method === "GET" && match) {
      sendJson(res, subscriptions.filter((sub) => sub.riderId === decodeURIComponent(match[1])));
      return;
    }

    if (req.method === "POST" && path === "/commute/subscriptions") {
      const body = await readJson(req);
      const routeId = value(body, "routeId", "route_id");
      const route = routes.find((item) => item.id === routeId);
      if (!route) {
        sendJson(res, { detail: "Route not found" }, 404);
        return;
      }
      const pickupId = value(body, "pickupPointId", "selectedPickupPointId", "selected_pickup_point_id");
      const dropId = value(body, "dropPointId", "selectedDropPointId", "selected_drop_point_id");
      const id = `sub-${crypto.randomUUID()}`;
      subscriptions.push({
        id,
        routeId,
        riderId: value(body, "riderId", "rider_id") || "rider-me",
        riderName: value(body, "riderName", "rider_name") || "Rider",
        startDate: value(body, "startDate", "start_date") || isoDate(0),
        endDate: value(body, "endDate", "end_date") || isoDate(30),
        selectedPickupPoint: route.pickupPoints.find((item) => item.id === pickupId) || route.pickupPoints[0],
        selectedDropPoint: route.dropPoints.find((item) => item.id === dropId) || route.dropPoints[0],
        status: "ACTIVE"
      });
      sendJson(res, { id, subscriptionId: id });
      return;
    }

    match = path.match(/^\/commute\/subscriptions\/([^/]+)\/status$/);
    if (req.method === "PUT" && match) {
      const body = await readJson(req);
      const sub = subscriptions.find((item) => item.id === decodeURIComponent(match[1]));
      if (!sub) {
        sendJson(res, { detail: "Subscription not found" }, 404);
        return;
      }
      sub.status = String(value(body, "status") || "ACTIVE").toUpperCase();
      sendNoContent(res);
      return;
    }

    match = path.match(/^\/commute\/riders\/([^/]+)\/calendar$/);
    if (req.method === "GET" && match) {
      sendJson(
        res,
        calendarForRider(
          decodeURIComponent(match[1]),
          url.searchParams.get("fromDate"),
          Number(url.searchParams.get("days") || 30)
        )
      );
      return;
    }

    if (req.method === "POST" && path === "/commute/rides/generate") {
      sendNoContent(res);
      return;
    }

    if (req.method === "GET" && path === "/chats/threads") {
      sendJson(res, threads);
      return;
    }

    match = path.match(/^\/chats\/([^/]+)$/);
    if (req.method === "GET" && match) {
      sendJson(res, messages.filter((message) => message.threadId === decodeURIComponent(match[1])));
      return;
    }

    match = path.match(/^\/chats\/([^/]+)\/send$/);
    if (req.method === "POST" && match) {
      const body = await readJson(req);
      messages.push(chat(`m-${crypto.randomUUID()}`, decodeURIComponent(match[1]), "ME", String(body.text || ""), 0));
      sendNoContent(res);
      return;
    }

    sendJson(res, { detail: "Not found" }, 404);
  } catch (error) {
    console.error(error);
    sendJson(res, { detail: "Internal server error" }, 500);
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Voygo Render backend listening on 0.0.0.0:${PORT}`);
});

function point(id, label, clusterId, lat, lng) {
  return { id, label, clusterId, lat, lng };
}

function reliability(onTimeRate, cancellationRate, repeatRiders, averageRating) {
  return { onTimeRate, cancellationRate, repeatRiders, averageRating };
}

function chat(id, threadId, sender, text, offsetSeconds) {
  return {
    id,
    threadId,
    sender,
    text,
    timestamp: new Date(Date.now() + offsetSeconds * 1000).toISOString()
  };
}

function isoDate(offsetDays) {
  const value = new Date();
  value.setUTCDate(value.getUTCDate() + offsetDays);
  return value.toISOString().slice(0, 10);
}

function sendJson(res, body, status = 200) {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS",
    "Content-Length": data.length
  });
  res.end(data);
}

function sendNoContent(res) {
  res.writeHead(204, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS"
  });
  res.end();
}

function readJson(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      if (!chunks.length) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch {
        resolve({});
      }
    });
  });
}

function value(body, ...names) {
  for (const name of names) {
    if (body && body[name] !== undefined && body[name] !== null) {
      return body[name];
    }
  }
  return undefined;
}

function clamp(value, min, max) {
  if (Number.isNaN(value)) return min;
  return Math.max(min, Math.min(max, value));
}

function parseMinutes(text, fallback) {
  const match = String(text || "").match(/^(\d{1,2}):(\d{2})$/);
  return match ? Number(match[1]) * 60 + Number(match[2]) : fallback;
}

function makeMatches(body) {
  const earliest = parseMinutes(value(body, "earliestDeparture", "earliest_departure"), 7 * 60);
  const latest = parseMinutes(value(body, "latestDeparture", "latest_departure"), 9 * 60 + 30);
  const riderId = value(body, "riderId", "rider_id") || "rider-me";
  const home = value(body, "homeLocation", "home_location") || "";
  const office = value(body, "officeLocation", "office_location") || "";
  const homeLat = value(body, "homeLat", "home_lat");
  const homeLng = value(body, "homeLng", "home_lng");
  const officeLat = value(body, "officeLat", "office_lat");
  const officeLng = value(body, "officeLng", "office_lng");
  const recurringRoutes = new Set(
    subscriptions
      .filter((sub) => sub.riderId === riderId && sub.status === "ACTIVE")
      .map((sub) => sub.routeId)
  );

  return routes
    .filter((route) => route.activeStatus === "ACTIVE")
    .filter((route) => {
      const minutes = parseMinutes(route.departureTime, 8 * 60);
      return minutes >= earliest && minutes <= latest;
    })
    .map((route) => {
      const activeSubs = subscriptions.filter((sub) => sub.routeId === route.id && sub.status === "ACTIVE");
      const pickupDistance =
        nearestDistance(homeLat, homeLng, route.pickupPoints) ??
        textDistance(home, [route.startLocation, ...route.pickupPoints.map((item) => item.label)]);
      const dropDistance =
        nearestDistance(officeLat, officeLng, route.dropPoints) ??
        textDistance(office, [route.endLocation, ...route.dropPoints.map((item) => item.label)]);
      const reliabilityScore = compositeScore(route.reliability);
      const routeOverlapScore = clamp(1 - dropDistance / 6000, 0, 1);
      const estimatedDetourMinutes = Math.max(1, ((pickupDistance + dropDistance) / 1000) * 2.8);
      const recurringRiderPriority = recurringRoutes.has(route.id);
      const availableSeats = Math.max(0, route.seatCount - activeSubs.length);
      const rankingScore = clamp(
        (recurringRiderPriority ? 0.35 : 0) +
          (1 - Math.min(estimatedDetourMinutes / 45, 1)) * 0.25 +
          routeOverlapScore * 0.2 +
          reliabilityScore * 0.2,
        0,
        1
      );
      return {
        route,
        pickupDistanceMeters: round(pickupDistance),
        reliabilityScore: round(reliabilityScore, 4),
        routeOverlapScore: round(routeOverlapScore, 4),
        estimatedDetourMinutes: round(estimatedDetourMinutes),
        recurringRiderPriority,
        availableSeats,
        rankingScore: round(rankingScore, 6)
      };
    })
    .filter((item) => item.availableSeats > 0)
    .sort((a, b) => b.rankingScore - a.rankingScore);
}

function compositeScore(item) {
  return clamp(
    item.onTimeRate * 0.4 +
      (1 - item.cancellationRate) * 0.25 +
      Math.min(item.repeatRiders / 50, 1) * 0.15 +
      (item.averageRating / 5) * 0.2,
    0,
    1
  );
}

function nearestDistance(lat, lng, points) {
  if (lat === undefined || lng === undefined || lat === null || lng === null) return undefined;
  return Math.min(...points.map((point) => haversine(Number(lat), Number(lng), point.lat, point.lng)));
}

function haversine(lat1, lng1, lat2, lng2) {
  const radius = 6371000;
  const dLat = radians(lat2 - lat1);
  const dLng = radians(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLng / 2) ** 2;
  return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function radians(value) {
  return (value * Math.PI) / 180;
}

function textDistance(input, candidates) {
  const score = tokenScore(input, candidates);
  return Math.max(150, 9000 * (1 - score));
}

function tokenScore(input, candidates) {
  const source = tokens(input);
  if (!source.size) return 0.25;
  return Math.max(
    0,
    ...candidates.map((candidate) => {
      const target = tokens(candidate);
      const union = new Set([...source, ...target]);
      const intersection = [...source].filter((token) => target.has(token));
      return union.size ? intersection.length / union.size : 0;
    })
  );
}

function tokens(text) {
  return new Set(String(text || "").toLowerCase().match(/[a-z0-9]+/g) || []);
}

function round(value, places = 2) {
  const scale = 10 ** places;
  return Math.round(value * scale) / scale;
}

function ridesForRoute(routeId, fromDate, days) {
  const route = routes.find((item) => item.id === routeId);
  if (!route) return [];
  const start = fromDate ? new Date(`${fromDate}T00:00:00Z`) : new Date();
  const activeSubs = subscriptions.filter((sub) => sub.routeId === routeId && sub.status === "ACTIVE");
  const output = [];
  for (let offset = 0; offset < days; offset += 1) {
    const day = new Date(start);
    day.setUTCDate(start.getUTCDate() + offset);
    const weekday = day.toLocaleDateString("en-US", { weekday: "long", timeZone: "UTC" }).toLowerCase();
    if (!route.daysOfWeek[weekday]) continue;
    output.push({
      id: `${routeId}-${offset}`,
      routeId,
      date: day.toISOString().slice(0, 10),
      seatAvailability: Math.max(0, route.seatCount - activeSubs.length),
      confirmedPassengers: activeSubs.map((sub) => sub.riderId),
      rideStatus: "SCHEDULED"
    });
  }
  return output;
}

function calendarForRider(riderId, fromDate, days) {
  return subscriptions
    .filter((sub) => sub.riderId === riderId && sub.status === "ACTIVE")
    .flatMap((sub) => {
      const route = routes.find((item) => item.id === sub.routeId);
      if (!route) return [];
      return ridesForRoute(route.id, fromDate, days).map((ride) => ({
        date: ride.date,
        routeId: route.id,
        driverName: route.driverName,
        startLocation: route.startLocation,
        endLocation: route.endLocation,
        pickupPoint: sub.selectedPickupPoint,
        dropPoint: sub.selectedDropPoint,
        rideStatus: ride.rideStatus
      }));
    });
}

function normalizeInputPoints(input, prefix) {
  if (!Array.isArray(input)) return [];
  return input.map((item) =>
    point(
      `${prefix}-${crypto.randomUUID()}`,
      item.label || "Stop",
      item.clusterId || item.cluster_id || "cluster-new",
      Number(item.lat || 3.14),
      Number(item.lng || 101.7)
    )
  );
}
