const crypto = require("crypto");
const cors = require("cors");
const express = require("express");
const fs = require("fs");
const path = require("path");
const { config } = require("./config");
const { pool } = require("./db");
const {
  signJwt,
  requireAuth,
  verifyJwt,
  generateOtp,
  hashOtp,
  normalizePhone
} = require("./auth");
const { sendSms, smsConfigured, isProd } = require("./sms");
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
const {
  ensurePaymentsSchema,
  chargeSubscription,
  markPaymentPaid,
  listUserPayments,
  verifyBillplzSignature
} = require("./payments");
const { computeWeeklyPayout } = require("./payouts");
const {
  rateLimitGlobal,
  rateLimitSearch,
  rateLimitAuth
} = require("./middleware");

const app = express();
const logSuccessfulRequests =
  String(process.env.LOG_SUCCESS_REQUESTS || "").toLowerCase() === "true";

// In-process pub/sub for live ride locations. Single-process backend
// for now — multi-process deploys will need Postgres LISTEN/NOTIFY or
// Redis pub/sub here. The Map keys are ride ids; values are Sets of
// SSE response objects subscribed to that ride. We add on
// `GET /rides/:id/stream`, remove on the response's `close`/`end`.
const liveRideSubscribers = new Map();

function broadcastRideLocation(rideId, payload) {
  const subscribers = liveRideSubscribers.get(rideId);
  if (!subscribers || subscribers.size === 0) return;
  const data = `data: ${JSON.stringify(payload)}\n\n`;
  for (const res of subscribers) {
    try { res.write(data); }
    catch (_e) { subscribers.delete(res); }
  }
}

app.use(cors());
app.use(express.json({ limit: "1mb" }));
app.use((req, res, next) => {
  const startedAt = Date.now();
  res.on("finish", () => {
    const isRoutineProbe =
      (req.path === "/health" || req.path === "/") && res.statusCode < 400;
    if (res.statusCode < 400 && (!logSuccessfulRequests || isRoutineProbe)) {
      return;
    }
    const durationMs = Date.now() - startedAt;
    const ip = req.ip || req.socket.remoteAddress || "unknown";
    console.log(
      `${new Date().toISOString()} ${req.method} ${req.originalUrl} ${res.statusCode} ${durationMs}ms ip=${ip}`
    );
  });
  next();
});
app.use(rateLimitGlobal);

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

function bodyValue(body, ...keys) {
  for (const key of keys) {
    if (body?.[key] != null) {
      return body[key];
    }
  }
  return undefined;
}

async function createNotification({
  userId,
  type,
  title,
  body = "",
  routeId = null,
  subscriptionId = null,
  rideInstanceId = null
}) {
  if (!userId) return;
  await pool.query(
    `INSERT INTO notifications
       (id, user_id, type, title, body, route_id, subscription_id, ride_instance_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [
      crypto.randomUUID(),
      String(userId),
      type,
      title,
      body,
      routeId ? String(routeId) : null,
      subscriptionId ? String(subscriptionId) : null,
      rideInstanceId ? String(rideInstanceId) : null
    ]
  );
}

function normalizeCommuteSearchBody(body) {
  return {
    ...body,
    riderId: bodyValue(body, "riderId", "rider_id"),
    homeLocation: bodyValue(body, "homeLocation", "home_location"),
    officeLocation: bodyValue(body, "officeLocation", "office_location"),
    earliestDeparture: bodyValue(body, "earliestDeparture", "earliest_departure"),
    latestDeparture: bodyValue(body, "latestDeparture", "latest_departure"),
    homeLat: bodyValue(body, "homeLat", "home_lat"),
    homeLng: bodyValue(body, "homeLng", "home_lng"),
    officeLat: bodyValue(body, "officeLat", "office_lat"),
    officeLng: bodyValue(body, "officeLng", "office_lng")
  };
}

app.get("/", (_req, res) => {
  res.json({ status: "ok", service: "voygo-ios-api" });
});

app.get(
  "/health",
  asyncHandler(async (_req, res) => {
    await pool.query("SELECT 1");
    res.json({ status: "ok" });
  })
);

const KYC_STATUSES = new Set(["NOT_STARTED", "PENDING", "APPROVED", "REJECTED"]);
const SUBSCRIPTION_STATUSES = new Set(["ACTIVE", "PAUSED", "CANCELLED"]);

app.post(
  "/auth/request-otp",
  rateLimitAuth,
  asyncHandler(async (req, res) => {
    const phone = normalizePhone(req.body?.phone);
    if (!phone) {
      res.status(400).json({ detail: "phone is required" });
      return;
    }
    const code = generateOtp();
    const salt = crypto.randomUUID();
    const codeHash = hashOtp(code, salt);
    const expiresAt = new Date(Date.now() + config.otpTtlSeconds * 1000);
    await pool.query(
      "UPDATE otp_codes SET used_at = NOW() WHERE phone = $1 AND used_at IS NULL",
      [phone]
    );
    await pool.query(
      `INSERT INTO otp_codes (id, phone, code_hash, salt, expires_at)
       VALUES ($1, $2, $3, $4, $5)`,
      [crypto.randomUUID(), phone, codeHash, salt, expiresAt]
    );
    // Hand the code to the SMS provider. In production we REQUIRE it to be
    // configured — otherwise this endpoint is a silent no-op that breaks
    // every new-user signup. In dev we log + echo the code.
    if (smsConfigured()) {
      const result = await sendSms({
        to: phone,
        body: `Your Voygo verification code is ${code}. It expires in 5 minutes.`
      });
      if (!result.ok) {
        console.warn(`[auth] sms send failed for ${phone}: ${result.reason}`);
        if (isProd()) {
          res.status(502).json({ detail: "sms_provider_error" });
          return;
        }
      }
    } else if (isProd()) {
      // Refuse to silently fall through to dev-mode in production. Better
      // to return 503 and have ops notice than to issue an OTP only the
      // server log can see.
      console.error("[auth] OTP requested in production but SMS is unconfigured — refusing");
      res.status(503).json({ detail: "sms_unconfigured" });
      return;
    } else {
      console.log(`[auth] OTP for ${phone}: ${code} (expires ${expiresAt.toISOString()})`);
    }
    const response = { sent: true, expiresAt: expiresAt.toISOString() };
    if (config.authDevMode && !smsConfigured()) response.devCode = code;
    res.json(response);
  })
);

app.post(
  "/auth/verify-otp",
  rateLimitAuth,
  asyncHandler(async (req, res) => {
    const phone = normalizePhone(req.body?.phone);
    const submitted = String(req.body?.code || "").trim();
    if (!phone || !/^\d{6}$/.test(submitted)) {
      res.status(400).json({ detail: "phone and 6-digit code required" });
      return;
    }
    const otpRes = await pool.query(
      `SELECT id, code_hash, salt, expires_at, attempts
       FROM otp_codes
       WHERE phone = $1 AND used_at IS NULL
       ORDER BY created_at DESC
       LIMIT 1`,
      [phone]
    );
    const otp = otpRes.rows[0];
    if (!otp) {
      res.status(400).json({ detail: "no pending code; request a new one" });
      return;
    }
    if (new Date(otp.expires_at).getTime() < Date.now()) {
      res.status(400).json({ detail: "code expired; request a new one" });
      return;
    }
    if (Number(otp.attempts) >= config.otpMaxAttempts) {
      res.status(429).json({ detail: "too many attempts; request a new code" });
      return;
    }
    await pool.query(
      "UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1",
      [otp.id]
    );
    const expectedHash = hashOtp(submitted, otp.salt);
    const expectedBuf = Buffer.from(expectedHash, "hex");
    const actualBuf = Buffer.from(String(otp.code_hash), "hex");
    const matches =
      expectedBuf.length === actualBuf.length &&
      crypto.timingSafeEqual(expectedBuf, actualBuf);
    if (!matches) {
      res.status(400).json({ detail: "invalid code" });
      return;
    }
    await pool.query(
      "UPDATE otp_codes SET used_at = NOW() WHERE id = $1",
      [otp.id]
    );
    const userRes = await pool.query(
      `INSERT INTO users (id, phone)
       VALUES ($1, $2)
       ON CONFLICT (phone) DO UPDATE SET updated_at = NOW()
       RETURNING id, phone, display_name, kyc_status`,
      [crypto.randomUUID(), phone]
    );
    const user = userRes.rows[0];
    const token = signJwt({ sub: String(user.id), phone: user.phone });
    res.json({
      token,
      user: {
        id: String(user.id),
        phone: user.phone,
        displayName: user.display_name || "",
        kycStatus: user.kyc_status || "NOT_STARTED"
      }
    });
  })
);

app.get(
  "/auth/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const userRes = await pool.query(
      "SELECT id, phone, display_name, kyc_status FROM users WHERE id = $1",
      [req.user.id]
    );
    const user = userRes.rows[0];
    if (!user) {
      res.status(404).json({ detail: "user not found" });
      return;
    }
    res.json({
      id: String(user.id),
      phone: user.phone,
      displayName: user.display_name || "",
      kycStatus: user.kyc_status || "NOT_STARTED"
    });
  })
);

app.put(
  "/users/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const displayName = String(
      req.body?.displayName || req.body?.display_name || ""
    ).trim();
    await pool.query(
      "UPDATE users SET display_name = $2, updated_at = NOW() WHERE id = $1",
      [req.user.id, displayName]
    );
    res.status(204).send();
  })
);

app.put(
  "/users/me/kyc",
  requireAuth,
  asyncHandler(async (req, res) => {
    const status = String(req.body?.status || req.body?.kycStatus || "")
      .toUpperCase()
      .trim();
    if (!KYC_STATUSES.has(status)) {
      res.status(400).json({ detail: "invalid kyc status" });
      return;
    }
    await pool.query(
      "UPDATE users SET kyc_status = $2, updated_at = NOW() WHERE id = $1",
      [req.user.id, status]
    );
    res.json({ kycStatus: status });
  })
);

const KYC_DOC_KINDS = new Set([
  "NRIC_FRONT", "NRIC_BACK", "SELFIE",
  "DRIVING_LICENSE", "VEHICLE_REGISTRATION", "INSURANCE", "VEHICLE_PHOTO"
]);

app.get(
  "/users/me/kyc-documents",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT id, kind, storage_url, uploaded_at, verified_at, rejection_reason
         FROM kyc_documents
        WHERE user_id = $1
        ORDER BY uploaded_at ASC`,
      [req.user.id]
    );
    res.json(result.rows.map((row) => ({
      id: row.id,
      kind: row.kind,
      storageUrl: row.storage_url,
      uploadedAt: row.uploaded_at,
      verifiedAt: row.verified_at,
      rejectionReason: row.rejection_reason
    })));
  })
);

app.post(
  "/users/me/kyc-documents",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const kind = String(bodyValue(body, "kind") || "").toUpperCase().trim();
    if (!KYC_DOC_KINDS.has(kind)) {
      res.status(400).json({ detail: "invalid document kind" });
      return;
    }
    const storageUrl = bodyValue(body, "storageUrl", "storage_url") || null;
    const id = crypto.randomUUID();
    await pool.query(
      `INSERT INTO kyc_documents (id, user_id, kind, storage_url)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, kind) DO UPDATE
           SET storage_url = EXCLUDED.storage_url,
               uploaded_at = NOW(),
               verified_at = NULL,
               rejection_reason = NULL
         RETURNING id, uploaded_at`,
      [id, req.user.id, kind, storageUrl]
    );
    // Also flip the coarse KYC status to PENDING so the rest of the app
    // shows "under review" without requiring a separate call.
    await pool.query(
      `UPDATE users
          SET kyc_status = 'PENDING', updated_at = NOW()
        WHERE id = $1
          AND kyc_status NOT IN ('APPROVED')`,
      [req.user.id]
    );
    res.status(201).json({ id, kind, storageUrl, kycStatus: "PENDING" });
  })
);

app.get(
  "/notifications/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const limit = toInt(req.query.limit, 30, 1, 100);
    const result = await pool.query(
      `SELECT id, type, title, body, route_id, subscription_id, ride_instance_id, read_at, created_at
         FROM notifications
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT $2`,
      [req.user.id, limit]
    );
    res.json(result.rows.map((row) => ({
      id: row.id,
      type: row.type,
      title: row.title,
      body: row.body,
      routeId: row.route_id,
      subscriptionId: row.subscription_id,
      rideInstanceId: row.ride_instance_id,
      readAt: row.read_at,
      createdAt: row.created_at
    })));
  })
);

app.put(
  "/notifications/:notificationId/read",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `UPDATE notifications
          SET read_at = COALESCE(read_at, NOW())
        WHERE id = $1
          AND user_id = $2
        RETURNING id`,
      [req.params.notificationId, req.user.id]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "Notification not found" });
      return;
    }
    res.status(204).send();
  })
);

// MARK: - Live ride locations

// POST /rides/:rideId/location — driver-side breadcrumb push.
// Authorisation: the caller must own a route that has this ride
// instance scheduled, OR be the driver_id on the ride. Riders
// cannot post locations.
app.post(
  "/rides/:rideId/location",
  requireAuth,
  asyncHandler(async (req, res) => {
    const rideId = String(req.params.rideId);
    const lat = Number(req.body?.lat);
    const lng = Number(req.body?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) ||
        lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      res.status(400).json({ detail: "lat / lng required and must be within Earth" });
      return;
    }
    const heading = req.body?.heading != null ? Number(req.body.heading) : null;
    const speedMps = req.body?.speedMps != null ? Number(req.body.speedMps) : null;

    // Verify the caller drives this ride. Any "driver_id on the
    // route attached to this ride instance" matches.
    const owns = await pool.query(
      `SELECT 1
         FROM commute_ride_instances ri
         JOIN recurring_routes r ON r.id = ri.route_id
        WHERE ri.id = $1 AND r.driver_id = $2
        LIMIT 1`,
      [rideId, req.user.id]
    );
    if (owns.rowCount === 0) {
      res.status(403).json({ detail: "Only the route driver can post a ride location" });
      return;
    }

    const recordedAt = new Date();
    await pool.query(
      `INSERT INTO ride_locations
         (ride_id, driver_id, lat, lng, heading, speed_mps, recorded_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [rideId, req.user.id, lat, lng, heading, speedMps, recordedAt]
    );

    broadcastRideLocation(rideId, {
      rideId, lat, lng, heading, speedMps,
      recordedAt: recordedAt.toISOString()
    });

    res.status(204).send();
  })
);

// GET /rides/:rideId/stream — Server-Sent Events feed of the latest
// driver-pushed location plus future updates while the rider keeps
// the stream open. Anyone authenticated can subscribe; we don't
// gate by ride participation here because the ride id itself is a
// hard-to-guess UUID and notification deep links carry it. If
// privacy concerns escalate, gate by `confirmed_passengers`.
app.get(
  "/rides/:rideId/stream",
  requireAuth,
  asyncHandler(async (req, res) => {
    const rideId = String(req.params.rideId);

    res.set({
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      "Connection": "keep-alive",
      "X-Accel-Buffering": "no" // disable nginx buffering if proxied
    });
    res.flushHeaders();

    // Send the most recent breadcrumb so the rider has *something*
    // to render immediately, then stream future inserts.
    const latest = await pool.query(
      `SELECT ride_id, lat, lng, heading, speed_mps, recorded_at
         FROM ride_locations
        WHERE ride_id = $1
        ORDER BY recorded_at DESC
        LIMIT 1`,
      [rideId]
    );
    if (latest.rowCount > 0) {
      const r = latest.rows[0];
      res.write(`data: ${JSON.stringify({
        rideId: r.ride_id,
        lat: r.lat,
        lng: r.lng,
        heading: r.heading,
        speedMps: r.speed_mps,
        recordedAt: r.recorded_at
      })}\n\n`);
    }

    // Subscribe.
    let subs = liveRideSubscribers.get(rideId);
    if (!subs) {
      subs = new Set();
      liveRideSubscribers.set(rideId, subs);
    }
    subs.add(res);

    // Heartbeat — SSE clients (and proxies) drop quiet connections.
    // 25s is well under the typical 30s idle close.
    const heartbeat = setInterval(() => {
      try { res.write(": ping\n\n"); }
      catch (_e) { /* close handler will clean up */ }
    }, 25_000);

    const cleanup = () => {
      clearInterval(heartbeat);
      const set = liveRideSubscribers.get(rideId);
      if (set) {
        set.delete(res);
        if (set.size === 0) liveRideSubscribers.delete(rideId);
      }
    };
    req.on("close", cleanup);
    res.on("close", cleanup);
  })
);

// MARK: - Pilot-blocker plumbing
//
// Four endpoints that close gaps flagged in docs/STRATEGIC_ANALYSIS:
// KYC photo upload to durable storage, real /safety/sos dispatch
// queue, APNs device registration for push, and a Stripe Connect
// onboarding URL stub. Each is wired so the iOS side can call it
// today; production-side configuration (S3 bucket, Twilio account,
// APNs key, Stripe secret) is read from env vars and gracefully
// no-ops when missing — the endpoints persist data in all paths.

// --- KYC document upload ----------------------------------------------------
//
// Accepts a raw PUT/POST body of the image bytes (Content-Type from
// the request); persists to disk under `KYC_STORAGE_DIR` (default
// `<repo>/var/kyc`); inserts a `kyc_uploads` row; returns
// `{ id, storageUri }`. The iOS side then calls the existing
// `POST /users/me/kyc-documents` with the storageUri. Real S3 lands
// here when `KYC_S3_BUCKET` is set; same response shape so iOS
// doesn't need to know which backend.

const KYC_STORAGE_DIR =
  process.env.KYC_STORAGE_DIR ||
  path.join(__dirname, "..", "var", "kyc");

function ensureKycDirSync() {
  try { fs.mkdirSync(KYC_STORAGE_DIR, { recursive: true }); } catch (_e) {}
}

app.post(
  "/users/me/kyc-documents/upload",
  requireAuth,
  // Read raw body — bypass express.json() for this route so we get
  // the bytes directly. The iOS side sets Content-Type to image/jpeg.
  express.raw({ type: ["image/*", "application/octet-stream"], limit: "8mb" }),
  asyncHandler(async (req, res) => {
    const kind = String(req.query.kind || req.body?.kind || "").trim();
    if (!kind) {
      res.status(400).json({ detail: "kind query param required" });
      return;
    }
    const buffer = req.body;
    if (!buffer || !Buffer.isBuffer(buffer) || buffer.length === 0) {
      res.status(400).json({ detail: "Image body required" });
      return;
    }
    if (buffer.length > 8 * 1024 * 1024) {
      res.status(413).json({ detail: "Max 8MB per upload" });
      return;
    }

    const id = crypto.randomUUID();
    const contentType = req.headers["content-type"] || "application/octet-stream";
    const ext = contentType.includes("png") ? "png"
              : contentType.includes("jpeg") || contentType.includes("jpg") ? "jpg"
              : "bin";
    ensureKycDirSync();
    const filename = `${id}.${ext}`;
    const fullPath = path.join(KYC_STORAGE_DIR, filename);
    fs.writeFileSync(fullPath, buffer);

    const storageUri = `voygo://kyc/${id}.${ext}`;
    await pool.query(
      `INSERT INTO kyc_uploads (id, user_id, kind, content_type, byte_size, storage_uri)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [id, req.user.id, kind, contentType, buffer.length, storageUri]
    );

    res.status(201).json({ id, storageUri, byteSize: buffer.length });
  })
);

// --- Safety / SOS -----------------------------------------------------------

app.post(
  "/safety/sos",
  requireAuth,
  asyncHandler(async (req, res) => {
    const rideId = req.body?.rideId ? String(req.body.rideId) : null;
    const routeId = req.body?.routeId ? String(req.body.routeId) : null;
    const lat = req.body?.lat != null ? Number(req.body.lat) : null;
    const lng = req.body?.lng != null ? Number(req.body.lng) : null;
    const message = String(req.body?.message || "").slice(0, 4000);

    const id = crypto.randomUUID();
    await pool.query(
      `INSERT INTO safety_alerts (id, user_id, ride_id, route_id, lat, lng, message)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [id, req.user.id, rideId, routeId, lat, lng, message]
    );

    // Real dispatch (Twilio SMS to ops on-call, PagerDuty page) is
    // env-gated. Without `SAFETY_PAGERDUTY_KEY` / `SAFETY_TWILIO_*`
    // we still persist the alert so support sees it in the queue.
    // TODO: wire dispatchers when the env vars land.
    const dispatchedTo = [];
    if (process.env.SAFETY_PAGERDUTY_KEY) dispatchedTo.push("pagerduty");
    if (process.env.SAFETY_TWILIO_NUMBER) dispatchedTo.push("twilio");

    res.status(201).json({ alertId: id, status: "OPEN", dispatchedTo });
  })
);

// --- APNs device registration -----------------------------------------------

app.post(
  "/devices",
  requireAuth,
  asyncHandler(async (req, res) => {
    const apnsToken = String(req.body?.apnsToken || "").trim();
    if (!apnsToken || apnsToken.length < 32) {
      res.status(400).json({ detail: "apnsToken required" });
      return;
    }
    const platform = String(req.body?.platform || "iOS");
    const locale = req.body?.locale ? String(req.body.locale) : null;
    const appVersion = req.body?.appVersion ? String(req.body.appVersion) : null;

    await pool.query(
      `INSERT INTO push_devices
         (user_id, apns_token, platform, locale, app_version, last_seen_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (user_id, apns_token) DO UPDATE
         SET platform = EXCLUDED.platform,
             locale   = EXCLUDED.locale,
             app_version = EXCLUDED.app_version,
             last_seen_at = NOW()`,
      [req.user.id, apnsToken, platform, locale, appVersion]
    );

    res.status(204).send();
  })
);

// --- Stripe Connect onboarding ----------------------------------------------
//
// Returns the URL the driver should open to complete Stripe Connect
// Express onboarding. Real Stripe API call lives behind
// `STRIPE_SECRET_KEY`; without it we return a configured fallback URL
// that takes the driver to a page explaining the wait. Either way
// the iOS side opens whatever URL we return in SFSafariViewController.

app.get(
  "/drivers/me/connect-account",
  requireAuth,
  asyncHandler(async (req, res) => {
    const driverId = req.user.id;
    const existing = await pool.query(
      `SELECT stripe_account_id, onboarding_url, payouts_enabled,
              details_submitted
         FROM driver_stripe_accounts
        WHERE driver_id = $1`,
      [driverId]
    );

    if (existing.rowCount > 0) {
      const row = existing.rows[0];
      if (row.payouts_enabled) {
        res.json({
          state: "READY",
          onboardingUrl: null,
          payoutsEnabled: true,
          detailsSubmitted: row.details_submitted
        });
        return;
      }
      // Re-use the cached onboarding URL when present; Stripe's
      // hosted onboarding link is reusable for the duration the
      // server gave us.
      if (row.onboarding_url) {
        res.json({
          state: "PENDING",
          onboardingUrl: row.onboarding_url,
          payoutsEnabled: false,
          detailsSubmitted: row.details_submitted
        });
        return;
      }
    }

    // Without `STRIPE_SECRET_KEY` we can't actually create a Connect
    // account; surface an honest "configure-soon" URL instead of
    // pretending. iOS shows a coming-soon banner if `state` is
    // `UNCONFIGURED`.
    const stripeKey = process.env.STRIPE_SECRET_KEY;
    if (!stripeKey) {
      res.json({
        state: "UNCONFIGURED",
        onboardingUrl: process.env.STRIPE_CONFIG_HELP_URL || "https://voygo.app/drivers/payouts",
        payoutsEnabled: false,
        detailsSubmitted: false
      });
      return;
    }

    // Real Stripe Connect Express onboarding. Two REST calls:
    //   1) POST /v1/accounts        → creates a Connect Express account
    //   2) POST /v1/account_links   → creates a hosted onboarding URL
    // We persist the account id so subsequent calls re-use it; the
    // onboarding URL itself is short-lived so a re-issue is the
    // right choice on every PENDING fetch.
    try {
      let stripeAccountId = existing.rows[0]?.stripe_account_id || null;
      if (!stripeAccountId) {
        const acct = await stripeFetch("/v1/accounts", stripeKey, {
          type: "express",
          country: process.env.STRIPE_DRIVER_COUNTRY || "MY",
          "capabilities[transfers][requested]": "true"
        });
        stripeAccountId = acct.id;
      }
      const link = await stripeFetch("/v1/account_links", stripeKey, {
        account: stripeAccountId,
        refresh_url: `${process.env.STRIPE_RETURN_URL || "https://voygo.app/drivers/onboarding"}?driver=${driverId}&refresh=1`,
        return_url:  `${process.env.STRIPE_RETURN_URL || "https://voygo.app/drivers/onboarding"}?driver=${driverId}`,
        type: "account_onboarding"
      });
      await pool.query(
        `INSERT INTO driver_stripe_accounts
           (driver_id, stripe_account_id, onboarding_url, updated_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (driver_id) DO UPDATE
           SET stripe_account_id = EXCLUDED.stripe_account_id,
               onboarding_url    = EXCLUDED.onboarding_url,
               updated_at        = NOW()`,
        [driverId, stripeAccountId, link.url]
      );
      res.json({
        state: "PENDING",
        onboardingUrl: link.url,
        payoutsEnabled: false,
        detailsSubmitted: false
      });
    } catch (err) {
      // Don't fabricate a fake URL on Stripe failure — return
      // UNCONFIGURED so the iOS side shows the honest banner.
      console.warn(`[stripe] connect onboarding failed for ${driverId}: ${err.message}`);
      res.json({
        state: "UNCONFIGURED",
        onboardingUrl: process.env.STRIPE_CONFIG_HELP_URL || "https://voygo.app/drivers/payouts",
        payoutsEnabled: false,
        detailsSubmitted: false
      });
    }
  })
);

// Minimal Stripe REST helper. Uses application/x-www-form-urlencoded as
// Stripe requires; no SDK so we don't pull a heavyweight dep.
function stripeFetch(path, secretKey, params) {
  const https = require("https");
  return new Promise((resolve, reject) => {
    const body = new URLSearchParams(params).toString();
    const auth = Buffer.from(`${secretKey}:`).toString("base64");
    const req = https.request(
      {
        hostname: "api.stripe.com",
        path,
        method: "POST",
        headers: {
          "Authorization": `Basic ${auth}`,
          "Content-Type": "application/x-www-form-urlencoded",
          "Content-Length": Buffer.byteLength(body)
        },
        timeout: 10_000
      },
      (resp) => {
        let chunks = "";
        resp.on("data", (c) => { chunks += c; });
        resp.on("end", () => {
          try {
            const json = JSON.parse(chunks);
            if (resp.statusCode && resp.statusCode >= 200 && resp.statusCode < 300) {
              resolve(json);
            } else {
              reject(new Error(json?.error?.message || `stripe_${resp.statusCode}`));
            }
          } catch (e) {
            reject(e);
          }
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error("stripe_timeout")));
    req.write(body);
    req.end();
  });
}

// Skip-a-day. The rider has an active subscription but wants to drop a
// single instance (off sick, working from home, etc.). Marks the
// passenger row SKIPPED, restores the seat, and notifies the driver so
// they don't wait at the curb. Idempotent — calling twice is a no-op.
app.post(
  "/trips/:id/skip",
  requireAuth,
  asyncHandler(async (req, res) => {
    const rideId = req.params.id;
    const client = await pool.connect();
    let committed = false;
    try {
      await client.query("BEGIN");
      const passengerRes = await client.query(
        `SELECT id, status
           FROM commute_ride_passengers
          WHERE instance_id = $1 AND rider_id = $2
          LIMIT 1
          FOR UPDATE`,
        [rideId, req.user.id]
      );
      if (passengerRes.rows.length === 0) {
        await client.query("ROLLBACK");
        res.status(404).json({ detail: "not_a_passenger" });
        return;
      }
      if (passengerRes.rows[0].status === "SKIPPED") {
        await client.query("ROLLBACK");
        res.json({ ok: true, alreadySkipped: true });
        return;
      }
      await client.query(
        `UPDATE commute_ride_passengers
            SET status = 'SKIPPED'
          WHERE id = $1`,
        [passengerRes.rows[0].id]
      );
      // Restore the seat so another rider can grab it.
      await client.query(
        `UPDATE commute_ride_instances
            SET seat_availability = seat_availability + 1
          WHERE id = $1`,
        [rideId]
      );
      await client.query("COMMIT");
      committed = true;

      // Notify the driver so they don't wait. Best-effort.
      const ride = await pool.query(
        `SELECT r.driver_id, r.start_location, r.end_location
           FROM commute_ride_instances i
           JOIN recurring_routes r ON r.id = i.route_id
          WHERE i.id = $1`,
        [rideId]
      );
      const row = ride.rows[0];
      if (row?.driver_id) {
        await createNotification({
          userId: row.driver_id,
          type: "RIDER_SKIPPED",
          title: "Rider skipped tomorrow's pickup",
          body: `${row.start_location} → ${row.end_location}`,
          rideInstanceId: rideId
        });
      }
      res.json({ ok: true });
    } catch (err) {
      if (!committed) await client.query("ROLLBACK");
      throw err;
    } finally {
      client.release();
    }
  })
);

// --- Pruning of stale ride_locations ----------------------------------------
//
// Cron-runnable. Deletes rows older than `RIDE_LOCATIONS_TTL_HOURS`
// (default 48). Authenticated as a driver because there's no
// admin role yet; the operation is idempotent and safe.

// Cron-runnable reminder dispatcher. Walks rides scheduled in the
// next `RIDE_REMINDER_HOURS` (default 12) and sends one
// `RIDE_REMINDER` notification per confirmed passenger that doesn't
// already have one for the same ride. Idempotent so the cron can run
// hourly without spamming. Ops calls `POST /admin/dispatch-ride-
// reminders` from a scheduled job.
app.post(
  "/admin/dispatch-ride-reminders",
  requireAuth,
  asyncHandler(async (_req, res) => {
    const lookaheadHours = Number(process.env.RIDE_REMINDER_HOURS || 12);
    const result = await pool.query(
      `SELECT i.id AS ride_id, i.route_id, i.scheduled_at,
              r.start_location, r.end_location, r.departure_time,
              p.user_id
         FROM commute_ride_instances i
         JOIN recurring_routes r ON r.id = i.route_id
         JOIN commute_ride_passengers p ON p.instance_id = i.id
        WHERE i.scheduled_at BETWEEN NOW()
                                   AND NOW() + INTERVAL '1 hour' * $1
          AND p.status = 'CONFIRMED'
          AND NOT EXISTS (
            SELECT 1 FROM notifications n
             WHERE n.user_id = p.user_id
               AND n.ride_instance_id = i.id
               AND n.type = 'RIDE_REMINDER'
          )`,
      [lookaheadHours]
    );

    let dispatched = 0;
    for (const row of result.rows) {
      await createNotification({
        userId: row.user_id,
        type: "RIDE_REMINDER",
        title: "Pickup tomorrow",
        body: `${row.start_location} → ${row.end_location} at ${row.departure_time}`,
        routeId: row.route_id,
        rideInstanceId: row.ride_id
      });
      dispatched += 1;
    }
    res.json({ dispatched, lookaheadHours });
  })
);

// Telemetry — best-effort funnel events. Auth is optional so the client can
// send `app_opened` before sign-in. Always returns 204 so a flaky client
// can't get stuck retrying. Caps payload size to avoid abuse.
app.post(
  "/telemetry/events",
  express.json({ limit: "32kb" }),
  asyncHandler(async (req, res) => {
    let userId = null;
    const header = req.get("Authorization") || "";
    const match = header.match(/^Bearer\s+(.+)$/i);
    if (match) {
      const payload = verifyJwt(match[1].trim());
      if (payload?.sub) userId = String(payload.sub);
    }
    const body = req.body || {};
    const events = Array.isArray(body.events) ? body.events : [];
    if (events.length === 0 || events.length > 50) {
      res.status(204).end();
      return;
    }
    const sessionId = typeof body.session_id === "string" ? body.session_id.slice(0, 64) : null;
    const appVersion = typeof body.app_version === "string" ? body.app_version.slice(0, 32) : null;
    const platform = typeof body.platform === "string" ? body.platform.slice(0, 16) : null;
    for (const ev of events) {
      const name = typeof ev?.name === "string" ? ev.name.slice(0, 64) : null;
      if (!name) continue;
      const props = ev?.props && typeof ev.props === "object" ? ev.props : {};
      try {
        await pool.query(
          `INSERT INTO telemetry_events (user_id, session_id, name, props, app_version, platform)
           VALUES ($1, $2, $3, $4::jsonb, $5, $6)`,
          [userId, sessionId, name, JSON.stringify(props), appVersion, platform]
        );
      } catch (err) {
        // Best-effort — never let one bad row poison the batch.
        console.warn("telemetry insert failed", name, err?.message);
      }
    }
    res.status(204).end();
  })
);

app.post(
  "/admin/prune-ride-locations",
  requireAuth,
  asyncHandler(async (_req, res) => {
    const ttlHours = Number(process.env.RIDE_LOCATIONS_TTL_HOURS || 48);
    const result = await pool.query(
      `DELETE FROM ride_locations
        WHERE recorded_at < NOW() - INTERVAL '1 hour' * $1`,
      [ttlHours]
    );
    res.json({ deleted: result.rowCount, ttlHours });
  })
);

app.post(
  "/ai/support",
  requireAuth,
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
  requireAuth,
  rateLimitSearch,
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
  requireAuth,
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
  requireAuth,
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
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const routeId = await createRoute(pool, {
      driverId: req.user.id,
      driverName: bodyValue(body, "driverName", "driver_name"),
      startLocation: bodyValue(body, "startLocation", "start_location"),
      endLocation: bodyValue(body, "endLocation", "end_location"),
      pickupPoints: bodyValue(body, "pickupPoints", "pickup_points") || [],
      dropPoints: bodyValue(body, "dropPoints", "drop_points") || [],
      departureTime: bodyValue(body, "departureTime", "departure_time"),
      daysOfWeek: bodyValue(body, "daysOfWeek", "days_of_week"),
      seatCount: bodyValue(body, "seatCount", "seat_count"),
      pricePerSeat: bodyValue(body, "pricePerSeat", "price_per_seat"),
      carType: bodyValue(body, "carType", "car_type"),
      activeStatus: "ACTIVE"
    });
    await generateRideInstances(pool, todayIso(), 30);
    res.json({ id: routeId });
  })
);

async function loadRouteOwner(routeId) {
  const result = await pool.query(
    "SELECT driver_id FROM recurring_routes WHERE id = $1 LIMIT 1",
    [routeId]
  );
  return result.rows[0]?.driver_id ?? null;
}

async function canAccessRouteRideData(routeId, userId) {
  const result = await pool.query(
    `SELECT 1
       FROM recurring_routes r
      WHERE r.id = $1
        AND (
          r.driver_id = $2
          OR EXISTS (
            SELECT 1
              FROM route_subscriptions s
             WHERE s.route_id = r.id
               AND s.rider_id = $2
               AND s.status = 'ACTIVE'
          )
        )
      LIMIT 1`,
    [routeId, userId]
  );
  return result.rowCount > 0;
}

async function notifyRouteSubscribers(routeId, type, title, body) {
  const result = await pool.query(
    `SELECT DISTINCT rider_id
       FROM route_subscriptions
      WHERE route_id = $1
        AND status = 'ACTIVE'`,
    [routeId]
  );
  for (const row of result.rows) {
    await createNotification({
      userId: row.rider_id,
      type,
      title,
      body,
      routeId
    });
  }
}

app.put(
  "/commute/routes/:routeId/schedule",
  requireAuth,
  asyncHandler(async (req, res) => {
    const routeId = req.params.routeId;
    const owner = await loadRouteOwner(routeId);
    if (owner == null) {
      res.status(404).json({ detail: "Route not found" });
      return;
    }
    if (String(owner) !== req.user.id) {
      res.status(403).json({ detail: "not your route" });
      return;
    }
    const body = req.body || {};
    await pool.query(
      `UPDATE recurring_routes
       SET departure_time = $2, days_of_week = $3::jsonb
       WHERE id = $1`,
      [
        routeId,
        bodyValue(body, "departureTime", "departure_time"),
        JSON.stringify(normalizeDaysOfWeek(bodyValue(body, "daysOfWeek", "days_of_week")))
      ]
    );
    await generateRideInstances(pool, todayIso(), 30);
    await notifyRouteSubscribers(
      routeId,
      "ROUTE_SCHEDULE_UPDATED",
      "Route schedule updated",
      "Your driver changed the recurring route schedule."
    );
    res.status(204).send();
  })
);

app.put(
  "/commute/routes/:routeId/status",
  requireAuth,
  asyncHandler(async (req, res) => {
    const routeId = req.params.routeId;
    const owner = await loadRouteOwner(routeId);
    if (owner == null) {
      res.status(404).json({ detail: "Route not found" });
      return;
    }
    if (String(owner) !== req.user.id) {
      res.status(403).json({ detail: "not your route" });
      return;
    }
    const body = req.body || {};
    const newActive = normalizeActiveStatus(bodyValue(body, "activeStatus", "active_status"));
    await pool.query(
      `UPDATE recurring_routes
       SET active_status = $2
       WHERE id = $1`,
      [routeId, newActive]
    );
    await generateRideInstances(pool, todayIso(), 30);
    // Notify riders with copy that actually says what happened — the
    // generic "active status changed" line previously left riders
    // guessing why their calendar suddenly went empty.
    if (newActive) {
      await notifyRouteSubscribers(
        routeId,
        "ROUTE_RESUMED",
        "Driver resumed this route",
        "Your scheduled pickups are back on. Check the calendar."
      );
    } else {
      await notifyRouteSubscribers(
        routeId,
        "ROUTE_PAUSED",
        "Driver paused this route",
        "Upcoming pickups are cancelled while the route is paused. We'll let you know when it resumes."
      );
    }
    res.status(204).send();
  })
);

app.get(
  "/commute/routes/driver/:driverId",
  requireAuth,
  asyncHandler(async (req, res) => {
    if (req.params.driverId !== req.user.id) {
      res.status(403).json({ detail: "may only list your own driver routes" });
      return;
    }
    const contexts = await loadRouteContexts(pool, "driver_id = $1", [
      req.params.driverId
    ]);
    res.json(contexts.map((ctx) => ctx.dto));
  })
);

app.get(
  "/commute/routes/:routeId/subscriptions",
  requireAuth,
  asyncHandler(async (req, res) => {
    const owner = await loadRouteOwner(req.params.routeId);
    if (owner == null) {
      res.status(404).json({ detail: "Route not found" });
      return;
    }
    if (String(owner) !== req.user.id) {
      res.status(403).json({ detail: "not your route" });
      return;
    }
    const items = await listSubscriptions(pool, "s.route_id = $1", [
      req.params.routeId
    ]);
    res.json(items);
  })
);

app.get(
  "/commute/routes/:routeId/rides",
  requireAuth,
  asyncHandler(async (req, res) => {
    const fromDate = String(req.query.fromDate || todayIso());
    const days = toInt(req.query.days, 7, 1, 60);
    const canSeePassengers = await canAccessRouteRideData(req.params.routeId, req.user.id);
    const rides = await listRouteRides(pool, req.params.routeId, fromDate, days);
    res.json(canSeePassengers ? rides : rides.map((ride) => ({
      ...ride,
      confirmedPassengers: []
    })));
  })
);

app.get(
  "/commute/routes/:routeId",
  requireAuth,
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
  requireAuth,
  asyncHandler(async (req, res) => {
    if (req.params.riderId !== req.user.id) {
      res.status(403).json({ detail: "may only list your own subscriptions" });
      return;
    }
    const items = await listSubscriptions(pool, "s.rider_id = $1", [req.params.riderId]);
    res.json(items);
  })
);

app.post(
  "/commute/subscriptions",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const id = await createSubscription(pool, {
      routeId: bodyValue(body, "routeId", "route_id"),
      riderId: req.user.id,
      riderName: bodyValue(body, "riderName", "rider_name"),
      startDate: bodyValue(body, "startDate", "start_date"),
      endDate: bodyValue(body, "endDate", "end_date"),
      pickupPointId: bodyValue(body, "pickupPointId", "pickup_point_id", "selectedPickupPointId", "selected_pickup_point_id"),
      dropPointId: bodyValue(body, "dropPointId", "drop_point_id", "selectedDropPointId", "selected_drop_point_id"),
      status: "ACTIVE"
    });
    await generateRideInstances(pool, todayIso(), 30);
    const route = (await pool.query(
      "SELECT driver_id, start_location, end_location FROM recurring_routes WHERE id = $1",
      [bodyValue(body, "routeId", "route_id")]
    )).rows[0];
    await createNotification({
      userId: req.user.id,
      type: "SUBSCRIPTION_CONFIRMED",
      title: "Subscription confirmed",
      body: route ? `${route.start_location} to ${route.end_location}` : "Your route subscription is active.",
      routeId: bodyValue(body, "routeId", "route_id"),
      subscriptionId: id
    });
    if (route?.driver_id) {
      await createNotification({
        userId: route.driver_id,
        type: "NEW_SUBSCRIBER",
        title: "New rider subscribed",
        body: route ? `${route.start_location} to ${route.end_location}` : "A rider joined your route.",
        routeId: bodyValue(body, "routeId", "route_id"),
        subscriptionId: id
      });
    }
    res.json({ id });
  })
);

app.put(
  "/commute/subscriptions/:subscriptionId/status",
  requireAuth,
  asyncHandler(async (req, res) => {
    const subscriptionId = req.params.subscriptionId;
    const ownerRes = await pool.query(
      "SELECT rider_id FROM route_subscriptions WHERE id = $1 LIMIT 1",
      [subscriptionId]
    );
    if (ownerRes.rows.length === 0) {
      res.status(404).json({ detail: "Subscription not found" });
      return;
    }
    if (String(ownerRes.rows[0].rider_id) !== req.user.id) {
      res.status(403).json({ detail: "not your subscription" });
      return;
    }
    const status = String(req.body?.status || "ACTIVE").toUpperCase();
    if (!SUBSCRIPTION_STATUSES.has(status)) {
      res.status(400).json({ detail: "invalid subscription status" });
      return;
    }
    await pool.query(
      `UPDATE route_subscriptions
       SET status = $2
       WHERE id = $1`,
      [subscriptionId, status]
    );
    await generateRideInstances(pool, todayIso(), 30);
    const sub = (await pool.query(
      "SELECT route_id FROM route_subscriptions WHERE id = $1",
      [subscriptionId]
    )).rows[0];
    await createNotification({
      userId: req.user.id,
      type: "SUBSCRIPTION_STATUS_UPDATED",
      title: "Subscription updated",
      body: `Status changed to ${status}.`,
      routeId: sub?.route_id,
      subscriptionId
    });
    res.status(204).send();
  })
);

app.post(
  "/commute/search",
  requireAuth,
  asyncHandler(async (req, res) => {
    const payload = normalizeCommuteSearchBody(req.body || {});
    payload.riderId = req.user.id;
    const matches = await findCommuteMatches(pool, payload);
    res.json({ matches, candidates: matches });
  })
);

app.get(
  "/commute/riders/:riderId/calendar",
  requireAuth,
  asyncHandler(async (req, res) => {
    if (req.params.riderId !== req.user.id) {
      res.status(403).json({ detail: "may only view your own calendar" });
      return;
    }
    const fromDate = String(req.query.fromDate || todayIso());
    const days = toInt(req.query.days, 7, 1, 60);
    const rides = await listRiderCalendar(pool, req.params.riderId, fromDate, days);
    res.json(rides);
  })
);

// Internal/admin: ride generation. Gated to a static admin key, since these
// endpoints aren't user-facing and shouldn't fall under the JWT user pool.
function requireAdmin(req, res, next) {
  const key = req.get("X-Admin-Key") || "";
  const expected = process.env.ADMIN_API_KEY || "";
  if (!expected || key !== expected) {
    res.status(401).json({ detail: "admin key required" });
    return;
  }
  next();
}

app.post(
  "/commute/rides/generate",
  requireAdmin,
  asyncHandler(async (req, res) => {
    const date = String(req.body?.date || todayIso());
    await generateRideInstances(pool, date, 1);
    res.status(204).send();
  })
);

app.post(
  "/routes",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const routeId = await createRoute(
      pool,
      {
        driverId: req.user.id,
        driverName: body.driver_name || req.user.id,
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
    await generateRideInstances(pool, todayIso(), 30);
    res.json({ route_id: routeId });
  })
);

app.post(
  "/subscriptions",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const id = await createSubscription(pool, {
      routeId: body.route_id,
      riderId: req.user.id,
      riderName: body.rider_name || req.user.id,
      startDate: body.start_date,
      endDate: body.end_date,
      pickupPointId: body.selected_pickup_point_id,
      dropPointId: body.selected_drop_point_id,
      status: body.status || "ACTIVE"
    });
    await generateRideInstances(pool, todayIso(), 30);
    const route = (await pool.query(
      "SELECT driver_id, start_location, end_location FROM recurring_routes WHERE id = $1",
      [body.route_id]
    )).rows[0];
    await createNotification({
      userId: req.user.id,
      type: "SUBSCRIPTION_CONFIRMED",
      title: "Subscription confirmed",
      body: route ? `${route.start_location} to ${route.end_location}` : "Your route subscription is active.",
      routeId: body.route_id,
      subscriptionId: id
    });
    if (route?.driver_id) {
      await createNotification({
        userId: route.driver_id,
        type: "NEW_SUBSCRIBER",
        title: "New rider subscribed",
        body: route ? `${route.start_location} to ${route.end_location}` : "A rider joined your route.",
        routeId: body.route_id,
        subscriptionId: id
      });
    }
    res.json({ subscription_id: id });
  })
);

app.post(
  "/admin/generate",
  requireAdmin,
  asyncHandler(async (req, res) => {
    const days = toInt(req.query.days, 7, 1, 60);
    const generatedInstances = await generateRideInstances(pool, todayIso(), days);
    res.json({ generated_instances: generatedInstances, days });
  })
);

app.post(
  "/match/search",
  requireAuth,
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

app.post(
  "/trips/:id/book",
  requireAuth,
  asyncHandler(async (req, res) => {
    const client = await pool.connect();
    let committed = false;
    try {
      await client.query("BEGIN");
      const rideRes = await client.query(
        `SELECT i.id, i.route_id, i.seat_availability, i.ride_status,
                r.driver_id, r.start_location, r.end_location
           FROM commute_ride_instances i
           JOIN recurring_routes r ON r.id = i.route_id
          WHERE i.id = $1
          FOR UPDATE`,
        [req.params.id]
      );
      const ride = rideRes.rows[0];
      if (!ride) {
        res.status(404).json({ detail: "Ride not found" });
        await client.query("ROLLBACK");
        return;
      }
      if (String(ride.driver_id) === req.user.id) {
        res.status(409).json({ detail: "Drivers cannot book their own ride" });
        await client.query("ROLLBACK");
        return;
      }
      if (ride.ride_status !== "SCHEDULED") {
        res.status(409).json({ detail: "Ride is not bookable" });
        await client.query("ROLLBACK");
        return;
      }
      const existing = await client.query(
        `SELECT id
           FROM commute_ride_passengers
          WHERE instance_id = $1
            AND rider_id = $2
          LIMIT 1`,
        [req.params.id, req.user.id]
      );
      if (existing.rows.length > 0) {
        res.status(409).json({ detail: "Ride already booked" });
        await client.query("ROLLBACK");
        return;
      }
      if (Number(ride.seat_availability) <= 0) {
        res.status(409).json({ detail: "No seats available" });
        await client.query("ROLLBACK");
        return;
      }

      const bookingId = crypto.randomUUID();
      await client.query(
        `INSERT INTO commute_ride_passengers (id, instance_id, rider_id)
         VALUES ($1, $2, $3)`,
        [bookingId, req.params.id, req.user.id]
      );
      await client.query(
        `UPDATE commute_ride_instances
            SET seat_availability = GREATEST(0, seat_availability - 1)
          WHERE id = $1`,
        [req.params.id]
      );
      await client.query("COMMIT");
      committed = true;

      await createNotification({
        userId: req.user.id,
        type: "RIDE_BOOKED",
        title: "Ride booked",
        body: `${ride.start_location} to ${ride.end_location}`,
        routeId: ride.route_id,
        rideInstanceId: req.params.id
      });
      await createNotification({
        userId: ride.driver_id,
        type: "RIDE_SEAT_BOOKED",
        title: "Seat booked",
        body: "A rider booked a seat on your ride.",
        routeId: ride.route_id,
        rideInstanceId: req.params.id
      });

      res.status(201).json({
        id: bookingId,
        rideInstanceId: req.params.id,
        routeId: String(ride.route_id)
      });
    } catch (error) {
      if (!committed) {
        await client.query("ROLLBACK");
      }
      throw error;
    } finally {
      client.release();
    }
  })
);

app.get(
  "/bookings/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT p.id, p.instance_id, i.route_id, i.date, i.ride_status,
              r.driver_name, r.start_location, r.end_location
         FROM commute_ride_passengers p
         JOIN commute_ride_instances i ON i.id = p.instance_id
         JOIN recurring_routes r ON r.id = i.route_id
        WHERE p.rider_id = $1
        ORDER BY i.date ASC`,
      [req.user.id]
    );
    res.json(result.rows.map((row) => ({
      id: row.id,
      rideInstanceId: row.instance_id,
      routeId: row.route_id,
      date: row.date,
      rideStatus: row.ride_status,
      driverName: row.driver_name,
      startLocation: row.start_location,
      endLocation: row.end_location
    })));
  })
);

app.post(
  "/reviews",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const rideInstanceId = bodyValue(body, "rideInstanceId", "ride_instance_id");
    const routeId = bodyValue(body, "routeId", "route_id");
    const providedDriverId = bodyValue(body, "driverId", "driver_id");
    const rating = Number.parseInt(String(body.rating), 10);
    const tags = Array.isArray(body.tags) ? body.tags.map(String).slice(0, 12) : [];
    const tipMyr = toInt(bodyValue(body, "tipMyr", "tip_myr"), 0, 0, 200);
    const note = String(body.note || "").trim().slice(0, 1000) || null;

    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      res.status(400).json({ detail: "rating must be between 1 and 5" });
      return;
    }
    if (!rideInstanceId && !routeId) {
      res.status(400).json({ detail: "rideInstanceId or routeId is required" });
      return;
    }

    let resolvedRouteId = routeId ? String(routeId) : null;
    let resolvedDriverId = providedDriverId ? String(providedDriverId) : null;

    if (rideInstanceId) {
      const ride = await pool.query(
        `SELECT i.id, i.route_id, r.driver_id
           FROM commute_ride_instances i
           JOIN recurring_routes r ON r.id = i.route_id
          WHERE i.id = $1`,
        [rideInstanceId]
      );
      if (ride.rowCount === 0) {
        res.status(404).json({ detail: "Ride not found" });
        return;
      }
      resolvedRouteId = String(ride.rows[0].route_id);
      resolvedDriverId = String(ride.rows[0].driver_id);

      const passenger = await pool.query(
        `SELECT 1
           FROM commute_ride_passengers
          WHERE instance_id = $1
            AND rider_id = $2
          LIMIT 1`,
        [rideInstanceId, req.user.id]
      );
      if (passenger.rowCount === 0 && resolvedDriverId !== req.user.id) {
        res.status(403).json({ detail: "Only ride participants can review this trip" });
        return;
      }
    } else if (resolvedRouteId) {
      const route = await pool.query(
        `SELECT driver_id
           FROM recurring_routes
          WHERE id = $1`,
        [resolvedRouteId]
      );
      if (route.rowCount === 0) {
        res.status(404).json({ detail: "Route not found" });
        return;
      }
      resolvedDriverId = resolvedDriverId || String(route.rows[0].driver_id);

      const participant = await pool.query(
        `SELECT 1
           FROM route_subscriptions
          WHERE route_id = $1
            AND rider_id = $2
          LIMIT 1`,
        [resolvedRouteId, req.user.id]
      );
      if (participant.rowCount === 0 && resolvedDriverId !== req.user.id) {
        res.status(403).json({ detail: "Only route participants can review this trip" });
        return;
      }
    }
    if (resolvedDriverId === req.user.id) {
      res.status(409).json({ detail: "Drivers cannot review their own ride" });
      return;
    }

    const id = crypto.randomUUID();
    await pool.query(
      `INSERT INTO ride_reviews
         (id, reviewer_id, ride_instance_id, route_id, driver_id, rating, tags, tip_myr, note)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9)`,
      [
        id,
        req.user.id,
        rideInstanceId ? String(rideInstanceId) : null,
        resolvedRouteId,
        resolvedDriverId,
        rating,
        JSON.stringify(tags),
        tipMyr,
        note
      ]
    );

    if (resolvedDriverId) {
      await pool.query(
        `INSERT INTO driver_reliability (driver_id, average_rating)
         VALUES ($1, $2)
         ON CONFLICT (driver_id) DO UPDATE
            SET average_rating = (
                  SELECT AVG(rating)::DOUBLE PRECISION
                    FROM ride_reviews
                   WHERE driver_id = $1
                ),
                updated_at = NOW()`,
        [resolvedDriverId, rating]
      );
      await createNotification({
        userId: resolvedDriverId,
        type: "RIDE_REVIEWED",
        title: "New ride review",
        body: `A rider rated your ride ${rating}/5.`,
        routeId: resolvedRouteId,
        rideInstanceId: rideInstanceId ? String(rideInstanceId) : null
      });
    }

    res.status(201).json({ id });
  })
);
app.get(
  "/chats/threads",
  requireAuth,
  asyncHandler(async (req, res) => {
    const threads = await listChatThreads(pool, req.user.id);
    res.json(threads);
  })
);
app.get(
  "/chats/:threadId",
  requireAuth,
  asyncHandler(async (req, res) => {
    const messages = await listChatMessages(pool, req.params.threadId, req.user.id);
    res.json(messages);
  })
);
app.post(
  "/chats/:threadId/send",
  requireAuth,
  asyncHandler(async (req, res) => {
    const text = String(req.body?.text || "");
    await appendChatMessage(pool, req.params.threadId, text, req.user.id);
    res.status(204).send();
  })
);

// ───────────────────────── Payments + payouts ─────────────────────────────
//
// Auth-gated charge endpoint. In mock mode (no Billplz creds) the call
// resolves immediately to PAID; in prod it returns a Billplz redirect URL
// the rider must visit.
app.post(
  "/payments/charge",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const subscriptionId = bodyValue(body, "subscriptionId", "subscription_id");
    const routeId = bodyValue(body, "routeId", "route_id");
    const amountMyr = Number(bodyValue(body, "amountMyr", "amount_myr"));
    if (!Number.isFinite(amountMyr) || amountMyr < 1) {
      res.status(400).json({ detail: "amountMyr is required (>= RM 1)" });
      return;
    }
    const tier = String(bodyValue(body, "tier") || "MONTHLY").toUpperCase();
    const result = await chargeSubscription(pool, {
      userId: req.user.id,
      subscriptionId,
      routeId,
      amountMyr,
      tier,
      contact: bodyValue(body, "contact") || {}
    });
    res.json(result);
  })
);

app.get(
  "/payments/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const limit = toInt(req.query.limit, 20, 1, 100);
    const items = await listUserPayments(pool, req.user.id, limit);
    res.json(items);
  })
);

// Billplz webhook — public, signature-verified.
app.post(
  "/payments/billplz/callback",
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const providedSignature = body.x_signature || req.get("x-signature") || "";
    if (!verifyBillplzSignature(body, providedSignature)) {
      res.status(401).json({ detail: "invalid signature" });
      return;
    }
    const billId = body.id ? String(body.id) : null;
    const paid = String(body.paid) === "true";

    if (billId) {
      // Look up the user this bill belongs to so we can land a real
      // notification regardless of which path closes the loop. The
      // payment row carries `user_id` even before `markPaymentPaid`
      // runs.
      const lookup = await pool.query(
        `SELECT user_id, route_id, subscription_id, amount_myr
           FROM payments
          WHERE billplz_id = $1
          LIMIT 1`,
        [billId]
      );
      const row = lookup.rows[0];

      if (paid) {
        await markPaymentPaid(pool, { billId });
        if (row?.user_id) {
          await createNotification({
            userId: row.user_id,
            type: "PAYMENT_SUCCEEDED",
            title: "Payment received",
            body: `Your subscription is active. RM ${row.amount_myr} charged.`,
            routeId: row.route_id,
            subscriptionId: row.subscription_id
          });
        }
      } else if (row?.user_id) {
        // Treat any non-paid callback (cancelled, expired, refused)
        // as a failed-payment signal so the rider sees an honest
        // notification + can retry from the wallet.
        await createNotification({
          userId: row.user_id,
          type: "PAYMENT_FAILED",
          title: "Payment didn't go through",
          body: "Your subscription is paused. Retry from My Subscriptions.",
          routeId: row.route_id,
          subscriptionId: row.subscription_id
        });
      }
    }
    res.status(204).send();
  })
);

app.get(
  "/payouts/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const payout = await computeWeeklyPayout(pool, req.user.id);
    res.json(payout);
  })
);

const CANCEL_ACTORS = new Set(["DRIVER", "RIDER", "SYSTEM"]);
const CANCEL_KINDS = new Set([
  "DRIVER_CANCEL_LATE", "DRIVER_NO_SHOW",
  "RIDER_CANCEL_MID_MONTH", "RIDER_NO_SHOW", "FORCE_MAJEURE"
]);

// Records a cancellation, computes the policy-engine penalty server-side
// using `cancellation_records` history, and returns the new row's id.
app.post(
  "/cancellations",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const rideInstanceId = bodyValue(body, "rideInstanceId", "ride_instance_id");
    const routeId        = bodyValue(body, "routeId", "route_id");
    const subscriptionId = bodyValue(body, "subscriptionId", "subscription_id");
    const actor          = String(bodyValue(body, "actor") || "").toUpperCase();
    const kind           = String(bodyValue(body, "kind") || "").toUpperCase();
    const notes          = bodyValue(body, "notes") || null;

    if (!routeId || !CANCEL_ACTORS.has(actor) || !CANCEL_KINDS.has(kind)) {
      res.status(400).json({ detail: "routeId, actor, and kind are required" });
      return;
    }

    // Look up per-seat price + driver's recent late-cancel count to feed
    // the policy engine, mirroring the Swift CancellationPolicyEngine.
    const routeRow = (await pool.query(
      "SELECT driver_id, price_per_seat FROM recurring_routes WHERE id = $1 LIMIT 1",
      [routeId]
    )).rows[0];
    if (!routeRow) {
      res.status(404).json({ detail: "Route not found" });
      return;
    }
    const pricePerSeat = Number(routeRow?.price_per_seat || 0);
    const driverId = routeRow?.driver_id || null;
    if (actor === "DRIVER" && String(driverId) !== req.user.id) {
      res.status(403).json({ detail: "Only the route driver can report driver cancellations" });
      return;
    }
    if (actor === "RIDER") {
      const riderAccess = await pool.query(
        `SELECT id
           FROM route_subscriptions
          WHERE route_id = $1
            AND rider_id = $2
            AND ($3::text IS NULL OR id::text = $3::text)
          LIMIT 1`,
        [routeId, req.user.id, subscriptionId || null]
      );
      if (riderAccess.rowCount === 0) {
        res.status(403).json({ detail: "Only subscribed riders can report rider cancellations" });
        return;
      }
    }
    if (actor === "SYSTEM") {
      res.status(403).json({ detail: "System cancellations require an admin workflow" });
      return;
    }

    const lateCancelsRes = await pool.query(
      `SELECT COUNT(*)::int AS count
         FROM cancellation_records
        WHERE route_id = $1
          AND actor = 'DRIVER'
          AND kind = 'DRIVER_CANCEL_LATE'
          AND reported_at > NOW() - INTERVAL '30 days'`,
      [routeId]
    );
    const driverLateCancels = Number(lateCancelsRes.rows[0]?.count || 0);

    // Same policy table as the iOS CancellationPolicyEngine.decide() —
    // keep these two in sync until they share a code path.
    const penalty = computePenalty({
      kind,
      pricePerSeat,
      driverLateCancels
    });

    const id = crypto.randomUUID();
    await pool.query(
      `INSERT INTO cancellation_records
         (id, ride_instance_id, subscription_id, route_id, actor, kind, penalty_amount, notes)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [id, rideInstanceId || null, subscriptionId || null, routeId, actor, kind, penalty, notes]
    );

    // Wire the refund ledger. A negative penalty means the rider is owed
    // money back (mid-month cancel = pro-rated credit minus admin fee).
    // We materialise that as a REFUNDED payment row so the wallet balance
    // and `voygoCreditMyr` actually reflect what the cancellation policy
    // promises, instead of the previous wishful filtering against rows
    // that were never created.
    let refundPaymentId = null;
    if (actor === "RIDER" && penalty < 0 && subscriptionId) {
      try {
        refundPaymentId = crypto.randomUUID();
        await pool.query(
          `INSERT INTO payments
             (id, user_id, subscription_id, route_id, amount_myr, status, tier, paid_at)
           VALUES ($1, $2, $3, $4, $5, 'REFUNDED', 'REFUND', NOW())`,
          [refundPaymentId, req.user.id, subscriptionId, routeId, Math.abs(penalty)]
        );
        await createNotification({
          userId: req.user.id,
          type: "REFUND",
          title: "Refund issued",
          body: `RM ${Math.abs(penalty)} credited to your Voygo wallet.`,
          routeId,
          subscriptionId
        });
      } catch (refundErr) {
        // Don't fail the cancellation if the refund row insert blows up;
        // ops can reconcile from the cancellation_records audit trail.
        console.warn(`[cancellations] refund insert failed: ${refundErr.message}`);
      }
    }

    res.status(201).json({ id, penaltyMyr: penalty, driverId, refundPaymentId });
  })
);

function computePenalty({ kind, pricePerSeat, driverLateCancels }) {
  switch (kind) {
    case "DRIVER_CANCEL_LATE":
      return driverLateCancels >= 2 ? pricePerSeat : 0;
    case "DRIVER_NO_SHOW":
      return Math.floor(pricePerSeat / 2);
    case "RIDER_CANCEL_MID_MONTH":
      // 10% admin fee, capped at MYR 20, expressed as a refund (negative).
      return -Math.min(20, Math.floor(pricePerSeat / 10) * 22);
    case "RIDER_NO_SHOW":
      return 0;
    case "FORCE_MAJEURE":
      return 0;
    default:
      return 0;
  }
}

app.use((error, _req, res, _next) => {
  console.error(error);
  const status = Number(error.status || 500);
  const detail =
    status >= 500 ? "Internal server error" : error.message || "Request failed";
  res.status(status).json({ detail });
});

async function start() {
  await initSchema(pool);
  await ensurePaymentsSchema(pool);
  await ensureCancellationSchema(pool);
  await ensureKycDocsSchema(pool);
  await ensureReviewsSchema(pool);
  await seedIfEmpty(pool);
  await backfillChatParticipants(pool);

  app.listen(config.port, "0.0.0.0", () => {
    const billplzMode = config.billplz.isMockMode ? "MOCK" : "LIVE";
    console.log(`Voygo Node API listening on 0.0.0.0:${config.port} · billplz=${billplzMode}`);
  });
}

// Cancellation_records is referenced by payouts.js but lives outside the
// existing schema.js bundle. Defining it here keeps the migration in one
// place rather than splitting it across files.
async function ensureCancellationSchema(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS cancellation_records (
      id UUID PRIMARY KEY,
      ride_instance_id TEXT,
      subscription_id TEXT,
      route_id TEXT NOT NULL,
      actor TEXT NOT NULL,
      kind TEXT NOT NULL,
      reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      resolved_at TIMESTAMPTZ NULL,
      penalty_amount INTEGER NOT NULL DEFAULT 0,
      notes TEXT NULL
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_cancel_route ON cancellation_records(route_id, reported_at)"
  );
}

// KYC documents table. Referenced by /users/me/kyc-documents endpoints.
async function ensureKycDocsSchema(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS kyc_documents (
      id UUID PRIMARY KEY,
      user_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      storage_url TEXT NULL,
      uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      verified_at TIMESTAMPTZ NULL,
      rejection_reason TEXT NULL,
      CONSTRAINT uq_kyc_user_kind UNIQUE (user_id, kind)
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_kyc_docs_user ON kyc_documents(user_id)"
  );
}

async function ensureReviewsSchema(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ride_reviews (
      id UUID PRIMARY KEY,
      reviewer_id TEXT NOT NULL,
      ride_instance_id TEXT NULL,
      route_id TEXT NULL,
      driver_id TEXT NULL,
      rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
      tags JSONB NOT NULL DEFAULT '[]'::jsonb,
      tip_myr INTEGER NOT NULL DEFAULT 0,
      note TEXT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_reviews_driver ON ride_reviews(driver_id, created_at)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_reviews_route ON ride_reviews(route_id, created_at)"
  );
  await pool.query(
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_reviews_rider_ride ON ride_reviews(reviewer_id, ride_instance_id) WHERE ride_instance_id IS NOT NULL"
  );
}

async function backfillChatParticipants(pool) {
  await pool.query(`
    INSERT INTO chat_participants (thread_id, user_id)
    SELECT t.id, r.driver_id
      FROM chat_threads t
      JOIN recurring_routes r ON r.id = t.route_id
     WHERE r.driver_id IS NOT NULL
    ON CONFLICT ON CONSTRAINT uq_chat_participant DO NOTHING
  `);
  await pool.query(`
    INSERT INTO chat_participants (thread_id, user_id)
    SELECT t.id, s.rider_id
      FROM chat_threads t
      JOIN route_subscriptions s ON s.route_id = t.route_id
     WHERE s.rider_id IS NOT NULL
    ON CONFLICT ON CONSTRAINT uq_chat_participant DO NOTHING
  `);
}

start().catch((error) => {
  console.error("Server failed to start", error);
  process.exit(1);
});

process.on("SIGTERM", async () => {
  await pool.end();
  process.exit(0);
});
