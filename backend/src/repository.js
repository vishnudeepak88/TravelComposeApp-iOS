const { randomUUID } = require("crypto");
const { clamp, haversineDistanceM, scoreCandidate } = require("./utils");

function normalizeDaysOfWeek(days) {
  return {
    monday: Boolean(days?.monday),
    tuesday: Boolean(days?.tuesday),
    wednesday: Boolean(days?.wednesday),
    thursday: Boolean(days?.thursday),
    friday: Boolean(days?.friday),
    saturday: Boolean(days?.saturday),
    sunday: Boolean(days?.sunday)
  };
}

function mapPoint(row) {
  return {
    id: String(row.id),
    label: row.label,
    clusterId: row.cluster_id || "",
    lat: Number(row.lat),
    lng: Number(row.lng)
  };
}

function mapReliability(row) {
  if (!row) {
    return {
      onTimeRate: 0.9,
      cancellationRate: 0.05,
      repeatRiders: 0,
      averageRating: 4.5
    };
  }
  return {
    onTimeRate: Number(row.on_time_rate),
    cancellationRate: Number(row.cancellation_rate),
    repeatRiders: Number(row.repeat_riders),
    averageRating: Number(row.average_rating)
  };
}

function reliabilityScore(reliability) {
  const value =
    reliability.onTimeRate * (1.0 - reliability.cancellationRate) * 0.7 +
    (reliability.averageRating / 5.0) * 0.3;
  return clamp(value, 0.0, 1.0);
}

function parseMinutes(value) {
  const match = String(value || "").trim().match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
  if (!match) {
    return null;
  }
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
    return null;
  }
  return hours * 60 + minutes;
}

function normalizeActiveStatus(status) {
  if (typeof status === "boolean") {
    return status;
  }
  return String(status || "")
    .toUpperCase()
    .trim() === "ACTIVE";
}

function mapRouteDto(routeRow, points, reliabilityRow, driverPhone = null,
                    driverPlate = null, driverColor = null, driverCarModel = null,
                    isFavorite = false) {
  const pickupPoints = points.filter((p) => p.kind === "pickup").map(mapPoint);
  const dropPoints = points.filter((p) => p.kind === "drop").map(mapPoint);
  const reliability = mapReliability(reliabilityRow);

  return {
    id: String(routeRow.id),
    driverId: routeRow.driver_id,
    driverName: routeRow.driver_name || routeRow.driver_id,
    // E.164 phone from users table — populated at OTP signup. Powers
    // the LiveTrip "Call driver" affordance; the iOS Models keep it
    // optional so a missing phone keeps the button disabled.
    driverPhone: driverPhone || null,
    startLocation: routeRow.start_location,
    endLocation: routeRow.end_location,
    pickupPoints,
    dropPoints,
    departureTime: routeRow.departure_time,
    daysOfWeek: normalizeDaysOfWeek(routeRow.days_of_week),
    seatCount: Number(routeRow.seat_count),
    pricePerSeat: Number(routeRow.price_per_seat),
    carType: routeRow.car_type || "SEDAN",
    // Vehicle identity is driver-owned now — sourced from users table
    // via the JOIN in loadRouteContexts. A route cannot fake a plate
    // it doesn't have; a driver who swaps cars updates the profile
    // once and every route reflects the change.
    plateNumber: driverPlate || null,
    carColor: driverColor || null,
    carModel: driverCarModel || null,
    activeStatus: routeRow.active_status ? "ACTIVE" : "PAUSED",
    reliability,
    isFavorite
  };
}

async function loadRouteContexts(pool, whereClause = "TRUE", params = [], options = {}) {
  // `favoriteForRiderId` decorates each DTO's `isFavorite` flag for
  // the given rider, so search results can surface a filled star
  // without a second round-trip. Optional — when omitted, all DTOs
  // come back with `isFavorite: false`.
  const favoriteForRiderId = options.favoriteForRiderId || null;
  const routeRes = await pool.query(
    `SELECT *
     FROM recurring_routes
     WHERE ${whereClause}
     ORDER BY created_at DESC`,
    params
  );
  if (routeRes.rows.length === 0) {
    return [];
  }

  const routeIds = routeRes.rows.map((row) => row.id);
  const driverIds = [...new Set(routeRes.rows.map((row) => row.driver_id))];

  const pointRes = await pool.query(
    `SELECT *
     FROM route_points
     WHERE route_id = ANY($1::uuid[])`,
    [routeIds]
  );
  const pointsByRoute = new Map();
  for (const row of pointRes.rows) {
    const items = pointsByRoute.get(String(row.route_id)) || [];
    items.push(row);
    pointsByRoute.set(String(row.route_id), items);
  }

  const reliabilityRes = await pool.query(
    `SELECT *
     FROM driver_reliability
     WHERE driver_id = ANY($1::text[])`,
    [driverIds]
  );
  const reliabilityByDriver = new Map(
    reliabilityRes.rows.map((row) => [row.driver_id, row])
  );

  // Pull driver phones AND vehicle identity from the users table.
  // Vehicle lives on the driver (not per-route) so a bad actor can't
  // list one plate at search time and arrive in a different car —
  // every route DTO reflects whatever's currently on the profile.
  // `users.id` is UUID and `recurring_routes.driver_id` is TEXT —
  // same mismatch that 500'd /longhaul/trips. Cast id::text on both
  // sides so Postgres doesn't error out.
  const userRes = await pool.query(
    `SELECT id::text AS id, phone, plate_number, car_color, car_model
       FROM users
      WHERE id::text = ANY($1::text[])`,
    [driverIds]
  );
  const phoneByDriver = new Map();
  const plateByDriver = new Map();
  const colorByDriver = new Map();
  const carModelByDriver = new Map();
  for (const row of userRes.rows) {
    const key = String(row.id);
    phoneByDriver.set(key, row.phone || null);
    plateByDriver.set(key, row.plate_number || null);
    colorByDriver.set(key, row.car_color || null);
    carModelByDriver.set(key, row.car_model || null);
  }

  const activeCountRes = await pool.query(
    `SELECT route_id, COUNT(*)::int AS active_count
     FROM route_subscriptions
     WHERE route_id = ANY($1::uuid[])
       AND status = 'ACTIVE'
     GROUP BY route_id`,
    [routeIds]
  );
  const activeCountByRoute = new Map(
    activeCountRes.rows.map((row) => [String(row.route_id), Number(row.active_count)])
  );

  // Favorites lookup — single roundtrip keyed by route_id for the
  // requesting rider. Default: nothing favourited.
  let favoriteRouteIds = new Set();
  if (favoriteForRiderId) {
    const favRes = await pool.query(
      `SELECT route_id::text AS route_id
         FROM route_favorites
        WHERE rider_id = $1
          AND route_id = ANY($2::uuid[])`,
      [favoriteForRiderId, routeIds]
    );
    favoriteRouteIds = new Set(favRes.rows.map((r) => r.route_id));
  }

  return routeRes.rows.map((route) => {
    const driverKey = String(route.driver_id);
    const points = pointsByRoute.get(String(route.id)) || [];
    const reliabilityRow = reliabilityByDriver.get(route.driver_id) || null;
    const driverPhone = phoneByDriver.get(driverKey) || null;
    const driverPlate = plateByDriver.get(driverKey) || null;
    const driverColor = colorByDriver.get(driverKey) || null;
    const driverCarModel = carModelByDriver.get(driverKey) || null;
    const isFavorite = favoriteRouteIds.has(String(route.id));
    const dto = mapRouteDto(
      route,
      points,
      reliabilityRow,
      driverPhone,
      driverPlate,
      driverColor,
      driverCarModel,
      isFavorite
    );
    const activeCount = activeCountByRoute.get(String(route.id)) || 0;
    return {
      route,
      points,
      reliabilityRow,
      dto,
      availableSeats: Math.max(0, Number(route.seat_count) - activeCount)
    };
  });
}

async function createRoute(pool, payload, options = {}) {
  const routeId = randomUUID();
  const activeStatus =
    options.rawActiveStatus != null
      ? Boolean(options.rawActiveStatus)
      : normalizeActiveStatus(payload.activeStatus || "ACTIVE");
  const driverName = payload.driverName || payload.driverId;

  // Vehicle identity (plate, colour, model) is intentionally NOT written
  // here — it lives on the driver's user record. Any plateNumber /
  // carColor fields in payload are dropped on the floor to prevent
  // route-level spoofing. If those legacy columns still exist they
  // stay NULL for new rows.
  await pool.query(
    `INSERT INTO recurring_routes (
      id, driver_id, driver_name, start_location, end_location, departure_time,
      days_of_week, seat_count, price_per_seat, car_type, active_status
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11)`,
    [
      routeId,
      payload.driverId,
      driverName,
      payload.startLocation,
      payload.endLocation,
      payload.departureTime,
      JSON.stringify(normalizeDaysOfWeek(payload.daysOfWeek)),
      Number(payload.seatCount),
      Number(payload.pricePerSeat),
      payload.carType || "SEDAN",
      activeStatus
    ]
  );

  const points = [
    ...(payload.pickupPoints || []).map((point) => ({
      ...point,
      kind: "pickup"
    })),
    ...(payload.dropPoints || []).map((point) => ({
      ...point,
      kind: "drop"
    }))
  ];

  for (const point of points) {
    const pointId = randomUUID();
    await pool.query(
      `INSERT INTO route_points (
        id, route_id, kind, label, cluster_id, lat, lng, geom
      )
      VALUES (
        $1, $2, $3, $4, $5, $6, $7, ST_SetSRID(ST_MakePoint($7, $6), 4326)
      )`,
      [
        pointId,
        routeId,
        point.kind,
        point.label,
        point.clusterId || point.cluster_id || null,
        Number(point.lat),
        Number(point.lng)
      ]
    );
  }

  return routeId;
}

async function createSubscription(pool, payload) {
  const client = await pool.connect();
  const routeId = payload.routeId;
  const pickupPointId = payload.pickupPointId;
  const dropPointId = payload.dropPointId;

  try {
    await client.query("BEGIN");

    const routeRes = await client.query(
      `SELECT id, driver_id, driver_name, start_location, end_location, seat_count, active_status
       FROM recurring_routes
       WHERE id = $1
       FOR UPDATE`,
      [routeId]
    );
    const route = routeRes.rows[0];
    if (!route) {
      const error = new Error("Route not found");
      error.status = 404;
      throw error;
    }
    if (!route.active_status) {
      const error = new Error("Route is not accepting new subscriptions");
      error.status = 409;
      throw error;
    }
    if (String(route.driver_id) === String(payload.riderId)) {
      const error = new Error("Drivers cannot subscribe to their own route");
      error.status = 409;
      throw error;
    }

    const duplicateRes = await client.query(
      `SELECT id
       FROM route_subscriptions
       WHERE route_id = $1
         AND rider_id = $2
         AND status = 'ACTIVE'
       LIMIT 1`,
      [routeId, payload.riderId]
    );
    if (duplicateRes.rows.length > 0) {
      const error = new Error("You already have an active subscription for this route");
      error.status = 409;
      throw error;
    }

    const activeCountRes = await client.query(
      `SELECT COUNT(*)::int AS active_count
       FROM route_subscriptions
       WHERE route_id = $1
         AND status = 'ACTIVE'`,
      [routeId]
    );
    const activeCount = Number(activeCountRes.rows[0]?.active_count || 0);
    if (activeCount >= Number(route.seat_count || 0)) {
      const error = new Error("No seats available on this route");
      error.status = 409;
      throw error;
    }

    const pointsRes = await client.query(
      `SELECT id, route_id
       FROM route_points
       WHERE id = ANY($1::uuid[])`,
      [[pickupPointId, dropPointId]]
    );
    if (pointsRes.rows.length !== 2) {
      const error = new Error("Selected pickup/drop points not found");
      error.status = 400;
      throw error;
    }
    for (const row of pointsRes.rows) {
      if (String(row.route_id) !== String(routeId)) {
        const error = new Error("Pickup/drop points must belong to the same route");
        error.status = 400;
        throw error;
      }
    }

    const subscriptionId = randomUUID();
    await client.query(
      `INSERT INTO route_subscriptions (
        id, route_id, rider_id, rider_name, start_date, end_date,
        selected_pickup_point_id, selected_drop_point_id, status
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        subscriptionId,
        routeId,
        payload.riderId,
        payload.riderName || payload.riderId,
        payload.startDate,
        payload.endDate,
        pickupPointId,
        dropPointId,
        payload.status || "ACTIVE"
      ]
    );

    await ensureRouteChatThread(client, route, [payload.riderId, route.driver_id]);
    await client.query("COMMIT");
    return subscriptionId;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function ensureRouteChatThread(client, route, userIds = []) {
  const existing = await client.query(
    "SELECT id FROM chat_threads WHERE route_id = $1 LIMIT 1",
    [route.id]
  );
  let threadId = existing.rows[0]?.id;
  if (!threadId) {
    threadId = randomUUID();
    const title = `${route.driver_name || "Driver"} - ${route.start_location} to ${route.end_location}`;
    await client.query(
      `INSERT INTO chat_threads (id, route_id, title, last_message, unread_count)
       VALUES ($1, $2, $3, '', 0)`,
      [threadId, route.id, title]
    );
  }

  for (const userId of userIds.filter(Boolean)) {
    await client.query(
      `INSERT INTO chat_participants (thread_id, user_id)
       VALUES ($1, $2)
       ON CONFLICT ON CONSTRAINT uq_chat_participant DO NOTHING`,
      [threadId, String(userId)]
    );
  }

  return threadId;
}

async function listSubscriptions(pool, whereClause, params) {
  const res = await pool.query(
    `SELECT
      s.*,
      p.id AS pickup_id, p.label AS pickup_label, p.cluster_id AS pickup_cluster_id, p.lat AS pickup_lat, p.lng AS pickup_lng,
      d.id AS drop_id, d.label AS drop_label, d.cluster_id AS drop_cluster_id, d.lat AS drop_lat, d.lng AS drop_lng
     FROM route_subscriptions s
     JOIN route_points p ON p.id = s.selected_pickup_point_id
     JOIN route_points d ON d.id = s.selected_drop_point_id
     WHERE ${whereClause}
     ORDER BY s.created_at DESC`,
    params
  );

  return res.rows.map((row) => ({
    id: String(row.id),
    routeId: String(row.route_id),
    riderId: row.rider_id,
    riderName: row.rider_name || row.rider_id,
    startDate: row.start_date,
    endDate: row.end_date,
    selectedPickupPoint: {
      id: String(row.pickup_id),
      label: row.pickup_label,
      clusterId: row.pickup_cluster_id || "",
      lat: Number(row.pickup_lat),
      lng: Number(row.pickup_lng)
    },
    selectedDropPoint: {
      id: String(row.drop_id),
      label: row.drop_label,
      clusterId: row.drop_cluster_id || "",
      lat: Number(row.drop_lat),
      lng: Number(row.drop_lng)
    },
    status: row.status
  }));
}

async function listRouteRides(pool, routeId, fromDate, days) {
  const res = await pool.query(
    `SELECT
      i.id,
      i.route_id,
      i.date,
      i.seat_availability,
      i.ride_status,
      COALESCE(
        ARRAY_AGG(p.rider_id) FILTER (WHERE p.rider_id IS NOT NULL),
        ARRAY[]::text[]
      ) AS confirmed_passengers
     FROM commute_ride_instances i
     LEFT JOIN commute_ride_passengers p ON p.instance_id = i.id
     WHERE i.route_id = $1
       AND i.date >= $2
       AND i.date < ($2::date + ($3::int * INTERVAL '1 day'))
     GROUP BY i.id
     ORDER BY i.date ASC`,
    [routeId, fromDate, days]
  );

  return res.rows.map((row) => ({
    id: String(row.id),
    routeId: String(row.route_id),
    date: row.date,
    seatAvailability: Number(row.seat_availability),
    confirmedPassengers: row.confirmed_passengers || [],
    rideStatus: row.ride_status
  }));
}

async function listRiderCalendar(pool, riderId, fromDate, days) {
  const res = await pool.query(
    `SELECT
      i.id,
      i.route_id,
      i.date,
      i.seat_availability,
      i.ride_status,
      COALESCE(
        ARRAY_AGG(allp.rider_id) FILTER (WHERE allp.rider_id IS NOT NULL),
        ARRAY[]::text[]
      ) AS confirmed_passengers
     FROM commute_ride_instances i
     JOIN commute_ride_passengers p ON p.instance_id = i.id AND p.rider_id = $1
     LEFT JOIN commute_ride_passengers allp ON allp.instance_id = i.id
     WHERE i.date >= $2
       AND i.date < ($2::date + ($3::int * INTERVAL '1 day'))
     GROUP BY i.id
     ORDER BY i.date ASC`,
    [riderId, fromDate, days]
  );

  return res.rows.map((row) => ({
    id: String(row.id),
    routeId: String(row.route_id),
    date: row.date,
    seatAvailability: Number(row.seat_availability),
    confirmedPassengers: row.confirmed_passengers || [],
    rideStatus: row.ride_status
  }));
}

async function findCommuteMatches(pool, payload) {
  const contexts = await loadRouteContexts(
    pool,
    "active_status = TRUE",
    [],
    { favoriteForRiderId: payload.riderId }
  );
  if (contexts.length === 0) {
    return [];
  }

  const recurringRoutesRes = await pool.query(
    `SELECT route_id
     FROM route_subscriptions
     WHERE rider_id = $1
       AND status = 'ACTIVE'`,
    [payload.riderId]
  );
  const recurringRouteIds = new Set(
    recurringRoutesRes.rows.map((row) => String(row.route_id))
  );

  const homeLat = payload.homeLat != null ? Number(payload.homeLat) : null;
  const homeLng = payload.homeLng != null ? Number(payload.homeLng) : null;
  const officeLat = payload.officeLat != null ? Number(payload.officeLat) : null;
  const officeLng = payload.officeLng != null ? Number(payload.officeLng) : null;
  const earliestMinutes = parseMinutes(payload.earliestDeparture) ?? 0;
  const latestMinutes = parseMinutes(payload.latestDeparture) ?? 24 * 60 - 1;
  const hasHomeCoords = Number.isFinite(homeLat) && Number.isFinite(homeLng);
  const hasOfficeCoords = Number.isFinite(officeLat) && Number.isFinite(officeLng);

  // Optional rider-supplied filters. Days of week is an object like
  // { monday: true, ... }; max price is a small integer ringgit cap.
  const requestedDays = payload.daysOfWeek
    ? normalizeDaysOfWeek(payload.daysOfWeek)
    : null;
  // Filter activates whenever the rider sent a daysOfWeek payload, even
  // if all flags are false. Previous behaviour silently dropped the
  // filter when the rider toggled every chip off — counterintuitive and
  // surfaced as "I disabled all days but still see Sat routes."
  const hasDayFilter = requestedDays != null;
  const maxPriceMyr = Number.isFinite(Number(payload.maxPriceMyr))
    ? Number(payload.maxPriceMyr)
    : null;

  const matches = [];
  for (const ctx of contexts) {
    const routeMinutes = parseMinutes(ctx.route.departure_time);
    if (routeMinutes == null || routeMinutes < earliestMinutes || routeMinutes > latestMinutes) {
      continue;
    }

    // Day-of-week filter: route's enabled days must overlap with the
    // rider's requested days. Skipped when the rider didn't supply any.
    if (hasDayFilter) {
      const routeDays = normalizeDaysOfWeek(ctx.route.days_of_week);
      const overlap = Object.entries(requestedDays).some(([k, v]) => v && routeDays[k]);
      if (!overlap) continue;
    }

    // Price cap — exclude routes pricier than the rider's budget.
    if (maxPriceMyr != null && Number(ctx.route.price_per_seat) > maxPriceMyr) {
      continue;
    }

    const pickupPoints = ctx.points.filter((item) => item.kind === "pickup");
    const dropPoints = ctx.points.filter((item) => item.kind === "drop");
    if (pickupPoints.length === 0 || dropPoints.length === 0) {
      continue;
    }
    if (ctx.availableSeats <= 0) {
      continue;
    }

    let pickupDistance = 1200;
    if (hasHomeCoords) {
      pickupDistance = Math.min(
        ...pickupPoints.map((point) =>
          haversineDistanceM(homeLat, homeLng, Number(point.lat), Number(point.lng))
        )
      );
    }

    let dropDistance = 1800;
    if (hasOfficeCoords) {
      dropDistance = Math.min(
        ...dropPoints.map((point) =>
          haversineDistanceM(officeLat, officeLng, Number(point.lat), Number(point.lng))
        )
      );
    }

    if (hasHomeCoords && pickupDistance > 40000) {
      continue;
    }
    if (hasOfficeCoords && dropDistance > 40000) {
      continue;
    }

    const reliability = mapReliability(ctx.reliabilityRow);
    const reliabilityValue = reliabilityScore(reliability);
    const pickupScore = hasHomeCoords ? clamp(1.0 - pickupDistance / 12000.0, 0.0, 1.0) : 1.0;
    const dropScore = hasOfficeCoords ? clamp(1.0 - dropDistance / 12000.0, 0.0, 1.0) : 1.0;
    const overlapScore = clamp((pickupScore + dropScore) / 2.0, 0.0, 1.0);
    const recurringPriority = recurringRouteIds.has(String(ctx.route.id));
    const detourMinutes = Math.max(1.0, ((pickupDistance + dropDistance) / 1000.0) * 2.8);

    const rankingScore = clamp(
      (recurringPriority ? 0.35 : 0.0) +
        (1.0 - clamp(pickupDistance / 5000.0, 0.0, 1.0)) * 0.25 +
        overlapScore * 0.2 +
        reliabilityValue * 0.2,
      0.0,
      1.0
    );

    matches.push({
      route: ctx.dto,
      pickupDistanceMeters: Number(pickupDistance.toFixed(2)),
      reliabilityScore: Number(reliabilityValue.toFixed(4)),
      routeOverlapScore: Number(overlapScore.toFixed(4)),
      estimatedDetourMinutes: Number(detourMinutes.toFixed(2)),
      recurringRiderPriority: recurringPriority,
      availableSeats: ctx.availableSeats,
      rankingScore: Number(rankingScore.toFixed(6))
    });
  }

  matches.sort((a, b) => b.rankingScore - a.rankingScore);
  return matches;
}

async function findLegacyMatchCandidates(pool, payload) {
  const contexts = await loadRouteContexts(pool, "active_status = TRUE");
  const homeLat = Number(payload.home_lat);
  const homeLng = Number(payload.home_lng);
  const officeLat = Number(payload.office_lat);
  const officeLng = Number(payload.office_lng);
  const maxPickupDistance = Number(payload.max_pickup_distance_m || 5000);

  const candidates = [];
  for (const ctx of contexts) {
    const pickupPoints = ctx.points.filter((item) => item.kind === "pickup");
    const dropPoints = ctx.points.filter((item) => item.kind === "drop");
    if (pickupPoints.length === 0 || dropPoints.length === 0) {
      continue;
    }
    if (ctx.availableSeats <= 0) {
      continue;
    }

    const pickupDistance = Math.min(
      ...pickupPoints.map((point) =>
        haversineDistanceM(homeLat, homeLng, Number(point.lat), Number(point.lng))
      )
    );
    if (pickupDistance > maxPickupDistance) {
      continue;
    }

    const dropDistance = Math.min(
      ...dropPoints.map((point) =>
        haversineDistanceM(officeLat, officeLng, Number(point.lat), Number(point.lng))
      )
    );

    const reliability = reliabilityScore(mapReliability(ctx.reliabilityRow));
    const overlapScore = Math.max(0.0, 1.0 - dropDistance / 6000.0);
    const score = scoreCandidate({
      pickupDistanceM: pickupDistance,
      reliabilityScore: reliability,
      pricePerSeat: Number(ctx.route.price_per_seat),
      overlapScore
    });

    candidates.push({
      route_id: String(ctx.route.id),
      driver_id: ctx.route.driver_id,
      score,
      pickup_distance_m: Number(pickupDistance.toFixed(2)),
      price_per_seat: Number(ctx.route.price_per_seat),
      reliability_score: Number(reliability.toFixed(4))
    });
  }
  candidates.sort((a, b) => b.score - a.score);
  return candidates;
}

async function listChatThreads(pool, userId) {
  const res = await pool.query(
    `SELECT t.id, t.route_id, t.title, t.last_message, p.unread_count
     FROM chat_threads t
     JOIN chat_participants p ON p.thread_id = t.id AND p.user_id = $1
     ORDER BY t.updated_at DESC, t.created_at DESC`,
    [userId]
  );

  return res.rows.map((row) => ({
    id: String(row.id),
    tripId: row.route_id ? String(row.route_id) : "",
    title: row.title,
    lastMessage: row.last_message || "",
    unreadCount: Number(row.unread_count || 0)
  }));
}

function mapSenderForRequester(rawSender, requesterId) {
  const value = String(rawSender || "").trim();
  const upper = value.toUpperCase();
  if (upper === "SYSTEM") return "SYSTEM";
  if (requesterId && value === String(requesterId)) return "ME";
  // Legacy seed rows store "ME"/"OTHER" literals before per-user senders existed
  if (upper === "ME") return "ME";
  return "OTHER";
}

async function assertChatParticipant(pool, threadId, userId) {
  const threadRes = await pool.query(
    `SELECT t.id
     FROM chat_threads t
     JOIN chat_participants p ON p.thread_id = t.id AND p.user_id = $2
     WHERE t.id = $1
     LIMIT 1`,
    [threadId, userId]
  );
  if (threadRes.rows.length === 0) {
    const error = new Error("Thread not found");
    error.status = 404;
    throw error;
  }
}

async function listChatMessages(pool, threadId, requesterId = null) {
  await assertChatParticipant(pool, threadId, requesterId);

  const res = await pool.query(
    `SELECT id, thread_id, sender, text, timestamp_ms
     FROM chat_messages
     WHERE thread_id = $1
     ORDER BY timestamp_ms ASC, created_at ASC`,
    [threadId]
  );

  return res.rows.map((row) => ({
    id: String(row.id),
    threadId: String(row.thread_id),
    sender: mapSenderForRequester(row.sender, requesterId),
    text: row.text,
    timestamp: Number(row.timestamp_ms)
  }));
}

// Hard cap on chat message length. 4000 chars is well above any
// realistic ride-coordination message ("I'm at the kopitiam, blue
// Myvi, 5 min") and well below anything that could slow the Postgres
// path or DoS the response. Enforced before DB write so the row never
// lands oversize.
const MAX_CHAT_MESSAGE_CHARS = 4000;

async function appendChatMessage(pool, threadId, text, sender = "ME") {
  const trimmedText = String(text || "").trim();
  if (!trimmedText) {
    const error = new Error("text is required");
    error.status = 400;
    throw error;
  }
  if (trimmedText.length > MAX_CHAT_MESSAGE_CHARS) {
    const error = new Error("message_too_long");
    error.status = 413;
    throw error;
  }

  await assertChatParticipant(pool, threadId, sender);

  const messageId = randomUUID();
  const timestampMs = Date.now();
  // Sender is stored as the user id for authenticated messages; legacy/seed rows
  // may use "ME"/"OTHER"/"SYSTEM" literals. listChatMessages maps these per-requester.
  await pool.query(
    `INSERT INTO chat_messages (id, thread_id, sender, text, timestamp_ms)
     VALUES ($1, $2, $3, $4, $5)`,
    [messageId, threadId, String(sender || "ME"), trimmedText, timestampMs]
  );

  await pool.query(
    `UPDATE chat_threads
     SET last_message = $2, updated_at = NOW()
     WHERE id = $1`,
    [threadId, trimmedText]
  );
  await pool.query(
    `UPDATE chat_participants
     SET unread_count = CASE WHEN user_id = $2 THEN 0 ELSE unread_count + 1 END
     WHERE thread_id = $1`,
    [threadId, String(sender)]
  );

  // Look up the thread's route + the OTHER participants so the
  // server can push a CHAT_MESSAGE notification per recipient.
  // Returning these alongside the DTO keeps the notification policy
  // in server.js (where createNotification + APNs hookup live)
  // without leaking the notifications table into the data layer.
  const recipientRes = await pool.query(
    `SELECT user_id
       FROM chat_participants
      WHERE thread_id = $1 AND user_id <> $2`,
    [threadId, String(sender)]
  );
  const threadRes = await pool.query(
    `SELECT route_id, title FROM chat_threads WHERE id = $1`,
    [threadId]
  );
  const recipients = recipientRes.rows.map((row) => String(row.user_id));
  const routeId = threadRes.rows[0]?.route_id ? String(threadRes.rows[0].route_id) : null;
  const threadTitle = threadRes.rows[0]?.title || null;

  // Return the DTO shape the iOS client expects so callers can
  // reconcile their optimistic local row with the server-assigned id.
  return {
    id: String(messageId),
    threadId: String(threadId),
    sender: "ME",
    text: trimmedText,
    timestamp: Number(timestampMs),
    _notify: { recipients, routeId, threadTitle }
  };
}

/// Marks a thread as read for a single participant. Used when a user
/// opens the chat — without it, `unread_count` only ever resets for
/// senders, so the inbox kicker keeps growing.
async function markChatThreadRead(pool, threadId, userId) {
  await assertChatParticipant(pool, threadId, userId);
  const result = await pool.query(
    `UPDATE chat_participants
        SET unread_count = 0
      WHERE thread_id = $1 AND user_id = $2`,
    [threadId, String(userId)]
  );
  return result.rowCount;
}

module.exports = {
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
  markChatThreadRead,
  assertChatParticipant,
  normalizeDaysOfWeek,
  normalizeActiveStatus
};
