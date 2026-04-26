const cors = require("cors");
const express = require("express");
const { config } = require("./config");
const { pool } = require("./db");
const { generateRideInstances } = require("./generation");
const { autocompletePlaces } = require("./places");
const {
  appendChatMessage,
  createRoute,
  createSubscription,
  findCommuteMatches,
  findLegacyMatchCandidates,
  listChatMessages,
  listChatThreads,
  listRiderCalendar,
  listRouteRides,
  listSubscriptions,
  loadRouteContexts,
  normalizeActiveStatus,
  normalizeDaysOfWeek
} = require("./repository");
const { initSchema } = require("./schema");
const { seedIfEmpty } = require("./seed");
const { estimateRoute, geocodeQuery, generateSupportReply } = require("./services");

const app = express();

app.use(cors());
app.use(express.json({ limit: "1mb" }));
app.use((req, res, next) => {
  const startedAt = Date.now();
  res.on("finish", () => {
    const durationMs = Date.now() - startedAt;
    const ip = req.ip || req.socket.remoteAddress || "unknown";
    console.log(
      `${new Date().toISOString()} ${req.method} ${req.originalUrl} ${res.statusCode} ${durationMs}ms ip=${ip}`
    );
  });
  next();
});

function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function toInt(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value), 10);
  if (Number.isNaN(parsed)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, parsed));
}

app.get(
  "/health",
  asyncHandler(async (_req, res) => {
    await pool.query("SELECT 1");
    res.json({ status: "ok" });
  })
);

app.post(
  "/ai/support",
  asyncHandler(async (req, res) => {
    const message = String(req.body?.message || "").trim();
    if (!message) {
      res.status(400).json({ detail: "message is required" });
      return;
    }
    const reply = await generateSupportReply(message);
    res.json({ reply });
  })
);

app.get(
  "/places/autocomplete",
  asyncHandler(async (req, res) => {
    const query = String(req.query.q || "");
    const limit = toInt(req.query.limit, 8, 1, 8);
    const lat = req.query.lat != null ? Number(req.query.lat) : null;
    const lon = req.query.lon != null ? Number(req.query.lon) : null;
    const clientIp = req.ip || req.socket.remoteAddress || "unknown";
    try {
      const rows = await autocompletePlaces({
        query,
        limit,
        lat,
        lon,
        clientIp
      });
      res.json(rows);
    } catch (error) {
      if (error.code === "rate_limited") {
        res.status(429).json({ detail: "Too many requests" });
        return;
      }
      console.error("autocomplete failed", error);
      res.json([]);
    }
  })
);

app.get(
  "/geo/geocode",
  asyncHandler(async (req, res) => {
    const query = String(req.query.q || "").trim();
    if (!query) {
      res.status(400).json({ detail: "q is required" });
      return;
    }
    const result = await geocodeQuery(query);
    res.json(result);
  })
);

app.post(
  "/route/estimate",
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    if (
      !body.origin ||
      !body.destination ||
      body.origin.lat == null ||
      body.origin.lng == null ||
      body.destination.lat == null ||
      body.destination.lng == null
    ) {
      res.status(400).json({ detail: "origin/destination are required" });
      return;
    }
    const route = await estimateRoute(body);
    res.json(route);
  })
);

app.post(
  "/commute/routes",
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const routeId = await createRoute(pool, {
      driverId: body.driverId,
      driverName: body.driverName,
      startLocation: body.startLocation,
      endLocation: body.endLocation,
      pickupPoints: body.pickupPoints || [],
      dropPoints: body.dropPoints || [],
      departureTime: body.departureTime,
      daysOfWeek: body.daysOfWeek,
      seatCount: body.seatCount,
      pricePerSeat: body.pricePerSeat,
      carType: body.carType,
      activeStatus: "ACTIVE"
    });
    res.json({ id: routeId });
  })
);

app.put(
  "/commute/routes/:routeId/schedule",
  asyncHandler(async (req, res) => {
    const routeId = req.params.routeId;
    const body = req.body || {};
    const result = await pool.query(
      `UPDATE recurring_routes
       SET departure_time = $2, days_of_week = $3::jsonb
       WHERE id = $1`,
      [routeId, body.departureTime, JSON.stringify(normalizeDaysOfWeek(body.daysOfWeek))]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "Route not found" });
      return;
    }
    res.status(204).send();
  })
);

app.put(
  "/commute/routes/:routeId/status",
  asyncHandler(async (req, res) => {
    const routeId = req.params.routeId;
    const body = req.body || {};
    const result = await pool.query(
      `UPDATE recurring_routes
       SET active_status = $2
       WHERE id = $1`,
      [routeId, normalizeActiveStatus(body.activeStatus)]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "Route not found" });
      return;
    }
    res.status(204).send();
  })
);

app.get(
  "/commute/routes/driver/:driverId",
  asyncHandler(async (req, res) => {
    const contexts = await loadRouteContexts(pool, "driver_id = $1", [
      req.params.driverId
    ]);
    res.json(contexts.map((ctx) => ctx.dto));
  })
);

app.get(
  "/commute/routes/:routeId/subscriptions",
  asyncHandler(async (req, res) => {
    const items = await listSubscriptions(pool, "s.route_id = $1", [
      req.params.routeId
    ]);
    res.json(items);
  })
);

app.get(
  "/commute/routes/:routeId/rides",
  asyncHandler(async (req, res) => {
    const fromDate = String(req.query.fromDate || todayIso());
    const days = toInt(req.query.days, 7, 1, 60);
    const rides = await listRouteRides(pool, req.params.routeId, fromDate, days);
    res.json(rides);
  })
);

app.get(
  "/commute/routes/:routeId",
  asyncHandler(async (req, res) => {
    const contexts = await loadRouteContexts(pool, "id = $1", [req.params.routeId]);
    if (contexts.length === 0) {
      res.status(404).json({ detail: "Route not found" });
      return;
    }
    res.json(contexts[0].dto);
  })
);

app.get(
  "/commute/subscriptions/rider/:riderId",
  asyncHandler(async (req, res) => {
    const items = await listSubscriptions(pool, "s.rider_id = $1", [req.params.riderId]);
    res.json(items);
  })
);

app.post(
  "/commute/subscriptions",
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const id = await createSubscription(pool, {
      routeId: body.routeId,
      riderId: body.riderId,
      riderName: body.riderName,
      startDate: body.startDate,
      endDate: body.endDate,
      pickupPointId: body.pickupPointId,
      dropPointId: body.dropPointId,
      status: "ACTIVE"
    });
    res.json({ id });
  })
);

app.put(
  "/commute/subscriptions/:subscriptionId/status",
  asyncHandler(async (req, res) => {
    const subscriptionId = req.params.subscriptionId;
    const status = String(req.body?.status || "ACTIVE").toUpperCase();
    const result = await pool.query(
      `UPDATE route_subscriptions
       SET status = $2
       WHERE id = $1`,
      [subscriptionId, status]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "Subscription not found" });
      return;
    }
    res.status(204).send();
  })
);

app.post(
  "/commute/search",
  asyncHandler(async (req, res) => {
    const matches = await findCommuteMatches(pool, req.body || {});
    res.json({ matches, candidates: matches });
  })
);

app.get(
  "/commute/riders/:riderId/calendar",
  asyncHandler(async (req, res) => {
    const fromDate = String(req.query.fromDate || todayIso());
    const days = toInt(req.query.days, 7, 1, 60);
    const rides = await listRiderCalendar(pool, req.params.riderId, fromDate, days);
    res.json(rides);
  })
);

app.post(
  "/commute/rides/generate",
  asyncHandler(async (req, res) => {
    const date = String(req.body?.date || todayIso());
    await generateRideInstances(pool, date, 1);
    res.status(204).send();
  })
);

app.post(
  "/routes",
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const routeId = await createRoute(
      pool,
      {
        driverId: body.driver_id,
        driverName: body.driver_name || body.driver_id,
        startLocation: body.start_location,
        endLocation: body.end_location,
        pickupPoints: body.pickup_points || [],
        dropPoints: body.drop_points || [],
        departureTime: body.departure_time,
        daysOfWeek: body.days_of_week,
        seatCount: body.seat_count,
        pricePerSeat: body.price_per_seat,
        carType: body.car_type,
        activeStatus: body.active_status ? "ACTIVE" : "PAUSED"
      },
      { rawActiveStatus: Boolean(body.active_status) }
    );
    res.json({ route_id: routeId });
  })
);

app.post(
  "/subscriptions",
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const id = await createSubscription(pool, {
      routeId: body.route_id,
      riderId: body.rider_id,
      riderName: body.rider_name || body.rider_id,
      startDate: body.start_date,
      endDate: body.end_date,
      pickupPointId: body.selected_pickup_point_id,
      dropPointId: body.selected_drop_point_id,
      status: body.status || "ACTIVE"
    });
    res.json({ subscription_id: id });
  })
);

app.post(
  "/admin/generate",
  asyncHandler(async (req, res) => {
    const days = toInt(req.query.days, 7, 1, 60);
    const generatedInstances = await generateRideInstances(pool, todayIso(), days);
    res.json({ generated_instances: generatedInstances, days });
  })
);

app.post(
  "/match/search",
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    if (
      body.home_lat != null &&
      body.home_lng != null &&
      body.office_lat != null &&
      body.office_lng != null
    ) {
      const candidates = await findLegacyMatchCandidates(pool, body);
      res.json({ matches: [], candidates });
      return;
    }
    res.json({ matches: [] });
  })
);

app.post("/trips/:id/book", (_req, res) => res.status(204).send());
app.get("/bookings/me", (_req, res) => res.json([]));
app.get(
  "/chats/threads",
  asyncHandler(async (_req, res) => {
    const threads = await listChatThreads(pool);
    res.json(threads);
  })
);
app.get(
  "/chats/:threadId",
  asyncHandler(async (req, res) => {
    const messages = await listChatMessages(pool, req.params.threadId);
    res.json(messages);
  })
);
app.post(
  "/chats/:threadId/send",
  asyncHandler(async (req, res) => {
    const text = String(req.body?.text || "");
    await appendChatMessage(pool, req.params.threadId, text, "ME");
    res.status(204).send();
  })
);

app.use((error, _req, res, _next) => {
  console.error(error);
  const status = Number(error.status || 500);
  const detail =
    status >= 500 ? "Internal server error" : error.message || "Request failed";
  res.status(status).json({ detail });
});

async function start() {
  await initSchema(pool);
  await seedIfEmpty(pool);

  app.listen(config.port, "0.0.0.0", () => {
    console.log(`Voygo Node API listening on 0.0.0.0:${config.port}`);
  });
}

start().catch((error) => {
  console.error("Server failed to start", error);
  process.exit(1);
});

process.on("SIGTERM", async () => {
  await pool.end();
  process.exit(0);
});
