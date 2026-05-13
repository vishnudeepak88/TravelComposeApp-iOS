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
const { sendSms, smsConfigured } = require("./sms");
const { sendOtpEmail, emailConfigured, activeProvider, verifyEmailTransport, emailDiagnostics } = require("./email");
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
  markChatThreadRead,
  maskPhone,
  publicDriverName,
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
  rateLimitAuth,
  rateLimitOtpByPhone,
  rateLimitWrite,
  rateLimitSafety,
  rateLimitLocation,
  rateLimitAiSupport,
  rateLimitTelemetry
} = require("./middleware");
const {
  buildKycObjectKey,
  kycObjectStorageConfigured,
  uploadKycObject
} = require("./objectStorage");

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

// CORS allowlist. The iOS app doesn't need CORS (URLSession doesn't
// enforce same-origin), but web browsers do. We allowlist the public
// website + the voygo:// deep-link scheme. Any other origin gets no
// `Access-Control-Allow-Origin` header so a malicious site can't
// proxy a logged-in user's session.
//
// `CORS_EXTRA_ORIGINS` is a comma-separated env override for ops
// (e.g. adding a preview branch domain temporarily). Empty is the
// safe default.
const corsAllowlist = new Set([
  "https://voygo.app",
  "https://www.voygo.app",
  "voygo://",
  ...(String(process.env.CORS_EXTRA_ORIGINS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean))
]);
app.use(
  cors({
    origin(origin, cb) {
      // No-origin requests (curl, server-to-server, native apps) are
      // allowed — they don't trigger CORS in the first place. We only
      // reject browser cross-origin requests from non-allowlisted
      // sites.
      if (!origin) return cb(null, true);
      if (corsAllowlist.has(origin)) return cb(null, true);
      cb(null, false);
    },
    credentials: false
  })
);
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

// Masks an E.164 phone for any log line. Keep the country code and
// last two digits — enough to correlate with a user report when ops
// is grepping logs — but strip the middle so dump-scraping a leaked
// log file doesn't produce a clean dialable list of every user.
function maskPhoneForLog(phone) {
  if (!phone) return "(none)";
  const s = String(phone);
  const digits = s.replace(/\D+/g, "");
  if (digits.length < 4) return "•••";
  const lastTwo = digits.slice(-2);
  const cc = s.startsWith("+") ? s.slice(1, 3) : digits.slice(0, 2);
  return `+${cc}••••${lastTwo}`;
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
    officeLng: bodyValue(body, "officeLng", "office_lng"),
    // New filters: rider's needed days (object form) + budget cap.
    // Both optional — when omitted, repository.findCommuteMatches
    // skips the filter and returns everything in the time window.
    daysOfWeek: bodyValue(body, "daysOfWeek", "days_of_week"),
    maxPriceMyr: bodyValue(body, "maxPriceMyr", "max_price_myr")
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
  // Two-layer rate limit: per-IP (`rateLimitAuth`, 5 per minute) blocks
  // a single client hammering, per-phone (`rateLimitOtpByPhone`,
  // 1/60s, 5/hour) blocks a residential-proxy attacker who rotates
  // IPs to enumerate phones or pump our Twilio bill. Both must pass.
  rateLimitAuth,
  rateLimitOtpByPhone,
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
    // OTP delivery, in priority order:
    //   1. SMS configured       → send via Twilio (any deploy tier).
    //   2. Email configured     → send via SMTP (Gmail) to OTP_TO_EMAIL.
    //                              Useful for staging when Twilio isn't
    //                              wired but the team has Gmail.
    //   3. Production without
    //      either               → 503 (refuse the silent no-op).
    //   4. Dev/staging without
    //      either               → log + echo `devCode` so testers can
    //                              still sign in.
    // Parallel delivery: when both SMS and email are configured we
    // don't want one slow provider to compound the other's latency.
    // Each call has its own internal timeout (sms.js: 10s; email.js:
    // 8s outer cap + 3s connect/greeting), so the OTP endpoint can
    // never block more than the slower of the two ~10s.
    const deliveries = [];
    if (smsConfigured()) {
      deliveries.push(
        sendSms({
          to: phone,
          body: `Your Voygo verification code is ${code}. It expires in 5 minutes.`
        }).then((r) => ({ channel: "sms", ...r }))
      );
    }
    if (emailConfigured()) {
      deliveries.push(
        sendOtpEmail({ phone, code, expiresAt: expiresAt.toISOString() })
          .then((r) => ({ channel: "email", ...r }))
      );
    }
    const results = await Promise.all(deliveries);
    const smsOk   = results.some((r) => r.channel === "sms"   && r.ok);
    const emailOk = results.some((r) => r.channel === "email" && r.ok);
    const maskedPhone = maskPhoneForLog(phone);
    for (const r of results) {
      if (!r.ok) {
        console.warn(`[auth] ${r.channel} send failed for ${maskedPhone}: ${r.reason}`);
      } else if (r.channel === "email") {
        // OTP_TO_EMAIL is fine to log — it's a single ops mailbox not
        // a per-user secret. Phone is masked.
        console.log(`[auth] OTP for ${maskedPhone} emailed to ${process.env.OTP_TO_EMAIL}`);
      }
    }
    // No delivery channel succeeded.
    if (!smsOk && !emailOk) {
      if (config.isProduction) {
        // Production is required to have at least SMS configured (config.js
        // guards block boot otherwise). Reaching here means SMS errored at
        // send time and email isn't a backup. Surface the failure honestly.
        console.error(`[auth] all OTP channels failed for ${maskedPhone} in production`);
        res.status(502).json({ detail: "otp_delivery_failed" });
        return;
      }
      // Local dev only: emit the devCode in the response (line 270
      // below). We never log the OTP code itself — anyone with read
      // access to staging logs would otherwise have a stable test
      // bypass for every phone.
      if (!config.isProduction) {
        console.log(`[auth] OTP delivery channels unconfigured for ${maskedPhone} — devCode returned in response`);
      }
    }
    const response = { sent: true, expiresAt: expiresAt.toISOString() };
    // Echo `devCode` only when no real delivery happened AND we're not
    // in production. Covers local dev and staging-without-providers.
    // Once email or SMS is configured, the code stops being echoed.
    if (!smsOk && !emailOk && !config.isProduction) {
      response.devCode = code;
    }
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
       ON CONFLICT (phone) DO UPDATE
          SET updated_at = NOW(),
              deleted_at = NULL
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
      `SELECT id, phone, display_name, kyc_status,
              plate_number, car_color, car_model,
              average_rating, rating_count, created_at, deleted_at
         FROM users
        WHERE id = $1`,
      [req.user.id]
    );
    const user = userRes.rows[0];
    if (!user) {
      res.status(404).json({ detail: "user not found" });
      return;
    }
    // PDPA: a deleted account stays in the DB during the 30-day
    // grace window so the user can recover via re-sign-in. While
    // deleted, /auth/me returns 410 Gone — iOS uses this to clear
    // session and bounce to the auth screen.
    if (user.deleted_at) {
      res.status(410).json({
        detail: "account_deleted",
        deletedAt: new Date(user.deleted_at).toISOString()
      });
      return;
    }
    res.json({
      id: String(user.id),
      phone: user.phone,
      displayName: user.display_name || "",
      kycStatus: user.kyc_status || "NOT_STARTED",
      // Vehicle identity belongs to the driver, not per-route. iOS reads
      // these from the profile and renders the "Vehicle" tile in
      // settings; missing fields show an empty CTA until the driver
      // fills them in.
      plateNumber: user.plate_number || null,
      carColor: user.car_color || null,
      carModel: user.car_model || null,
      // Real rating + count. Both null/0 until the reviews fan-out
      // populates them — iOS shows "New rider" in that case. We
      // never invent a default like the old hardcoded 5.0; the lie
      // was visible to every user looking at their own profile.
      averageRating: user.average_rating != null ? Number(user.average_rating) : null,
      ratingCount: Number(user.rating_count || 0),
      // ISO-8601 created_at for the "Member since" line on Profile.
      memberSince: user.created_at ? new Date(user.created_at).toISOString() : null
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

// Driver vehicle identity — the single source of truth for plate +
// colour + model. A bad actor cannot list one plate on a route and
// arrive in another car because every route DTO sources vehicle from
// here at read time (see loadRouteContexts in repository.js).
//
// Hardening:
// 1. KYC-gated — only APPROVED drivers can claim a plate. Stops a
//    fresh signup from grabbing a high-trust plate ("PEN 1234") and
//    impersonating an existing driver on the search results.
// 2. Plate uniqueness — partial unique index in schema.js ensures two
//    drivers can't simultaneously claim the same normalised plate.
//    409 on conflict.
// 3. Audit trail — every write lands a row in user_vehicle_history so
//    a driver who swaps plates between rides leaves a discoverable
//    trail when ops investigates a rider report.
// 4. Refuse-to-clear when there's an active route — prevents a driver
//    from blanking their identity right before a problem ride.
app.put(
  "/users/me/vehicle",
  requireAuth,
  requireKyc,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const plateRaw = body.plateNumber ?? body.plate_number ?? "";
    const colorRaw = body.carColor ?? body.car_color ?? "";
    const modelRaw = body.carModel ?? body.car_model ?? "";

    // Trim + length-cap so a malicious client can't push 1MB of text
    // into the column. 32 chars holds even the longest Malaysian
    // plate ("WMM 1234 P" is 10), 24 covers "Pearl White Metallic",
    // 64 covers most "Toyota Vios 1.5 G AT".
    const plate = String(plateRaw).trim().slice(0, 32);
    const color = String(colorRaw).trim().slice(0, 24);
    const model = String(modelRaw).trim().slice(0, 64);

    // Refuse to clear plate while any active route exists — the
    // rider-facing card needs a plate to be useful, and a "blank
    // plate driver" right before a dodgy ride is a classic dodge.
    if (!plate) {
      const activeRoutes = await pool.query(
        `SELECT 1 FROM recurring_routes
          WHERE driver_id = $1 AND active_status = TRUE LIMIT 1`,
        [req.user.id]
      );
      if (activeRoutes.rowCount > 0) {
        res.status(409).json({ detail: "plate_required_with_active_route" });
        return;
      }
    }

    try {
      await pool.query(
        `UPDATE users
            SET plate_number = $2,
                car_color    = $3,
                car_model    = $4,
                updated_at   = NOW()
          WHERE id = $1`,
        [req.user.id, plate || null, color || null, model || null]
      );
    } catch (err) {
      // 23505 = unique_violation. Surfaces when the partial unique
      // index on plate_number catches a duplicate claim.
      if (err && err.code === "23505") {
        res.status(409).json({ detail: "plate_already_claimed" });
        return;
      }
      throw err;
    }

    // Audit row — best-effort, never blocks the write response if it
    // somehow fails (e.g., the table got dropped mid-deploy). The
    // primary write already succeeded.
    pool.query(
      `INSERT INTO user_vehicle_history
         (id, user_id, plate_number, car_color, car_model, source_ip)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        crypto.randomUUID(),
        req.user.id,
        plate || null,
        color || null,
        model || null,
        // Trust X-Forwarded-For only when behind a known proxy (Render
        // sets it). Falls back to req.ip if header missing.
        String(req.get("x-forwarded-for") || req.ip || "").slice(0, 64)
      ]
    ).catch((e) => console.warn(`[vehicle-audit] ${e.message}`));

    res.json({
      plateNumber: plate || null,
      carColor: color || null,
      carModel: model || null
    });
  })
);

// ─── Privacy & Security ──────────────────────────────────────────────
//
// Backs the Profile → Privacy & Security screen. The previous version
// was a static brochure with no actual controls; this endpoint group
// powers the four real surfaces the user expects there:
//   1. /users/me/preferences  — push toggle, phone visibility
//   2. /users/me/blocks       — block list (list/add/remove)
//   3. /users/me/delete       — account deletion (PDPA + App Store 5.1.1(v))
//   4. /users/me/data-export  — PDPA Section 7 right of access
//
// All require auth + rate limit on writes; reads are uncapped beyond
// the global per-IP bucket.

app.get(
  "/users/me/preferences",
  requireAuth,
  asyncHandler(async (req, res) => {
    const r = await pool.query(
      "SELECT preferences FROM users WHERE id = $1",
      [req.user.id]
    );
    const prefs = r.rows[0]?.preferences || {};
    // Defaults — never invent a value the user didn't set, just
    // describe what the absence means.
    res.json({
      pushEnabled: prefs.pushEnabled !== false,             // default ON
      phoneVisibleToSubscribers: prefs.phoneVisibleToSubscribers !== false, // default ON
      biometricLock: prefs.biometricLock === true,          // default OFF
      marketingEmails: prefs.marketingEmails === true,      // default OFF (PDPA: opt-in)
      analyticsEnabled: prefs.analyticsEnabled !== false    // default ON, user can opt out
    });
  })
);

app.put(
  "/users/me/preferences",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    // Whitelist the keys we accept. A future toggle gets added to
    // this list explicitly — prevents a malicious client from
    // injecting arbitrary preference keys.
    const allowed = [
      "pushEnabled",
      "phoneVisibleToSubscribers",
      "biometricLock",
      "marketingEmails",
      "analyticsEnabled"
    ];
    const patch = {};
    for (const key of allowed) {
      if (typeof body[key] === "boolean") patch[key] = body[key];
    }
    if (Object.keys(patch).length === 0) {
      res.status(400).json({ detail: "no_valid_preferences" });
      return;
    }
    await pool.query(
      `UPDATE users
          SET preferences = COALESCE(preferences, '{}'::jsonb) || $2::jsonb,
              updated_at = NOW()
        WHERE id = $1`,
      [req.user.id, JSON.stringify(patch)]
    );
    res.status(204).send();
  })
);

// Block list — riders can block drivers (and vice versa) so that
// future search results filter them out. Bidirectional matching is
// enforced in findCommuteMatches via a NOT EXISTS subquery.
app.get(
  "/users/me/blocks",
  requireAuth,
  asyncHandler(async (req, res) => {
    const r = await pool.query(
      `SELECT b.blocked_id::text AS blocked_id,
              u.display_name AS display_name,
              b.reason, b.created_at
         FROM user_blocks b
         LEFT JOIN users u ON u.id::text = b.blocked_id
        WHERE b.blocker_id = $1
        ORDER BY b.created_at DESC
        LIMIT 200`,
      [req.user.id]
    );
    res.json(r.rows.map((row) => ({
      userId: String(row.blocked_id),
      displayName: row.display_name || "Voygo user",
      reason: row.reason || null,
      createdAt: row.created_at ? new Date(row.created_at).toISOString() : null
    })));
  })
);

app.post(
  "/users/me/blocks",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const targetId = String(body.userId || body.user_id || "").trim();
    const reason = String(body.reason || "").slice(0, 200) || null;
    if (!targetId) {
      res.status(400).json({ detail: "userId required" });
      return;
    }
    if (targetId === String(req.user.id)) {
      res.status(400).json({ detail: "cannot_block_self" });
      return;
    }
    // Cap at 200 to keep the table from growing unbounded per user
    // and limit the cost of the NOT EXISTS subquery on search.
    const count = (await pool.query(
      "SELECT COUNT(*)::int AS n FROM user_blocks WHERE blocker_id = $1",
      [req.user.id]
    )).rows[0]?.n || 0;
    if (count >= 200) {
      res.status(409).json({ detail: "block_list_full" });
      return;
    }
    await pool.query(
      `INSERT INTO user_blocks (blocker_id, blocked_id, reason)
         VALUES ($1, $2, $3)
         ON CONFLICT (blocker_id, blocked_id) DO UPDATE SET reason = EXCLUDED.reason`,
      [req.user.id, targetId, reason]
    );
    res.status(204).send();
  })
);

app.delete(
  "/users/me/blocks/:targetId",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    await pool.query(
      "DELETE FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2",
      [req.user.id, req.params.targetId]
    );
    res.status(204).send();
  })
);

// PDPA + App Store 5.1.1(v) — account deletion. Soft-deletes (sets
// deleted_at) so a misclick can be recovered within a 30-day grace
// window; ops job anonymises display_name + phone after the grace
// expires. Active subscriptions are PAUSED so the rider isn't
// charged on a cancelled account. The current JWT is invalidated by
// flagging deleted_at — requireAuth checks it on every request.
app.post(
  "/users/me/delete",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      // Pause everything the rider has running so we don't keep
      // charging or notifying a "deleted" account.
      await client.query(
        `UPDATE route_subscriptions SET status = 'PAUSED'
          WHERE rider_id = $1 AND status = 'ACTIVE'`,
        [req.user.id]
      );
      // If the user is also a driver, pause their routes so riders
      // don't see ghost routes from someone with no account.
      await client.query(
        `UPDATE recurring_routes SET active_status = FALSE, updated_at = NOW()
          WHERE driver_id = $1 AND active_status = TRUE`,
        [req.user.id]
      );
      await client.query(
        "UPDATE users SET deleted_at = NOW(), updated_at = NOW() WHERE id = $1",
        [req.user.id]
      );
      await client.query("COMMIT");
    } catch (err) {
      await client.query("ROLLBACK").catch(() => {});
      throw err;
    } finally {
      client.release();
    }
    res.json({
      scheduledFor: new Date(Date.now() + 30 * 86_400_000).toISOString(),
      message: "Account deletion scheduled. Sign in again within 30 days to cancel deletion. Paused subscriptions and routes stay paused until you resume them."
    });
  })
);

// PDPA Section 7 right of access — caller requests an email export
// of their data. For pilot we just notify ops; the actual file
// generation runs offline.
app.post(
  "/users/me/data-export",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    // Track who asked + when so ops can de-duplicate within 7 days.
    await pool.query(
      `INSERT INTO notifications (id, user_id, type, title, body, created_at)
         VALUES ($1, $2, 'DATA_EXPORT_REQUESTED', $3, $4, NOW())`,
      [
        crypto.randomUUID(),
        req.user.id,
        "Data export requested",
        "We'll email you a copy of your Voygo data within 7 working days."
      ]
    );
    res.json({
      acknowledged: true,
      slaDays: 7,
      message: "We'll email you a copy of your Voygo data within 7 working days."
    });
  })
);

// KYC self-submit. The previous implementation accepted any of
// NOT_STARTED / PENDING / APPROVED / REJECTED from the client, which
// let any authenticated user mark themselves APPROVED and unlock
// driver mode without ever being reviewed. This endpoint is now
// scoped to one transition only: the user attests they have uploaded
// their documents and is requesting review (status moves to PENDING).
//
// APPROVED / REJECTED are reachable only through the admin endpoints below.
app.post(
  "/users/me/kyc/submit",
  requireAuth,
  asyncHandler(async (req, res) => {
    // Soft-require at least one uploaded document before flipping to
    // PENDING — otherwise the ops queue fills with empty submissions.
    const docs = await pool.query(
      "SELECT 1 FROM kyc_documents WHERE user_id = $1 LIMIT 1",
      [req.user.id]
    );
    if (docs.rowCount === 0) {
      res.status(400).json({ detail: "no_documents_uploaded" });
      return;
    }
    await pool.query(
      `UPDATE users
          SET kyc_status = 'PENDING', updated_at = NOW()
        WHERE id = $1
          AND kyc_status IN ('NOT_STARTED', 'PENDING', 'REJECTED')`,
      [req.user.id]
    );
    const after = await pool.query(
      "SELECT kyc_status FROM users WHERE id = $1",
      [req.user.id]
    );
    res.json({ kycStatus: after.rows[0]?.kyc_status || "PENDING" });
  })
);

app.get(
  "/admin/kyc/pending",
  requireAdmin,
  asyncHandler(async (_req, res) => {
    const result = await pool.query(
      `SELECT u.id, u.phone, u.display_name, u.kyc_status,
              json_agg(
                json_build_object(
                  'id', d.id,
                  'kind', d.kind,
                  'storageUrl', d.storage_url,
                  'uploadedAt', d.uploaded_at,
                  'verifiedAt', d.verified_at,
                  'rejectionReason', d.rejection_reason
                )
                ORDER BY d.uploaded_at DESC
              ) FILTER (WHERE d.id IS NOT NULL) AS documents
         FROM users u
         LEFT JOIN kyc_documents d ON d.user_id = u.id::text
        WHERE u.kyc_status = 'PENDING'
        GROUP BY u.id, u.phone, u.display_name, u.kyc_status
        ORDER BY MIN(d.uploaded_at) ASC NULLS LAST, u.updated_at ASC
        LIMIT 100`
    );
    res.json(result.rows.map((row) => ({
      userId: String(row.id),
      phone: maskPhoneForLog(row.phone),
      displayName: row.display_name || "",
      kycStatus: row.kyc_status || "PENDING",
      documents: row.documents || []
    })));
  })
);

app.post(
  "/admin/kyc/:userId/decision",
  requireAdmin,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const userId = String(req.params.userId || "").trim();
    const decision = String(req.body?.decision || "").trim().toUpperCase();
    const reason = String(req.body?.reason || "").trim().slice(0, 500);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
      res.status(400).json({ detail: "invalid_user_id" });
      return;
    }
    if (!["APPROVED", "REJECTED"].includes(decision)) {
      res.status(400).json({ detail: "decision must be APPROVED or REJECTED" });
      return;
    }
    if (decision === "REJECTED" && !reason) {
      res.status(400).json({ detail: "rejection reason required" });
      return;
    }

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      const userRes = await client.query(
        "UPDATE users SET kyc_status = $2, updated_at = NOW() WHERE id = $1 RETURNING id, kyc_status",
        [userId, decision]
      );
      if (userRes.rowCount === 0) {
        await client.query("ROLLBACK");
        res.status(404).json({ detail: "user_not_found" });
        return;
      }
      if (decision === "APPROVED") {
        await client.query(
          `UPDATE kyc_documents
              SET verified_at = NOW(), rejection_reason = NULL
            WHERE user_id = $1`,
          [userId]
        );
      } else {
        await client.query(
          `UPDATE kyc_documents
              SET verified_at = NULL, rejection_reason = $2
            WHERE user_id = $1`,
          [userId, reason]
        );
      }
      await client.query("COMMIT");
      res.json({ userId, kycStatus: decision });
    } catch (err) {
      await client.query("ROLLBACK").catch(() => {});
      throw err;
    } finally {
      client.release();
    }
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
    const rawStorageUrl = bodyValue(body, "storageUrl", "storage_url") || null;

    // SECURITY: clients used to be able to supply any URL string here
    // and it would be stamped onto the user's KYC record. That meant
    // an attacker could (a) point the admin reviewer at a phishing
    // page that mimics KYC, (b) impersonate another user by pointing
    // at the legitimate-looking URL of someone else's upload, or (c)
    // poison the record with a known-bad URL after the fact.
    //
    // The legitimate flow is: client uploads bytes via
    // `/users/me/kyc-documents/upload` → server returns a
    // `storageUri` → client immediately submits that uri here. So
    // any non-null storage_url MUST match a `kyc_uploads` row owned
    // by the same user. If it doesn't, treat the submission as
    // tampered: reject hard rather than persisting an attacker
    // controlled URL.
    let storageUrl = null;
    if (rawStorageUrl) {
      const provenance = await pool.query(
        `SELECT 1 FROM kyc_uploads
          WHERE user_id = $1 AND storage_uri = $2
          LIMIT 1`,
        [req.user.id, rawStorageUrl]
      );
      if (provenance.rowCount === 0) {
        res.status(400).json({ detail: "storageUrl must reference a prior upload owned by this user" });
        return;
      }
      storageUrl = rawStorageUrl;
    }

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
  rateLimitLocation,
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

// GET /rides/:rideId/stream — Server-Sent Events feed of the driver's
// live location for a specific ride. Restricted to participants:
// either the route's driver, or a passenger who has booked or is
// subscribed to the route this ride belongs to. Knowing the ride
// UUID alone is not sufficient — UUIDs leak through screenshots,
// share sheets and notification payloads.
app.get(
  "/rides/:rideId/stream",
  requireAuth,
  asyncHandler(async (req, res) => {
    const rideId = String(req.params.rideId);

    // Authorise: caller must be the driver of the route, OR have a
    // passenger row on this ride, OR hold a non-cancelled subscription
    // on the route this ride belongs to. Anything else is a 403.
    const access = await pool.query(
      `SELECT 1
         FROM commute_ride_instances i
         JOIN recurring_routes r ON r.id = i.route_id
         LEFT JOIN commute_ride_passengers p ON p.instance_id = i.id AND p.rider_id = $2
         LEFT JOIN route_subscriptions s
                ON s.route_id = r.id
               AND s.rider_id = $2
               AND s.status <> 'CANCELLED'
        WHERE i.id = $1
          AND (r.driver_id = $2 OR p.rider_id IS NOT NULL OR s.id IS NOT NULL)
        LIMIT 1`,
      [rideId, req.user.id]
    );
    if (access.rowCount === 0) {
      res.status(403).json({ detail: "not_a_ride_participant" });
      return;
    }

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
// APNs key, Stripe secret) is read from env vars. Production KYC fails
// closed when durable object storage is missing; the other pilot endpoints
// persist queue/audit rows even when external dispatch providers are absent.

// --- KYC document upload ----------------------------------------------------
//
// Accepts a raw PUT/POST body of the image bytes (Content-Type from
// the request); persists to S3-compatible object storage when configured,
// otherwise to disk under `KYC_STORAGE_DIR` in non-production only; inserts
// a `kyc_uploads` row; returns `{ id, storageUri }`. The iOS side then calls
// the existing `POST /users/me/kyc-documents` with the storageUri.

// KYC storage. Local-disk fallback (writing to `KYC_STORAGE_DIR`) is fine
// for development but unsafe in production:
//   1. PII at rest is unencrypted.
//   2. Render's local disk is ephemeral — restarts wipe uploads.
//   3. There's no retention policy or access audit.
// In production we therefore require the S3-compatible adapter configured
// through KYC_S3_* / AWS_* env vars.
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
    const kind = String(req.query.kind || "").toUpperCase().trim();
    if (!kind) {
      res.status(400).json({ detail: "kind query param required" });
      return;
    }
    if (!KYC_DOC_KINDS.has(kind)) {
      res.status(400).json({ detail: "invalid document kind" });
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

    let storageUri;
    if (kycObjectStorageConfigured()) {
      const key = buildKycObjectKey({ userId: req.user.id, id, ext });
      storageUri = await uploadKycObject({ key, body: buffer, contentType });
    } else {
      if (config.isProduction) {
        res.status(503).json({ detail: "kyc_storage_unavailable" });
        return;
      }
      if (config.isStaging) {
        console.warn("[kyc] STAGING: writing PII to local disk (KYC_S3_* env vars unset)");
      }
      ensureKycDirSync();
      const filename = `${id}.${ext}`;
      const fullPath = path.join(KYC_STORAGE_DIR, filename);
      fs.writeFileSync(fullPath, buffer);
      storageUri = `voygo://kyc/${id}.${ext}`;
    }
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
  rateLimitSafety,
  asyncHandler(async (req, res) => {
    const rideId = req.body?.rideId ? String(req.body.rideId).slice(0, 80) : null;
    const routeId = req.body?.routeId ? String(req.body.routeId).slice(0, 80) : null;
    const parsedLat = req.body?.lat != null ? Number(req.body.lat) : null;
    const parsedLng = req.body?.lng != null ? Number(req.body.lng) : null;
    const lat = Number.isFinite(parsedLat) ? parsedLat : null;
    const lng = Number.isFinite(parsedLng) ? parsedLng : null;
    const message = String(req.body?.message || "").slice(0, 4000);

    // Ownership check: an SOS that names a ride/route must come from
    // someone actually on that ride/route. Without this, an
    // authenticated attacker could stamp arbitrary `routeId` strings,
    // pollute another driver's incident record, and harass on-call
    // (since each SOS pages PagerDuty with `severity=critical`).
    //
    // Membership rules:
    //   - rideId: caller is the route's driver, the ride's solo
    //     booker, or an ACTIVE subscriber on that route
    //   - routeId (no rideId): caller is the driver, or an ACTIVE
    //     subscriber on that route
    //
    // If neither id is supplied we accept the alert as-is — a rider
    // might fire SOS before any ride is matched (e.g. walking to the
    // pickup spot) and we don't want a schema artefact blocking that.
    let scopedRideId = rideId;
    let scopedRouteId = routeId;
    if (rideId) {
      const owns = await pool.query(
        `SELECT 1
           FROM commute_ride_instances ri
           JOIN recurring_routes r ON r.id = ri.route_id
           LEFT JOIN route_subscriptions rs
             ON rs.route_id = r.id
            AND rs.rider_id = $2
            AND rs.status = 'ACTIVE'
          WHERE ri.id = $1
            AND (
              r.driver_id = $2
              OR rs.rider_id = $2
              OR ri.solo_rider_id = $2
            )
          LIMIT 1`,
        [rideId, req.user.id]
      );
      if (owns.rowCount === 0) {
        // Drop the bogus ride/route reference but still record the
        // alert — we never want to swallow a real SOS just because
        // the client sent a stale id.
        scopedRideId = null;
        scopedRouteId = null;
      }
    } else if (routeId) {
      const owns = await pool.query(
        `SELECT 1
           FROM recurring_routes r
           LEFT JOIN route_subscriptions rs
             ON rs.route_id = r.id
            AND rs.rider_id = $2
            AND rs.status = 'ACTIVE'
          WHERE r.id = $1
            AND (r.driver_id = $2 OR rs.rider_id = $2)
          LIMIT 1`,
        [routeId, req.user.id]
      );
      if (owns.rowCount === 0) {
        scopedRouteId = null;
      }
    }

    const id = crypto.randomUUID();
    await pool.query(
      `INSERT INTO safety_alerts (id, user_id, ride_id, route_id, lat, lng, message)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [id, req.user.id, scopedRideId, scopedRouteId, lat, lng, message]
    );

    const dispatchedTo = [];
    const dispatchFailures = [];
    const summary = [
      `Voygo SOS ${id}`,
      `user=${req.user.id}`,
      scopedRideId ? `ride=${scopedRideId}` : null,
      scopedRouteId ? `route=${scopedRouteId}` : null,
      Number.isFinite(lat) && Number.isFinite(lng) ? `loc=${lat},${lng}` : null
    ].filter(Boolean).join(" · ");

    if (process.env.SAFETY_TWILIO_NUMBER) {
      if (!smsConfigured()) {
        dispatchFailures.push("twilio_unconfigured");
      } else {
        const sms = await sendSms({
          to: process.env.SAFETY_TWILIO_NUMBER,
          body: `${summary}\n\n${message.slice(0, 900)}`
        });
        if (sms.ok) dispatchedTo.push("twilio");
        else dispatchFailures.push(`twilio_${sms.reason || "failed"}`);
      }
    }

    if (process.env.SAFETY_PAGERDUTY_KEY) {
      try {
        const pd = await fetch("https://events.pagerduty.com/v2/enqueue", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            routing_key: process.env.SAFETY_PAGERDUTY_KEY,
            event_action: "trigger",
            dedup_key: `voygo-sos-${id}`,
            payload: {
              summary,
              severity: "critical",
              source: "voygo-api",
              custom_details: { alertId: id, userId: req.user.id, rideId: scopedRideId, routeId: scopedRouteId, lat, lng, message }
            }
          })
        });
        if (pd.ok) dispatchedTo.push("pagerduty");
        else dispatchFailures.push(`pagerduty_${pd.status}`);
      } catch (_err) {
        dispatchFailures.push("pagerduty_network");
      }
    }

    const opsNotified = dispatchedTo.length > 0;
    res.status(201).json({
      alertId: id,
      status: opsNotified ? "DISPATCHED" : "OPEN",
      dispatchedTo,
      dispatchFailures,
      opsNotified
    });
  })
);

// --- APNs device registration -----------------------------------------------

app.post(
  "/devices",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const apnsToken = String(req.body?.apnsToken || "").trim();
    // APNs tokens are 64 hex chars (32 bytes) historically; modern
    // tokens are longer base64-ish strings. Length check is a soft
    // guard against junk + a malicious oversized payload.
    if (!apnsToken || apnsToken.length < 32 || apnsToken.length > 200) {
      res.status(400).json({ detail: "apnsToken required" });
      return;
    }
    const platform = String(req.body?.platform || "iOS").slice(0, 16);
    const locale = req.body?.locale ? String(req.body.locale).slice(0, 16) : null;
    const appVersion = req.body?.appVersion ? String(req.body.appVersion).slice(0, 32) : null;

    // CRITICAL: the device's APNs token is the unique key. If a
    // previous owner of the device (different user) still has a row
    // with this token, we REASSIGN it to the current user — not add
    // a second row. The old PK (user_id, apns_token) let an attacker
    // who learned a victim's token register it under their own
    // account and harvest the victim's push notifications. The new
    // schema's PK is `apns_token` alone, so this ON CONFLICT replaces
    // any prior owner.
    await pool.query(
      `INSERT INTO push_devices
         (user_id, apns_token, platform, locale, app_version, last_seen_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (apns_token) DO UPDATE
         SET user_id     = EXCLUDED.user_id,
             platform    = EXCLUDED.platform,
             locale      = EXCLUDED.locale,
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
        `SELECT r.id AS route_id, r.driver_id, r.start_location, r.end_location
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
      // A skip frees a seat for tomorrow's pickup — fan out a
      // SEAT_OPENED to favorites + saved-search corridor matches.
      // Detached so we don't block the rider's HTTP response.
      if (row?.route_id) {
        notifySeatOpenedListeners(row.route_id, row.start_location, row.end_location)
          .catch((e) => console.warn(`[notify] skip seat-open fanout: ${e.message}`));
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
  requireAdmin,
  asyncHandler(async (_req, res) => {
    const lookaheadHours = Number(process.env.RIDE_REMINDER_HOURS || 12);
    // The audit caught two column bugs that made this endpoint throw
    // on first call:
    //   1. `commute_ride_instances` has no `scheduled_at` column —
    //      ride time is `date + departure_time` from the route. We
    //      construct it inline via `(i.date + r.departure_time::time)`.
    //   2. `commute_ride_passengers.user_id` is actually `rider_id`.
    const result = await pool.query(
      `SELECT i.id AS ride_id, i.route_id,
              (i.date + r.departure_time::time) AT TIME ZONE 'Asia/Kuala_Lumpur' AS scheduled_at,
              r.start_location, r.end_location, r.departure_time,
              p.rider_id AS user_id
         FROM commute_ride_instances i
         JOIN recurring_routes r ON r.id = i.route_id
         JOIN commute_ride_passengers p ON p.instance_id = i.id
        WHERE (i.date + r.departure_time::time) AT TIME ZONE 'Asia/Kuala_Lumpur'
              BETWEEN NOW() AND NOW() + INTERVAL '1 hour' * $1
          AND p.status = 'CONFIRMED'
          AND NOT EXISTS (
            SELECT 1 FROM notifications n
             WHERE n.user_id = p.rider_id
               AND n.ride_instance_id::text = i.id::text
               AND n.type = 'RIDE_REMINDER'
          )`,
      [lookaheadHours]
    );

    // Fan-out in parallel — N×createNotification was the audit's other
    // perf complaint here. Promise.all keeps total time at ~max-rtt
    // not sum-rtt.
    await Promise.all(result.rows.map((row) =>
      createNotification({
        userId: row.user_id,
        type: "RIDE_REMINDER",
        title: "Pickup tomorrow",
        body: `${row.start_location} → ${row.end_location} at ${row.departure_time}`,
        routeId: row.route_id,
        rideInstanceId: row.ride_id
      }).catch((e) => console.warn(`[reminder] failed for ${row.ride_id}: ${e.message}`))
    ));
    res.json({ dispatched: result.rows.length, lookaheadHours });
  })
);

// Telemetry — best-effort funnel events. Auth is optional so the client can
// send `app_opened` before sign-in. Always returns 204 so a flaky client
// can't get stuck retrying. Caps payload size to avoid abuse.
app.post(
  "/telemetry/events",
  express.json({ limit: "32kb" }),
  rateLimitTelemetry,
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
    if (userId) {
      const prefRes = await pool.query(
        "SELECT preferences FROM users WHERE id = $1 LIMIT 1",
        [userId]
      );
      const prefs = prefRes.rows[0]?.preferences || {};
      if (prefs.analyticsEnabled === false) {
        res.status(204).end();
        return;
      }
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
  requireAdmin,
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

// Diagnostic: returns the SMTP env presence (boolean only — never echoes
// values), the most recent verify result, and the most recent send
// result. Hard-gated to admin-key so the test addresses + error
// detail don't leak to anonymous callers. Re-runs verify when
// `?verify=1` is passed so ops can re-test without restarting.
app.get(
  "/admin/email-status",
  requireAdmin,
  asyncHandler(async (req, res) => {
    if (req.query.verify === "1") {
      await verifyEmailTransport();
    }
    res.json(emailDiagnostics());
  })
);

app.post(
  "/ai/support",
  requireAuth,
  rateLimitAiSupport,
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
  requireKyc,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    // driverName is server-derived. The previous version honoured a
    // client field which let an attacker publish a route under any
    // string they wanted ("Officer Tan"). We pull display_name from
    // the users table and fall back to a neutral public label.
    const userRow = (await pool.query(
      "SELECT display_name FROM users WHERE id = $1",
      [req.user.id]
    )).rows[0];
    const driverName = publicDriverName(userRow?.display_name);

    // Cap free-text fields server-side. start/end_location feeds
    // ILIKE comparisons in fan-out (notifySeatOpenedListeners) — an
    // unbounded label would force a slow scan and hold the request
    // hostage. 120 chars is generous for "Petaling Jaya, Mid Valley
    // Megamall (KTM side)".
    const startLocation = String(bodyValue(body, "startLocation", "start_location") || "").slice(0, 120).trim();
    const endLocation = String(bodyValue(body, "endLocation", "end_location") || "").slice(0, 120).trim();
    if (!startLocation || !endLocation) {
      res.status(400).json({ detail: "startLocation and endLocation required" });
      return;
    }

    const routeId = await createRoute(pool, {
      driverId: req.user.id,
      driverName,
      startLocation,
      endLocation,
      pickupPoints: bodyValue(body, "pickupPoints", "pickup_points") || [],
      dropPoints: bodyValue(body, "dropPoints", "drop_points") || [],
      departureTime: bodyValue(body, "departureTime", "departure_time"),
      daysOfWeek: bodyValue(body, "daysOfWeek", "days_of_week"),
      seatCount: bodyValue(body, "seatCount", "seat_count"),
      pricePerSeat: bodyValue(body, "pricePerSeat", "price_per_seat"),
      carType: bodyValue(body, "carType", "car_type"),
      // plateNumber/carColor are intentionally NOT read from this body.
      // Vehicle identity is sourced from the driver's profile via
      // loadRouteContexts's user JOIN — preventing a route from
      // listing one plate at search time and the driver arriving
      // in a different car.
      activeStatus: "ACTIVE"
    });
    await generateRideInstances(pool, todayIso(), 30);

    // Cross-pollinate with route_requests: when a new route lands,
    // notify riders who flagged interest in this corridor. Run as a
    // detached task so 500 matched requests don't block the driver's
    // create-route HTTP response for 30 seconds.
    fanoutRouteRequestMatches(routeId, startLocation, endLocation).catch((e) => {
      console.warn(`[routes] cross-pollinate failed: ${e.message}`);
    });

    res.json({ id: routeId });
  })
);

// ─── Route requests (cold-start liquidity) ────────────────────────────
//
// When search returns 0 results, the rider can post a request. Drivers
// see aggregated demand on /commute/route-requests/driver/me so they
// can decide whether to add a route. New routes auto-notify the
// matching requesters and flip their status to FULFILLED.

app.post(
  "/commute/route-requests",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const origin = String(bodyValue(body, "origin") || "").trim();
    const destination = String(bodyValue(body, "destination") || "").trim();
    if (!origin || !destination) {
      res.status(400).json({ detail: "origin and destination required" });
      return;
    }
    // Cap open requests per rider at 20 — generous enough for daily
    // commute experimentation, tight enough to stop a runaway client
    // from filling the table.
    const openCount = (await pool.query(
      "SELECT COUNT(*)::int AS n FROM route_requests WHERE rider_id = $1 AND status = 'OPEN'",
      [req.user.id]
    )).rows[0]?.n || 0;
    if (openCount >= 20) {
      res.status(409).json({ detail: "too_many_open_requests" });
      return;
    }
    const id = crypto.randomUUID();
    await pool.query(
      `INSERT INTO route_requests
         (id, rider_id, origin, destination, origin_lat, origin_lng,
          dest_lat, dest_lng, preferred_time, days_of_week, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11)`,
      [
        id,
        req.user.id,
        origin,
        destination,
        bodyValue(body, "originLat", "origin_lat"),
        bodyValue(body, "originLng", "origin_lng"),
        bodyValue(body, "destLat",   "dest_lat"),
        bodyValue(body, "destLng",   "dest_lng"),
        bodyValue(body, "preferredTime", "preferred_time"),
        JSON.stringify(bodyValue(body, "daysOfWeek", "days_of_week") || {}),
        String(bodyValue(body, "notes") || "").slice(0, 500)
      ]
    );
    res.status(201).json({ id });
  })
);

// Rider can withdraw an open request — useful when they no longer
// need that corridor or it gets posted.
app.delete(
  "/commute/route-requests/:id",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `DELETE FROM route_requests
        WHERE id = $1 AND rider_id = $2`,
      [req.params.id, req.user.id]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "not_found" });
      return;
    }
    res.status(204).send();
  })
);

app.get(
  "/commute/route-requests/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT id, origin, destination, preferred_time, days_of_week,
              notes, status, created_at
         FROM route_requests
        WHERE rider_id = $1
        ORDER BY created_at DESC
        LIMIT 50`,
      [req.user.id]
    );
    res.json(result.rows.map((r) => ({
      id: String(r.id),
      origin: r.origin,
      destination: r.destination,
      preferredTime: r.preferred_time,
      daysOfWeek: r.days_of_week,
      notes: r.notes,
      status: r.status,
      createdAt: r.created_at
    })));
  })
);

// Aggregated demand for the driver dashboard — counts of how many
// riders want each corridor.
app.get(
  "/commute/route-requests/demand",
  requireAuth,
  asyncHandler(async (_req, res) => {
    const result = await pool.query(
      `SELECT origin, destination, COUNT(*)::int AS riders
         FROM route_requests
        WHERE status = 'OPEN'
        GROUP BY origin, destination
        ORDER BY riders DESC
        LIMIT 25`
    );
    res.json(result.rows.map((r) => ({
      origin: r.origin,
      destination: r.destination,
      riders: Number(r.riders)
    })));
  })
);

// ─── Route favorites ──────────────────────────────────────────────────
app.post(
  "/commute/routes/:routeId/favorite",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    // Cap favorites per rider at 50. Plenty for a power user
    // comparison-shopping; prevents runaway-toggle floods.
    const count = (await pool.query(
      "SELECT COUNT(*)::int AS n FROM route_favorites WHERE rider_id = $1",
      [req.user.id]
    )).rows[0]?.n || 0;
    if (count >= 50) {
      res.status(409).json({ detail: "favorites_limit" });
      return;
    }
    await pool.query(
      `INSERT INTO route_favorites (route_id, rider_id)
       VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [req.params.routeId, req.user.id]
    );
    res.status(204).send();
  })
);

app.delete(
  "/commute/routes/:routeId/favorite",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    await pool.query(
      `DELETE FROM route_favorites WHERE route_id = $1 AND rider_id = $2`,
      [req.params.routeId, req.user.id]
    );
    res.status(204).send();
  })
);

app.get(
  "/commute/routes/favorites/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const contexts = await loadRouteContexts(
      pool,
      `id IN (SELECT route_id FROM route_favorites WHERE rider_id = $1)`,
      [req.user.id],
      { favoriteForRiderId: req.user.id, requesterId: req.user.id }
    );
    res.json(contexts.map((c) => c.dto));
  })
);

// ─── Corridor-aware pickup / drop suggestions ─────────────────────────
//
// Learns from what real drivers + riders have used as pickup/drop
// points on similar corridors. Given (originLat, originLng, destLat,
// destLng, kind), returns the most-frequently-used labels from
// existing routes whose pickup is near `origin` AND drop is near
// `dest`. Surfaced on the Create Route form ABOVE MapKit results so
// the rail self-improves as more routes get published.
//
// Privacy: every pickup/drop label is already public on the matching
// route detail pages, so we're not leaking new information — we're
// aggregating already-visible data. Counts are public too.
//
// Performance: ST_DWithin on a `geometry` cast to `geography` for
// metre-accurate distance, capped at 5km per side. The route_points
// table has a geom column with a SRID-4326 point so PostGIS uses the
// existing GIST index automatically.
//
// Rate-limited via `rateLimitSearch` (10 req/min/IP) — same bucket
// as autocomplete, because this gets called on every Create Route
// coord change.
app.get(
  "/commute/corridor-suggestions",
  requireAuth,
  rateLimitSearch,
  asyncHandler(async (req, res) => {
    const kindRaw = String(req.query.kind || "").toLowerCase();
    if (kindRaw !== "pickup" && kindRaw !== "drop") {
      res.status(400).json({ detail: "kind must be pickup or drop" });
      return;
    }
    // Parse + validate all four coords. We allow either pair to be
    // missing IF the caller only knows one endpoint (the other is
    // still being filled in) — in that case we fall back to "near
    // the known coord" without the corridor constraint.
    const num = (v) => {
      const n = Number(v);
      return Number.isFinite(n) ? n : null;
    };
    const originLat = num(req.query.originLat);
    const originLng = num(req.query.originLng);
    const destLat   = num(req.query.destLat);
    const destLng   = num(req.query.destLng);
    const hasOrigin = originLat != null && originLng != null;
    const hasDest   = destLat != null && destLng != null;
    if (!hasOrigin && !hasDest) {
      res.status(400).json({ detail: "originLat/originLng or destLat/destLng required" });
      return;
    }
    // Sanity range check — keeps a malicious caller from forcing
    // weird ST_DWithin coords or sending lat=999.
    const inRange = (lat, lng) =>
      lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
    if (hasOrigin && !inRange(originLat, originLng)) {
      res.status(400).json({ detail: "origin coords out of range" });
      return;
    }
    if (hasDest && !inRange(destLat, destLng)) {
      res.status(400).json({ detail: "dest coords out of range" });
      return;
    }

    // The candidate route set: every active route that has BOTH a
    // pickup near `origin` AND a drop near `dest`. When only one
    // coord is supplied, we relax the join to one side.
    //
    // The aggregation then pulls all route_points of the requested
    // `kind` from those routes, groups by label + rounded coord (so
    // "Komtar" at 5.4148,100.3299 doesn't double-count with a tiny
    // ±0.0001 drift), and orders by use count.
    const PICKUP_RADIUS_M = 5000;
    const DROP_RADIUS_M = 5000;
    const params = [kindRaw];
    let pickupNearOriginSql = "TRUE";
    let dropNearDestSql = "TRUE";
    if (hasOrigin) {
      params.push(originLng, originLat); // lng then lat — ST_MakePoint(x=lng, y=lat)
      pickupNearOriginSql = `
        EXISTS (
          SELECT 1 FROM route_points pp
          WHERE pp.route_id = r.id
            AND pp.kind = 'pickup'
            AND ST_DWithin(
              pp.geom::geography,
              ST_SetSRID(ST_MakePoint($${params.length - 1}, $${params.length}), 4326)::geography,
              ${PICKUP_RADIUS_M}
            )
        )
      `;
    }
    if (hasDest) {
      params.push(destLng, destLat);
      dropNearDestSql = `
        EXISTS (
          SELECT 1 FROM route_points dp
          WHERE dp.route_id = r.id
            AND dp.kind = 'drop'
            AND ST_DWithin(
              dp.geom::geography,
              ST_SetSRID(ST_MakePoint($${params.length - 1}, $${params.length}), 4326)::geography,
              ${DROP_RADIUS_M}
            )
        )
      `;
    }

    const sql = `
      WITH matching_routes AS (
        SELECT r.id
          FROM recurring_routes r
         WHERE r.active_status = TRUE
           AND ${pickupNearOriginSql}
           AND ${dropNearDestSql}
      )
      SELECT
        rp.label                         AS label,
        ROUND(rp.lat::numeric, 4)::float AS lat,
        ROUND(rp.lng::numeric, 4)::float AS lng,
        COUNT(*)::int                    AS use_count
      FROM route_points rp
      WHERE rp.kind = $1
        AND rp.route_id IN (SELECT id FROM matching_routes)
      GROUP BY rp.label, ROUND(rp.lat::numeric, 4), ROUND(rp.lng::numeric, 4)
      ORDER BY use_count DESC, label ASC
      LIMIT 12
    `;
    const result = await pool.query(sql, params);
    res.json(result.rows.map((row) => ({
      label: row.label,
      lat: Number(row.lat),
      lng: Number(row.lng),
      useCount: Number(row.use_count)
    })));
  })
);

// ─── Saved commute search ─────────────────────────────────────────────
app.put(
  "/commute/saved-search",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    await pool.query(
      `INSERT INTO commute_saved_searches
         (rider_id, origin_label, destination_label, origin_lat, origin_lng,
          dest_lat, dest_lng, earliest_time, latest_time, days_of_week, max_price_myr, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11, NOW())
       ON CONFLICT (rider_id) DO UPDATE SET
         origin_label       = EXCLUDED.origin_label,
         destination_label  = EXCLUDED.destination_label,
         origin_lat         = EXCLUDED.origin_lat,
         origin_lng         = EXCLUDED.origin_lng,
         dest_lat           = EXCLUDED.dest_lat,
         dest_lng           = EXCLUDED.dest_lng,
         earliest_time      = EXCLUDED.earliest_time,
         latest_time        = EXCLUDED.latest_time,
         days_of_week       = EXCLUDED.days_of_week,
         max_price_myr      = EXCLUDED.max_price_myr,
         updated_at         = NOW()`,
      [
        req.user.id,
        String(bodyValue(body, "originLabel", "origin_label") || ""),
        String(bodyValue(body, "destinationLabel", "destination_label") || ""),
        bodyValue(body, "originLat", "origin_lat"),
        bodyValue(body, "originLng", "origin_lng"),
        bodyValue(body, "destLat",   "dest_lat"),
        bodyValue(body, "destLng",   "dest_lng"),
        String(bodyValue(body, "earliestTime", "earliest_time") || "06:30"),
        String(bodyValue(body, "latestTime",   "latest_time")   || "09:00"),
        JSON.stringify(bodyValue(body, "daysOfWeek", "days_of_week") || {}),
        bodyValue(body, "maxPriceMyr", "max_price_myr")
      ]
    );
    res.status(204).send();
  })
);

app.get(
  "/commute/saved-search",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT origin_label, destination_label, origin_lat, origin_lng,
              dest_lat, dest_lng, earliest_time, latest_time,
              days_of_week, max_price_myr, updated_at
         FROM commute_saved_searches WHERE rider_id = $1`,
      [req.user.id]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "no_saved_search" });
      return;
    }
    const r = result.rows[0];
    res.json({
      originLabel: r.origin_label,
      destinationLabel: r.destination_label,
      originLat: r.origin_lat,
      originLng: r.origin_lng,
      destLat: r.dest_lat,
      destLng: r.dest_lng,
      earliestTime: r.earliest_time,
      latestTime: r.latest_time,
      daysOfWeek: r.days_of_week,
      maxPriceMyr: r.max_price_myr,
      updatedAt: r.updated_at
    });
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

/// Pushes a SEAT_OPENED notification to riders who have either
/// favourited this route or have a saved-search whose corridor
/// (origin/destination labels) substring-matches this route. Triggered
/// whenever capacity expands or a sub releases — sub cancel/pause,
/// route resume, seat_count bump, ride-instance passenger skip.
///
/// Fan-out runs in parallel via Promise.all so a popular route with
/// 200 listeners doesn't block the triggering HTTP request for
/// minutes. Errors are swallowed per-notification — one bad row
/// shouldn't poison the whole batch.
async function notifySeatOpenedListeners(routeId, startLocation, endLocation) {
  try {
    const favRes = await pool.query(
      `SELECT rider_id FROM route_favorites WHERE route_id = $1`,
      [routeId]
    );
    const startLow = String(startLocation || "").toLowerCase();
    const endLow   = String(endLocation   || "").toLowerCase();
    const corridorRes = startLow && endLow
      ? await pool.query(
          `SELECT rider_id
             FROM commute_saved_searches
            WHERE LOWER(origin_label) LIKE '%' || $1 || '%'
              AND LOWER(destination_label) LIKE '%' || $2 || '%'`,
          [startLow, endLow]
        )
      : { rows: [] };
    const recipients = new Set([
      ...favRes.rows.map((r) => String(r.rider_id)),
      ...corridorRes.rows.map((r) => String(r.rider_id))
    ]);
    await Promise.all(
      [...recipients].map((riderId) =>
        createNotification({
          userId: riderId,
          type: "SEAT_OPENED",
          title: "A seat just opened up",
          body: `${startLocation} → ${endLocation} has space. Tap to book.`,
          routeId
        }).catch((err) => {
          console.warn(`[notify] seat-opened to ${riderId} failed: ${err.message}`);
        })
      )
    );
  } catch (err) {
    console.warn(`[notify] seat-opened fanout failed: ${err.message}`);
  }
}

/// Fan-out for route-request matches. Mirror shape of seat-opens —
/// parallel, per-row error isolated, runs detached from the HTTP
/// request that triggered it.
async function fanoutRouteRequestMatches(routeId, startLocation, endLocation) {
  const startLow = String(startLocation || "").toLowerCase();
  const endLow   = String(endLocation   || "").toLowerCase();
  if (!startLow || !endLow) return;
  const matched = await pool.query(
    `SELECT id, rider_id
       FROM route_requests
      WHERE status = 'OPEN'
        AND LOWER(origin) LIKE '%' || $1 || '%'
        AND LOWER(destination) LIKE '%' || $2 || '%'`,
    [startLow, endLow]
  );
  if (matched.rowCount === 0) return;
  await Promise.all(
    matched.rows.map((row) =>
      createNotification({
        userId: row.rider_id,
        type: "ROUTE_REQUEST_MATCHED",
        title: "A driver added your corridor!",
        body: `${startLocation} → ${endLocation} is now available. Tap to subscribe.`,
        routeId
      }).catch((err) => {
        console.warn(`[notify] route-request-match to ${row.rider_id} failed: ${err.message}`);
      })
    )
  );
  await pool.query(
    `UPDATE route_requests SET status = 'FULFILLED' WHERE id = ANY($1::uuid[])`,
    [matched.rows.map((r) => r.id)]
  );
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
      // Resume reopens seats. Ping favorites + saved-search matches
      // so anyone watching gets a heads-up. Detached so the resume
      // HTTP response isn't blocked by the fanout.
      const routeRow = (await pool.query(
        "SELECT start_location, end_location FROM recurring_routes WHERE id = $1",
        [routeId]
      )).rows[0];
      if (routeRow) {
        notifySeatOpenedListeners(routeId, routeRow.start_location, routeRow.end_location)
          .catch((e) => console.warn(`[notify] resume seat-open fanout: ${e.message}`));
      }
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

// PATCH /commute/routes/:routeId — full route edit (price, seat
// count, car type, pickup/drop points). Pause/resume + schedule
// have their own endpoints (status, schedule) so this handler
// covers the rest.
//
// SAFETY: price changes are blocked when a route has active
// subscribers — riders agreed to the original price for the
// remainder of their tier. Drivers can still change price by
// pausing → cancelling active subs → resuming, but that costs
// them the rider; the friction is intentional.
app.patch(
  "/commute/routes/:routeId",
  requireAuth,
  rateLimitWrite,
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

    // Whitelist the patchable fields. Anything not in this list is
    // ignored — protects against a stale client trying to flip
    // status or reassign driver_id.
    const updates = [];
    const params = [routeId];

    const pricePerSeat = bodyValue(body, "pricePerSeat", "price_per_seat");
    if (pricePerSeat != null) {
      const n = Number(pricePerSeat);
      if (!Number.isFinite(n) || n < 1 || n > 500) {
        res.status(400).json({ detail: "pricePerSeat out of range" });
        return;
      }
      // Price-freeze guard: block if any rider is currently ACTIVE.
      const activeRes = await pool.query(
        `SELECT COUNT(*)::int AS c
           FROM route_subscriptions
          WHERE route_id = $1 AND status = 'ACTIVE'`,
        [routeId]
      );
      if (Number(activeRes.rows[0]?.c || 0) > 0) {
        res.status(409).json({
          detail: "price_locked_active_subscribers",
          message: "Price can't change while riders are subscribed. Pause active subs or wait for them to lapse before re-pricing."
        });
        return;
      }
      params.push(n);
      updates.push(`price_per_seat = $${params.length}`);
    }

    const seatCount = bodyValue(body, "seatCount", "seat_count");
    if (seatCount != null) {
      const n = Number(seatCount);
      if (!Number.isFinite(n) || n < 1 || n > 8) {
        res.status(400).json({ detail: "seatCount out of range" });
        return;
      }
      params.push(n);
      updates.push(`seat_count = $${params.length}`);
    }

    const carType = bodyValue(body, "carType", "car_type");
    if (carType != null) {
      const s = String(carType).slice(0, 32);
      params.push(s);
      updates.push(`car_type = $${params.length}`);
    }

    const startLocation = bodyValue(body, "startLocation", "start_location");
    if (startLocation != null) {
      const s = String(startLocation).slice(0, 200);
      params.push(s);
      updates.push(`start_location = $${params.length}`);
    }

    const endLocation = bodyValue(body, "endLocation", "end_location");
    if (endLocation != null) {
      const s = String(endLocation).slice(0, 200);
      params.push(s);
      updates.push(`end_location = $${params.length}`);
    }

    if (updates.length === 0) {
      res.status(400).json({ detail: "no patchable fields supplied" });
      return;
    }

    await pool.query(
      `UPDATE recurring_routes SET ${updates.join(", ")}, updated_at = NOW() WHERE id = $1`,
      params
    );

    // Notify subscribers so they know the route they're on changed.
    // The schedule-update notifier sends a generic line; this one is
    // explicit about the patch so a rider doesn't think their pickup
    // time moved when really the price went up.
    await notifyRouteSubscribers(
      routeId,
      "ROUTE_UPDATED",
      "Route updated",
      "Your driver updated this route. Open the route to see what changed."
    );

    res.status(204).send();
  })
);

// ----------------------------------------------------------------
// Ride-instance lifecycle endpoints.
//
// Without these, the on-time rate metric (which drives the streak
// bonus in payouts.js) and the no-show penalty engine had no way
// to be triggered from the iOS client. Drivers tapped Start / End
// on the day-of card; passengers got auto-flipped to NO_SHOW from
// a separate dedicated endpoint.
//
// Auth: every endpoint requires the caller to BE the route's
// driver. Riders can't start/end their own ride.
// ----------------------------------------------------------------

async function loadRideOwner(rideInstanceId) {
  const res = await pool.query(
    `SELECT r.driver_id AS driver_id, i.ride_status, i.route_id
       FROM commute_ride_instances i
       JOIN recurring_routes r ON r.id = i.route_id
      WHERE i.id = $1
      LIMIT 1`,
    [rideInstanceId]
  );
  return res.rows[0] || null;
}

app.post(
  "/rides/:rideId/start",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const rideId = req.params.rideId;
    const owner = await loadRideOwner(rideId);
    if (!owner) {
      res.status(404).json({ detail: "ride_not_found" });
      return;
    }
    if (String(owner.driver_id) !== req.user.id) {
      res.status(403).json({ detail: "not_your_ride" });
      return;
    }
    if (owner.ride_status !== "SCHEDULED") {
      res.status(409).json({ detail: "ride_not_startable", currentStatus: owner.ride_status });
      return;
    }
    await pool.query(
      `UPDATE commute_ride_instances
          SET ride_status = 'IN_PROGRESS', started_at = NOW()
        WHERE id = $1`,
      [rideId]
    );

    // Fan out a notification to every confirmed passenger so they
    // know the driver has rolled. The push has the routeId so
    // .voygoOpenRoute / .voygoOpenThread handlers work.
    const passengers = await pool.query(
      `SELECT DISTINCT rider_id
         FROM commute_ride_passengers
        WHERE instance_id = $1 AND status = 'CONFIRMED'`,
      [rideId]
    );
    await Promise.all(
      passengers.rows.map((row) =>
        createNotification({
          userId: row.rider_id,
          type: "RIDE_STARTED",
          title: "Driver started the ride",
          body: "Pickup window is now open. Head to your stop.",
          routeId: owner.route_id,
          rideInstanceId: rideId
        }).catch((e) => console.warn(`[ride start] notify failed: ${e.message}`))
      )
    );

    res.status(204).send();
  })
);

app.post(
  "/rides/:rideId/end",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const rideId = req.params.rideId;
    const owner = await loadRideOwner(rideId);
    if (!owner) {
      res.status(404).json({ detail: "ride_not_found" });
      return;
    }
    if (String(owner.driver_id) !== req.user.id) {
      res.status(403).json({ detail: "not_your_ride" });
      return;
    }
    if (owner.ride_status !== "IN_PROGRESS" && owner.ride_status !== "SCHEDULED") {
      res.status(409).json({ detail: "ride_not_endable", currentStatus: owner.ride_status });
      return;
    }
    await pool.query(
      `UPDATE commute_ride_instances
          SET ride_status = 'COMPLETED', ended_at = NOW()
        WHERE id = $1`,
      [rideId]
    );
    // Notify riders so the in-app trip history reflects the
    // completion the moment the driver taps End.
    const passengers = await pool.query(
      `SELECT DISTINCT rider_id
         FROM commute_ride_passengers
        WHERE instance_id = $1 AND status = 'CONFIRMED'`,
      [rideId]
    );
    await Promise.all(
      passengers.rows.map((row) =>
        createNotification({
          userId: row.rider_id,
          type: "RIDE_COMPLETED",
          title: "Ride completed",
          body: "Rate your driver — it helps the next rider.",
          routeId: owner.route_id,
          rideInstanceId: rideId
        }).catch((e) => console.warn(`[ride end] notify failed: ${e.message}`))
      )
    );

    res.status(204).send();
  })
);

app.post(
  "/rides/:rideId/no-show",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const rideId = req.params.rideId;
    const riderId = String(req.body?.riderId || "").slice(0, 80);
    if (!riderId) {
      res.status(400).json({ detail: "riderId required" });
      return;
    }
    const owner = await loadRideOwner(rideId);
    if (!owner) {
      res.status(404).json({ detail: "ride_not_found" });
      return;
    }
    if (String(owner.driver_id) !== req.user.id) {
      res.status(403).json({ detail: "not_your_ride" });
      return;
    }
    // Idempotent + scoped: only the named rider on THIS instance
    // is touched; status flips CONFIRMED → NO_SHOW. Already-no-show
    // rows are a no-op (zero rowCount → 200 with same shape).
    await pool.query(
      `UPDATE commute_ride_passengers
          SET status = 'NO_SHOW'
        WHERE instance_id = $1
          AND rider_id = $2
          AND status = 'CONFIRMED'`,
      [rideId, riderId]
    );
    // Record the no-show in cancellation_records so the trust /
    // payout engines have a single source of truth. The penalty
    // amount is left at 0 here — the policy engine in payouts.js
    // calculates the actual hit at payout time.
    await pool.query(
      `INSERT INTO cancellation_records (id, route_id, ride_instance_id, actor, kind, penalty_amount, reported_at, notes)
       VALUES ($1, $2, $3, 'DRIVER', 'NO_SHOW', 0, NOW(), $4)
       ON CONFLICT DO NOTHING`,
      [crypto.randomUUID(), owner.route_id, rideId, `driver=${req.user.id} rider=${riderId}`]
    ).catch((e) => console.warn(`[no-show] record insert: ${e.message}`));

    // Notify the no-shown rider so they know what happened (often
    // they had forgotten or had a connectivity issue and want to
    // contest). The body intentionally doesn't accuse them — just
    // states the fact.
    await createNotification({
      userId: riderId,
      type: "NO_SHOW",
      title: "Marked as no-show",
      body: "Your driver couldn't pick you up today. Contact support if this is a mistake.",
      routeId: owner.route_id,
      rideInstanceId: rideId
    }).catch((e) => console.warn(`[no-show] notify failed: ${e.message}`));

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
    // Driver viewing their own routes — they already know their own
    // phone, so revealAllPhones is safe (and avoids confusing them
    // with a masked stub on their own dashboard).
    const contexts = await loadRouteContexts(pool, "driver_id = $1", [
      req.params.driverId
    ], { requesterId: req.user.id, revealAllPhones: true });
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
    // Pass requesterId so the DTO's phone is unmasked when the caller
    // is the driver OR an ACTIVE subscriber. Anyone else (e.g. a rider
    // doing a deep-link share preview) sees the masked stub.
    const contexts = await loadRouteContexts(
      pool,
      "id = $1",
      [req.params.routeId],
      { requesterId: req.user.id }
    );
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
    // Capture previous status before the update so the seat-open
    // notification below knows whether a seat actually opened.
    const previousStatus = (await pool.query(
      "SELECT status FROM route_subscriptions WHERE id = $1",
      [subscriptionId]
    )).rows[0]?.status;
    await pool.query(
      `UPDATE route_subscriptions
       SET status = $2
       WHERE id = $1`,
      [subscriptionId, status]
    );

    // Revoke chat access when a rider cancels. Without this an
    // ex-rider remains a `chat_participants` row forever and can
    // keep messaging the driver indefinitely. PAUSED is benign
    // (the rider's coming back) — only CANCELLED tears down. Driver
    // keeps the thread; only this rider's seat at the table goes.
    if (status === "CANCELLED") {
      await pool.query(
        `DELETE FROM chat_participants
          WHERE user_id = $1
            AND thread_id IN (
              SELECT id FROM chat_threads
               WHERE route_id = (SELECT route_id FROM route_subscriptions WHERE id = $2)
            )`,
        [req.user.id, subscriptionId]
      );
    }

    await generateRideInstances(pool, todayIso(), 30);
    // Seat-open notification: when an ACTIVE sub becomes CANCELLED
    // or PAUSED, a seat just freed up. Notify riders who favourited
    // this route OR have a recent saved search whose corridor
    // matches the route, so they can grab the open seat.
    if (previousStatus === "ACTIVE" && (status === "CANCELLED" || status === "PAUSED")) {
      const routeRow = (await pool.query(
        "SELECT route_id, start_location, end_location FROM recurring_routes r JOIN route_subscriptions s ON s.route_id = r.id WHERE s.id = $1",
        [subscriptionId]
      )).rows[0];
      if (routeRow) {
        // Detach the fanout so a 200-listener route doesn't block the
        // subscription-update HTTP response by minutes.
        notifySeatOpenedListeners(routeRow.route_id, routeRow.start_location, routeRow.end_location)
          .catch((e) => console.warn(`[notify] subscription seat-open fanout: ${e.message}`));
      }
    }
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
// `crypto.timingSafeEqual` defends against character-by-character side-channel
// timing on the comparison; padding to equal length first because tSE
// throws when lengths differ.
function requireAdmin(req, res, next) {
  const key = req.get("X-Admin-Key") || "";
  const expected = process.env.ADMIN_API_KEY || "";
  if (!expected) {
    res.status(401).json({ detail: "admin key required" });
    return;
  }
  const keyBuf = Buffer.from(key);
  const expBuf = Buffer.from(expected);
  let ok = false;
  if (keyBuf.length === expBuf.length) {
    try { ok = crypto.timingSafeEqual(keyBuf, expBuf); } catch { ok = false; }
  }
  if (!ok) {
    res.status(401).json({ detail: "admin key required" });
    return;
  }
  next();
}

// Driver-only gate: requires authenticated user AND `kyc_status='APPROVED'`.
// Used to wrap every create-route / publish-trip / vehicle-write surface
// that downstream surfaces to riders. Riders themselves can sign up
// without KYC and book — only the *driver-side* of every product needs
// this gate. If the user is missing entirely we 401 (auth middleware
// should already have caught this; defensive belt-and-braces).
function requireKyc(req, res, next) {
  if (!req.user || !req.user.id) {
    res.status(401).json({ detail: "auth required" });
    return;
  }
  pool.query("SELECT kyc_status FROM users WHERE id = $1", [req.user.id])
    .then((r) => {
      const status = r.rows[0]?.kyc_status || "NOT_STARTED";
      if (status !== "APPROVED") {
        res.status(403).json({ detail: "kyc_required", kycStatus: status });
        return;
      }
      next();
    })
    .catch((err) => next(err));
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

// Legacy create-route. Kept for backwards compatibility with older
// iOS clients; new clients hit POST /commute/routes. Both go through
// the same KYC + rate-limit gate and BOTH derive driver_name from
// the authenticated user — never from the body — to prevent an
// attacker from publishing a route under someone else's display name.
app.post(
  "/routes",
  requireAuth,
  requireKyc,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    // Look up the canonical display name from the users row. Fall back
    // to a neutral public label, never the account UUID.
    const userRow = (await pool.query(
      "SELECT display_name FROM users WHERE id = $1",
      [req.user.id]
    )).rows[0];
    const driverName = publicDriverName(userRow?.display_name);
    const routeId = await createRoute(
      pool,
      {
        driverId: req.user.id,
        driverName,
        startLocation: String(body.start_location || "").slice(0, 120),
        endLocation: String(body.end_location || "").slice(0, 120),
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
                i.is_solo, i.solo_rider_id,
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
      // Solo booking locks out every other rider for that day's
      // instance. The original solo booker themselves still passes
      // this check (they own the ride), but they shouldn't be hitting
      // this endpoint — solo bookings are charged through the
      // dedicated /commute/rides/:id/solo-book flow.
      if (ride.is_solo) {
        res.status(409).json({ detail: "Ride is exclusively booked today" });
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

// ─── Book-a-day (single ride, 1× seat price, paid one-off) ──────────
//
// "Schedule" tile on Home → BookDay flow. Rider picks a route +
// specific upcoming ride instance, pays 1× the seat price for that
// SINGLE day. Doesn't lock the car (other riders can still book
// remaining seats), doesn't require a recurring subscription.
//
// Fills the product gap between:
//   - Subscribe (monthly commit, recurring schedule)
//   - Solo book (2× price, locks the whole car for one day)
//
// Backend shape mirrors solo-book by intent (atomic claim + Billplz
// charge + notification fan-out) but with:
//   - 1× pricing (not 2×)
//   - seat_availability decremented by 1, not zeroed
//   - is_solo NOT flipped — other riders can still book the remaining seats
//   - tier='DAYPASS' so payments / payouts can distinguish from
//     SUBSCRIPTION + SOLO + LONGHAUL revenue without a schema change.
app.post(
  "/trips/:id/book-day",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const client = await pool.connect();
    let committed = false;
    let booking = null;
    try {
      await client.query("BEGIN");
      const rideRes = await client.query(
        `SELECT i.id, i.route_id, i.date, i.ride_status,
                i.is_solo, i.solo_rider_id, i.seat_availability,
                r.driver_id, r.driver_name, r.departure_time,
                r.start_location, r.end_location, r.price_per_seat
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
        res.status(403).json({ detail: "Drivers cannot book their own ride" });
        await client.query("ROLLBACK");
        return;
      }
      if (ride.ride_status !== "SCHEDULED") {
        res.status(409).json({ detail: "ride_not_scheduled" });
        await client.query("ROLLBACK");
        return;
      }
      const departAt = rideDepartAt(ride);
      if (!departAt || departAt.getTime() < Date.now()) {
        res.status(409).json({ detail: "ride_in_past" });
        await client.query("ROLLBACK");
        return;
      }
      if (ride.is_solo) {
        res.status(409).json({ detail: "already_solo_booked" });
        await client.query("ROLLBACK");
        return;
      }
      if (Number(ride.seat_availability) <= 0) {
        res.status(409).json({ detail: "no_seats_available" });
        await client.query("ROLLBACK");
        return;
      }
      // Idempotency: a rider who's already on this ride (subscribed
      // OR previously booked via day-pass) shouldn't pay twice.
      const existing = await client.query(
        `SELECT id FROM commute_ride_passengers
          WHERE instance_id = $1 AND rider_id = $2 LIMIT 1`,
        [req.params.id, req.user.id]
      );
      if (existing.rowCount > 0) {
        res.status(409).json({ detail: "already_booked" });
        await client.query("ROLLBACK");
        return;
      }

      const pricePerSeat = Number(ride.price_per_seat || 0);
      if (!Number.isFinite(pricePerSeat) || pricePerSeat < 1) {
        res.status(409).json({ detail: "price_unavailable" });
        await client.query("ROLLBACK");
        return;
      }

      // Decrement seat availability + record the passenger row.
      // Other riders can still book the remaining seats.
      await client.query(
        `UPDATE commute_ride_instances
            SET seat_availability = GREATEST(0, seat_availability - 1)
          WHERE id = $1`,
        [req.params.id]
      );

      const passengerId = crypto.randomUUID();
      await client.query(
        `INSERT INTO commute_ride_passengers (id, instance_id, rider_id, status)
           VALUES ($1, $2, $3, 'CONFIRMED')`,
        [passengerId, req.params.id, req.user.id]
      );

      await client.query("COMMIT");
      committed = true;
      booking = {
        rideInstanceId: String(ride.id),
        routeId: String(ride.route_id),
        passengerId,
        amountMyr: pricePerSeat,
        driverId: ride.driver_id,
        startLocation: ride.start_location,
        endLocation: ride.end_location
      };
    } catch (error) {
      if (!committed) await client.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      client.release();
    }

    // Charge via the existing Billplz pipeline. subscriptionId is
    // null — day-pass bookings are one-off payments.
    let charge = null;
    try {
      charge = await chargeSubscription(pool, {
        userId: req.user.id,
        subscriptionId: null,
        routeId: booking.routeId,
        amountMyr: booking.amountMyr,
        tier: "DAYPASS",
        contact: bodyValue(req.body || {}, "contact") || {}
      });
    } catch (chargeErr) {
      // Charge failed AFTER we claimed the seat. Release it so the
      // next rider can book + we don't bill for a phantom hold.
      console.warn(`[book-day] charge failed, releasing seat on ${booking.rideInstanceId}: ${chargeErr.message}`);
      await pool.query(
        `UPDATE commute_ride_instances
            SET seat_availability = seat_availability + 1
          WHERE id = $1`,
        [booking.rideInstanceId]
      );
      await pool.query(
        "DELETE FROM commute_ride_passengers WHERE instance_id = $1 AND rider_id = $2",
        [booking.rideInstanceId, req.user.id]
      );
      res.status(502).json({ detail: "charge_failed", reason: chargeErr.message });
      return;
    }

    // Notify both sides. Parallel fan-out — never block the response.
    Promise.all([
      createNotification({
        userId: req.user.id,
        type: "RIDE_BOOKED",
        title: "Ride booked",
        body: `${booking.startLocation} → ${booking.endLocation}`,
        routeId: booking.routeId,
        rideInstanceId: booking.rideInstanceId
      }),
      createNotification({
        userId: booking.driverId,
        type: "RIDE_SEAT_BOOKED",
        title: "Seat booked",
        body: "A rider booked a seat on your ride.",
        routeId: booking.routeId,
        rideInstanceId: booking.rideInstanceId
      })
    ]).catch((e) => console.warn(`[book-day] notify failed: ${e.message}`));

    res.status(201).json({
      rideInstanceId: booking.rideInstanceId,
      routeId: booking.routeId,
      amountMyr: booking.amountMyr,
      payment: charge
    });
  })
);

// ─── Solo seat (book the whole car) ──────────────────────────────────
//
// Rider pays SOLO_PRICE_MULTIPLIER × normal seat price to claim the
// entire car for a specific day's ride. Driver doesn't pick up other
// passengers — same trusted driver, same route, exclusive vehicle.
//
// Malaysia legal note: this stays inside the cost-sharing model
// (driver was going there anyway, rider pays a higher slice of the
// petrol/wear cost) so no LPKP / PSV trigger. The 2× multiplier
// reflects that the driver foregoes other seat revenue + accepts a
// premium for exclusivity.

const SOLO_PRICE_MULTIPLIER = 2;
// Cancellation policy. Time deltas in hours before scheduled depart:
//   >= 12h  : full refund
//   2..12h  : 50% refund (driver may have turned away other bookings)
//   <  2h   : no refund (driver is en-route / committed)
const SOLO_CANCEL_FULL_REFUND_HOURS = 12;
const SOLO_CANCEL_HALF_REFUND_HOURS = 2;

/// Computes the solo price + a depart-at timestamp for a ride instance.
/// Returns null when the ride can't be solo-booked at all (already has
/// passengers, already solo'd, past, cancelled). The reason string
/// drives the iOS UI's disabled-state messaging.
async function loadSoloRideContext(pool, rideInstanceId) {
  const res = await pool.query(
    `SELECT i.id, i.route_id, i.date, i.seat_availability, i.ride_status,
            i.is_solo, i.solo_rider_id, i.solo_price_myr,
            r.driver_id, r.driver_name, r.departure_time,
            r.start_location, r.end_location, r.price_per_seat, r.seat_count,
            (SELECT COUNT(*)::int FROM commute_ride_passengers WHERE instance_id = i.id) AS passenger_count
       FROM commute_ride_instances i
       JOIN recurring_routes r ON r.id = i.route_id
      WHERE i.id = $1
      LIMIT 1`,
    [rideInstanceId]
  );
  return res.rows[0] || null;
}

/// Combines the ride's `date` (DATE) and the route's `departure_time`
/// (HH:mm string) into a single JS Date. Used to compute refund tier
/// and to reject past-departure bookings. Returns null on malformed
/// input so callers can fail with a clear 4xx.
function rideDepartAt(ride) {
  if (!ride?.date || !ride?.departure_time) return null;
  const [hh, mm] = String(ride.departure_time).split(":").map((n) => Number(n));
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  // ride.date can come back as a Date (pg auto-parses DATE) or string.
  const baseIso = ride.date instanceof Date
    ? ride.date.toISOString().slice(0, 10)
    : String(ride.date).slice(0, 10);
  // Anchor in Asia/Kuala_Lumpur (UTC+8) by treating HH:mm as KL time
  // and converting to UTC. Avoids the trap of `new Date('YYYY-MM-DD')`
  // landing at midnight UTC instead of midnight KL.
  const ms = Date.UTC(
    Number(baseIso.slice(0, 4)),
    Number(baseIso.slice(5, 7)) - 1,
    Number(baseIso.slice(8, 10)),
    hh - 8, // KL is UTC+8
    mm,
    0
  );
  return new Date(ms);
}

// GET /commute/rides/:id/solo-quote
//   Returns whether this ride is bookable solo + the server-computed
//   price. iOS uses this to render the confirm sheet — never trust
//   the client to compute the price.
app.get(
  "/commute/rides/:id/solo-quote",
  requireAuth,
  asyncHandler(async (req, res) => {
    const ride = await loadSoloRideContext(pool, req.params.id);
    if (!ride) {
      res.status(404).json({ detail: "Ride not found" });
      return;
    }
    if (String(ride.driver_id) === req.user.id) {
      res.status(403).json({ detail: "Drivers cannot solo-book their own ride" });
      return;
    }
    const departAt = rideDepartAt(ride);
    const departIso = departAt ? departAt.toISOString() : null;
    const pricePerSeat = Number(ride.price_per_seat || 0);
    const soloPrice = pricePerSeat * SOLO_PRICE_MULTIPLIER;
    let available = true;
    let reason = null;
    if (ride.ride_status !== "SCHEDULED") {
      available = false; reason = "ride_not_scheduled";
    } else if (departAt && departAt.getTime() < Date.now()) {
      available = false; reason = "ride_in_past";
    } else if (ride.is_solo) {
      available = false;
      reason = String(ride.solo_rider_id) === req.user.id
        ? "you_already_solo_booked"
        : "already_solo_booked";
    } else if (Number(ride.passenger_count) > 0) {
      available = false; reason = "other_passengers_already_booked";
    }
    res.json({
      rideInstanceId: String(ride.id),
      routeId: String(ride.route_id),
      driverName: ride.driver_name || null,
      startLocation: ride.start_location,
      endLocation: ride.end_location,
      date: ride.date instanceof Date ? ride.date.toISOString().slice(0, 10) : String(ride.date),
      departureTime: ride.departure_time,
      departAt: departIso,
      pricePerSeatMyr: pricePerSeat,
      soloPriceMyr: soloPrice,
      soloMultiplier: SOLO_PRICE_MULTIPLIER,
      available,
      reason,
      // Surfaces the cancellation policy on the confirm sheet so the
      // rider sees the rules BEFORE paying, not in fine print after.
      cancellationPolicy: {
        fullRefundUntilHours: SOLO_CANCEL_FULL_REFUND_HOURS,
        halfRefundUntilHours: SOLO_CANCEL_HALF_REFUND_HOURS
      }
    });
  })
);

// POST /commute/rides/:id/solo-book
//   Atomic claim of the ride + charge via existing payments pipeline.
//   Server-derived price, transactional FOR UPDATE so two riders can't
//   race to claim the same ride, write-rate-limited.
app.post(
  "/commute/rides/:id/solo-book",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const client = await pool.connect();
    let committed = false;
    let booking = null;
    try {
      await client.query("BEGIN");
      const rideRes = await client.query(
        `SELECT i.id, i.route_id, i.date, i.ride_status,
                i.is_solo, i.solo_rider_id,
                r.driver_id, r.driver_name, r.departure_time,
                r.start_location, r.end_location, r.price_per_seat,
                (SELECT COUNT(*)::int FROM commute_ride_passengers WHERE instance_id = i.id) AS passenger_count
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
        res.status(403).json({ detail: "Drivers cannot solo-book their own ride" });
        await client.query("ROLLBACK");
        return;
      }
      if (ride.ride_status !== "SCHEDULED") {
        res.status(409).json({ detail: "ride_not_scheduled" });
        await client.query("ROLLBACK");
        return;
      }
      const departAt = rideDepartAt(ride);
      if (!departAt || departAt.getTime() < Date.now()) {
        res.status(409).json({ detail: "ride_in_past" });
        await client.query("ROLLBACK");
        return;
      }
      if (ride.is_solo) {
        res.status(409).json({ detail: "already_solo_booked" });
        await client.query("ROLLBACK");
        return;
      }
      if (Number(ride.passenger_count) > 0) {
        res.status(409).json({ detail: "other_passengers_already_booked" });
        await client.query("ROLLBACK");
        return;
      }

      // Server-derived price. The /payments/days saga taught us not
      // to honour any client-supplied amount here.
      const pricePerSeat = Number(ride.price_per_seat || 0);
      const soloPriceMyr = pricePerSeat * SOLO_PRICE_MULTIPLIER;
      if (!Number.isFinite(soloPriceMyr) || soloPriceMyr < 1) {
        res.status(409).json({ detail: "price_unavailable" });
        await client.query("ROLLBACK");
        return;
      }

      // Flip the instance to solo + zero remaining seats so the
      // regular booking path (/trips/:id/book) bounces other riders.
      await client.query(
        `UPDATE commute_ride_instances
            SET is_solo        = TRUE,
                solo_rider_id  = $2,
                solo_price_myr = $3,
                solo_booked_at = NOW(),
                seat_availability = 0
          WHERE id = $1`,
        [req.params.id, req.user.id, soloPriceMyr]
      );

      // Insert a passenger row so the existing rides-by-rider lookups
      // see this booking. The `solo_*` flag on the instance is the
      // authoritative source — this row is for joins.
      const passengerId = crypto.randomUUID();
      await client.query(
        `INSERT INTO commute_ride_passengers (id, instance_id, rider_id, status)
           VALUES ($1, $2, $3, 'CONFIRMED')`,
        [passengerId, req.params.id, req.user.id]
      );

      await client.query("COMMIT");
      committed = true;
      booking = {
        rideInstanceId: String(ride.id),
        routeId: String(ride.route_id),
        passengerId,
        amountMyr: soloPriceMyr,
        driverId: ride.driver_id,
        startLocation: ride.start_location,
        endLocation: ride.end_location
      };
    } catch (error) {
      if (!committed) await client.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      client.release();
    }

    // Charge via the existing Billplz pipeline. subscriptionId is
    // null — solo bookings are one-off payments. tier='SOLO' lets the
    // payments + payout aggregators distinguish them from subscription
    // and long-haul revenue without a schema change.
    let charge = null;
    try {
      charge = await chargeSubscription(pool, {
        userId: req.user.id,
        subscriptionId: null,
        routeId: booking.routeId,
        amountMyr: booking.amountMyr,
        tier: "SOLO",
        contact: bodyValue(req.body || {}, "contact") || {}
      });
      await pool.query(
        "UPDATE commute_ride_instances SET solo_payment_id = $1 WHERE id = $2",
        [charge.paymentId, booking.rideInstanceId]
      );
    } catch (chargeErr) {
      // Charge failed AFTER we already locked the instance. Roll back
      // the solo flag so other riders can book and the customer isn't
      // billed for a phantom hold. We DO leave an audit trail in
      // cancellation_records-like logging via console.warn.
      console.warn(`[solo-book] charge failed, releasing ride ${booking.rideInstanceId}: ${chargeErr.message}`);
      await pool.query(
        `UPDATE commute_ride_instances
            SET is_solo = FALSE,
                solo_rider_id = NULL,
                solo_price_myr = NULL,
                solo_booked_at = NULL,
                seat_availability = (SELECT seat_count FROM recurring_routes WHERE id = $2)
          WHERE id = $1`,
        [booking.rideInstanceId, booking.routeId]
      );
      await pool.query(
        "DELETE FROM commute_ride_passengers WHERE instance_id = $1 AND rider_id = $2",
        [booking.rideInstanceId, req.user.id]
      );
      res.status(502).json({ detail: "charge_failed", reason: chargeErr.message });
      return;
    }

    // Notify both sides. Parallel fan-out — never block the response.
    Promise.all([
      createNotification({
        userId: req.user.id,
        type: "SOLO_BOOKED",
        title: "Solo ride confirmed",
        body: `${booking.startLocation} → ${booking.endLocation}`,
        routeId: booking.routeId,
        rideInstanceId: booking.rideInstanceId
      }),
      createNotification({
        userId: booking.driverId,
        type: "SOLO_BOOKED_DRIVER",
        title: "Solo booking — exclusive ride today",
        body: `A rider booked your full car for ${booking.startLocation} → ${booking.endLocation}.`,
        routeId: booking.routeId,
        rideInstanceId: booking.rideInstanceId
      })
    ]).catch((e) => console.warn(`[solo-book] notify failed: ${e.message}`));

    res.status(201).json({
      rideInstanceId: booking.rideInstanceId,
      routeId: booking.routeId,
      amountMyr: booking.amountMyr,
      payment: charge
    });
  })
);

// POST /commute/rides/:id/solo-cancel
//   Cancels a solo booking. Tiered refund based on time-to-departure
//   so we don't burn drivers who've already cleared their calendar.
app.post(
  "/commute/rides/:id/solo-cancel",
  requireAuth,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const client = await pool.connect();
    let committed = false;
    let refundResult = null;
    try {
      await client.query("BEGIN");
      const rideRes = await client.query(
        `SELECT i.id, i.route_id, i.date, i.is_solo,
                i.solo_rider_id, i.solo_price_myr, i.solo_payment_id,
                r.driver_id, r.departure_time, r.seat_count,
                r.start_location, r.end_location
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
      if (!ride.is_solo || !ride.solo_rider_id) {
        res.status(409).json({ detail: "not_solo_booked" });
        await client.query("ROLLBACK");
        return;
      }
      // OWNERSHIP CHECK — only the solo booker can cancel their own
      // booking. The route driver has a separate path (route pause,
      // ride cancellation) and goes through the cancellations
      // endpoint, not here.
      if (String(ride.solo_rider_id) !== req.user.id) {
        res.status(403).json({ detail: "not_your_solo_booking" });
        await client.query("ROLLBACK");
        return;
      }

      const departAt = rideDepartAt(ride);
      const hoursToDepart = departAt
        ? (departAt.getTime() - Date.now()) / 3_600_000
        : -1;
      let refundFraction = 0;
      if (hoursToDepart >= SOLO_CANCEL_FULL_REFUND_HOURS) refundFraction = 1.0;
      else if (hoursToDepart >= SOLO_CANCEL_HALF_REFUND_HOURS) refundFraction = 0.5;
      const refundMyr = Math.floor(Number(ride.solo_price_myr || 0) * refundFraction);

      // Release the instance. We restore seat_availability from
      // route.seat_count so the regular booking path becomes available
      // again. If the rider cancels last-minute (<2h), the seat stays
      // released but they get no refund — same trade-off Grab applies.
      await client.query(
        `UPDATE commute_ride_instances
            SET is_solo = FALSE,
                solo_rider_id = NULL,
                solo_price_myr = NULL,
                solo_booked_at = NULL,
                seat_availability = $2
          WHERE id = $1`,
        [req.params.id, Number(ride.seat_count)]
      );
      await client.query(
        "DELETE FROM commute_ride_passengers WHERE instance_id = $1 AND rider_id = $2",
        [req.params.id, req.user.id]
      );

      // Write a REFUNDED payment row so the wallet credit shows up.
      // Same shape as the cancellation refund elsewhere — keeps the
      // ledger consistent. amountMyr is the REFUND amount (positive),
      // not the original charge.
      let refundPaymentId = null;
      if (refundMyr > 0) {
        refundPaymentId = crypto.randomUUID();
        await client.query(
          `INSERT INTO payments
             (id, user_id, subscription_id, route_id, amount_myr, status, tier, paid_at)
           VALUES ($1, $2, NULL, $3, $4, 'REFUNDED', 'REFUND', NOW())`,
          [refundPaymentId, req.user.id, ride.route_id, refundMyr]
        );
      }

      await client.query("COMMIT");
      committed = true;
      refundResult = {
        refundMyr,
        refundFraction,
        refundPaymentId,
        hoursToDepart,
        driverId: ride.driver_id,
        startLocation: ride.start_location,
        endLocation: ride.end_location,
        routeId: String(ride.route_id)
      };
    } catch (error) {
      if (!committed) await client.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      client.release();
    }

    Promise.all([
      createNotification({
        userId: req.user.id,
        type: "SOLO_CANCELLED",
        title: "Solo ride cancelled",
        body: refundResult.refundMyr > 0
          ? `Refund: RM ${refundResult.refundMyr} credited.`
          : "No refund — cancelled inside the no-refund window.",
        routeId: refundResult.routeId,
        rideInstanceId: req.params.id
      }),
      createNotification({
        userId: refundResult.driverId,
        type: "SOLO_CANCELLED_DRIVER",
        title: "Solo booking cancelled",
        body: `${refundResult.startLocation} → ${refundResult.endLocation} — seats reopened.`,
        routeId: refundResult.routeId,
        rideInstanceId: req.params.id
      })
    ]).catch((e) => console.warn(`[solo-cancel] notify failed: ${e.message}`));

    res.json({
      cancelled: true,
      refundMyr: refundResult.refundMyr,
      refundFraction: refundResult.refundFraction,
      refundPaymentId: refundResult.refundPaymentId
    });
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
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const text = String(req.body?.text || "");
    // Pre-validate length so the client gets a clean 413 rather than the
    // generic 500 handler. The repo layer enforces the same cap as a
    // defense-in-depth check.
    if (text.length > 4000) {
      res.status(413).json({ detail: "message_too_long" });
      return;
    }
    const message = await appendChatMessage(pool, req.params.threadId, text, req.user.id);

    // Push a CHAT_MESSAGE notification to every OTHER participant in
    // the thread. Without this, replies are invisible until the
    // recipient happens to open the Inbox tab — fine for testing,
    // a complaint for real users. The notification carries the
    // route_id so iOS's existing voygoOpenThread deep-link lookup
    // works (Home tap → thread).
    //
    // Run fan-out in parallel so a 20-rider thread doesn't tail the
    // sender's HTTP response by 20× DB roundtrips. Per-recipient
    // failure is logged but never tanks the send — the message itself
    // is already persisted.
    const notify = message._notify || { recipients: [], routeId: null, threadTitle: null };
    const preview = text.length > 80 ? text.slice(0, 80) + "…" : text;
    await Promise.all(
      notify.recipients.map((recipientId) =>
        createNotification({
          userId: recipientId,
          type: "CHAT_MESSAGE",
          title: notify.threadTitle || "New message",
          body: preview,
          routeId: notify.routeId
        }).catch((e) => console.warn(`[chat] notify ${recipientId} failed: ${e.message}`))
      )
    );

    // Strip the internal `_notify` field from the wire response so the
    // shape stays exactly what the iOS ChatMessage decoder expects.
    delete message._notify;
    // Returning the persisted DTO (id + timestamp) lets the iOS
    // client reconcile its optimistic local row with the
    // server-assigned id, instead of clobbering the optimistic
    // bubble on the next refresh.
    res.status(201).json(message);
  })
);

// Marks a thread read for the current user — flips their
// participant `unread_count` to 0. Without this the inbox
// kicker grew forever; only the sender was previously zeroed.
app.post(
  "/chats/:threadId/read",
  requireAuth,
  asyncHandler(async (req, res) => {
    const updated = await markChatThreadRead(pool, req.params.threadId, req.user.id);
    res.json({ ok: updated > 0 });
  })
);

// ───────────────────────── Long-haul (one-off inter-city) ────────────────
//
// Orthogonal to the recurring-routes commute product: drivers post a
// single trip (KL → Penang Friday 6pm), riders book N seats, server
// reserves capacity inside a transaction and charges via the existing
// Billplz pipeline. We deliberately reuse the `payments` table (with
// subscription_id NULL, tier='LONGHAUL') rather than minting a new
// charge schema — receipts and refunds stay one-source-of-truth.

const LONG_HAUL_MAX_SEATS_PER_BOOKING = 8;

// `revealPhone` controls whether the rider sees the unmasked E.164 or
// the masked stub. We reveal when the caller is the driver OR has a
// confirmed booking on the trip. Same policy as the commute route DTO
// — see `loadRouteContexts` in repository.js.
function toLongHaulTripDto(row, { revealPhone = false } = {}) {
  return {
    id: String(row.id),
    driverId: String(row.driver_id),
    driverName: row.driver_name || null,
    driverPhone: maskPhone(row.driver_phone, { revealed: revealPhone }),
    driverPhoneRevealed: revealPhone,
    driverRating: row.average_rating != null ? Number(row.average_rating) : null,
    origin: row.origin,
    destination: row.destination,
    departAt: row.depart_at,
    seatsTotal: Number(row.seats_total),
    seatsAvailable: Number(row.seats_available),
    pricePerSeatMyr: Number(row.price_per_seat_myr),
    status: row.status,
    notes: row.notes || ""
  };
}

// Driver creates a trip. Rejects past departures, absurd seat counts,
// and absurd prices so a fat-finger doesn't list a RM 5000 / seat trip
// for 50 seats. Status starts OPEN.
app.post(
  "/longhaul/trips",
  requireAuth,
  requireKyc,
  rateLimitWrite,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const origin = String(bodyValue(body, "origin") || "").slice(0, 120).trim();
    const destination = String(bodyValue(body, "destination") || "").slice(0, 120).trim();
    const departAtRaw = bodyValue(body, "departAt", "depart_at");
    const seatsTotal = Number(bodyValue(body, "seatsTotal", "seats_total"));
    const pricePerSeatMyr = Number(bodyValue(body, "pricePerSeatMyr", "price_per_seat_myr"));
    const notes = String(bodyValue(body, "notes") || "").slice(0, 1000);

    if (!origin || !destination) {
      res.status(400).json({ detail: "origin and destination required" });
      return;
    }
    const departAt = new Date(departAtRaw);
    if (Number.isNaN(departAt.getTime()) || departAt.getTime() < Date.now() - 60_000) {
      res.status(400).json({ detail: "departAt must be a future ISO datetime" });
      return;
    }
    if (!Number.isFinite(seatsTotal) || seatsTotal < 1 || seatsTotal > 20) {
      res.status(400).json({ detail: "seatsTotal must be 1..20" });
      return;
    }
    if (!Number.isFinite(pricePerSeatMyr) || pricePerSeatMyr < 5 || pricePerSeatMyr > 5000) {
      res.status(400).json({ detail: "pricePerSeatMyr must be RM 5..5000" });
      return;
    }

    const id = crypto.randomUUID();
    await pool.query(
      `INSERT INTO long_haul_trips
         (id, driver_id, origin, destination, depart_at,
          seats_total, seats_available, price_per_seat_myr, status, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $6, $7, 'OPEN', $8)`,
      [id, req.user.id, origin, destination, departAt.toISOString(),
       seatsTotal, pricePerSeatMyr, notes]
    );
    res.status(201).json({ id });
  })
);

// Browse open trips. Filters: origin, destination (substring match —
// people type "KL" or "Kuala Lumpur"), fromDate (default = now). Caps
// at 100 rows so a degenerate query can't bloat the response.
app.get(
  "/longhaul/trips",
  requireAuth,
  asyncHandler(async (req, res) => {
    const origin = String(req.query.origin || "").trim();
    const destination = String(req.query.destination || "").trim();
    const fromDate = req.query.fromDate
      ? new Date(String(req.query.fromDate))
      : new Date();
    const fromIso = Number.isNaN(fromDate.getTime())
      ? new Date().toISOString()
      : fromDate.toISOString();

    const where = ["t.depart_at >= $1", "t.status = 'OPEN'", "t.seats_available > 0"];
    const params = [fromIso];
    if (origin) {
      params.push(`%${origin}%`);
      where.push(`t.origin ILIKE $${params.length}`);
    }
    if (destination) {
      params.push(`%${destination}%`);
      where.push(`t.destination ILIKE $${params.length}`);
    }
    const sql = `
      SELECT t.id, t.driver_id, t.origin, t.destination, t.depart_at,
             t.seats_total, t.seats_available, t.price_per_seat_myr, t.status, t.notes,
             u.display_name AS driver_name,
             u.phone        AS driver_phone,
             dr.average_rating
        FROM long_haul_trips t
        LEFT JOIN users u             ON u.id::text = t.driver_id
        LEFT JOIN driver_reliability dr ON dr.driver_id = t.driver_id
       WHERE ${where.join(" AND ")}
       ORDER BY t.depart_at ASC
       LIMIT 100
    `;
    const result = await pool.query(sql, params);
    if (result.rowCount === 0) {
      res.json([]);
      return;
    }
    // Reveal phones only on trips where caller is the driver OR has
    // a booking. One round-trip on long_haul_bookings keyed by the
    // matching trip ids, so we don't N+1 the response.
    const tripIds = result.rows.map((r) => String(r.id));
    const driverIds = new Set(result.rows.map((r) => String(r.driver_id)));
    let bookedTripIds = new Set();
    if (!driverIds.has(String(req.user.id))) {
      const bookRes = await pool.query(
        `SELECT trip_id::text AS trip_id
           FROM long_haul_bookings
          WHERE rider_id = $1
            AND trip_id = ANY($2::uuid[])`,
        [req.user.id, tripIds]
      );
      bookedTripIds = new Set(bookRes.rows.map((r) => r.trip_id));
    } else {
      // Driver: reveal only on their own trips, mask on others.
      bookedTripIds = new Set(); // handled per-row below via driver_id check
    }
    res.json(result.rows.map((row) => {
      const isDriver = String(row.driver_id) === String(req.user.id);
      const hasBooking = bookedTripIds.has(String(row.id));
      return toLongHaulTripDto(row, { revealPhone: isDriver || hasBooking });
    }));
  })
);

// Trip detail — same shape as the list rows.
app.get(
  "/longhaul/trips/:id",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT t.id, t.driver_id, t.origin, t.destination, t.depart_at,
              t.seats_total, t.seats_available, t.price_per_seat_myr, t.status, t.notes,
              u.display_name AS driver_name,
              u.phone        AS driver_phone,
              dr.average_rating
         FROM long_haul_trips t
         LEFT JOIN users u             ON u.id::text = t.driver_id
         LEFT JOIN driver_reliability dr ON dr.driver_id = t.driver_id
        WHERE t.id = $1`,
      [req.params.id]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "trip_not_found" });
      return;
    }
    // Same gating policy as the list endpoint above.
    const row = result.rows[0];
    const isDriver = String(row.driver_id) === String(req.user.id);
    let hasBooking = false;
    if (!isDriver) {
      const bookRes = await pool.query(
        "SELECT 1 FROM long_haul_bookings WHERE trip_id = $1 AND rider_id = $2 LIMIT 1",
        [req.params.id, req.user.id]
      );
      hasBooking = bookRes.rowCount > 0;
    }
    res.json(toLongHaulTripDto(row, { revealPhone: isDriver || hasBooking }));
  })
);

// Book N seats. Transactional seat reservation + payment row insert
// so two concurrent bookings can't oversell. Amount is server-derived
// from the trip's price × seats — client-supplied amounts are
// ignored, same security boundary as the subscription charge path.
app.post(
  "/longhaul/trips/:id/book",
  requireAuth,
  asyncHandler(async (req, res) => {
    const tripId = req.params.id;
    const seats = Number(bodyValue(req.body || {}, "seats") || 1);
    if (!Number.isFinite(seats) || seats < 1 || seats > LONG_HAUL_MAX_SEATS_PER_BOOKING) {
      res.status(400).json({ detail: `seats must be 1..${LONG_HAUL_MAX_SEATS_PER_BOOKING}` });
      return;
    }

    const client = await pool.connect();
    let bookingId = null;
    let amountMyr = 0;
    let driverId = null;
    let trip = null;
    let committed = false;
    try {
      await client.query("BEGIN");
      const tripRes = await client.query(
        `SELECT id, driver_id, origin, destination, depart_at,
                seats_total, seats_available, price_per_seat_myr, status
           FROM long_haul_trips
          WHERE id = $1
          FOR UPDATE`,
        [tripId]
      );
      if (tripRes.rowCount === 0) {
        await client.query("ROLLBACK");
        res.status(404).json({ detail: "trip_not_found" });
        return;
      }
      trip = tripRes.rows[0];
      if (trip.status !== "OPEN") {
        await client.query("ROLLBACK");
        res.status(409).json({ detail: "trip_not_open" });
        return;
      }
      if (String(trip.driver_id) === req.user.id) {
        await client.query("ROLLBACK");
        res.status(400).json({ detail: "cannot_book_own_trip" });
        return;
      }
      if (Number(trip.seats_available) < seats) {
        await client.query("ROLLBACK");
        res.status(409).json({ detail: "not_enough_seats" });
        return;
      }
      const dup = await client.query(
        "SELECT id FROM long_haul_bookings WHERE trip_id = $1 AND rider_id = $2",
        [tripId, req.user.id]
      );
      if (dup.rowCount > 0) {
        await client.query("ROLLBACK");
        res.status(409).json({ detail: "already_booked" });
        return;
      }

      bookingId = crypto.randomUUID();
      driverId = trip.driver_id;
      amountMyr = Number(trip.price_per_seat_myr) * seats;

      await client.query(
        `INSERT INTO long_haul_bookings (id, trip_id, rider_id, seats)
         VALUES ($1, $2, $3, $4)`,
        [bookingId, tripId, req.user.id, seats]
      );
      await client.query(
        `UPDATE long_haul_trips
            SET seats_available = seats_available - $1,
                status = CASE WHEN seats_available - $1 <= 0 THEN 'FULL' ELSE status END,
                updated_at = NOW()
          WHERE id = $2`,
        [seats, tripId]
      );
      await client.query("COMMIT");
      committed = true;
    } catch (err) {
      if (!committed) await client.query("ROLLBACK").catch(() => {});
      throw err;
    } finally {
      client.release();
    }

    // Charge via the existing Billplz pipeline. subscriptionId/routeId
    // stay NULL — long-haul has its own first-class booking row. The
    // billplz callback rolls these into PAYMENT_SUCCEEDED notifications
    // with copy that adapts when subscription_id is null.
    const charge = await chargeSubscription(pool, {
      userId: req.user.id,
      subscriptionId: null,
      routeId: null,
      amountMyr,
      tier: "LONGHAUL",
      contact: bodyValue(req.body || {}, "contact") || {}
    });
    await pool.query(
      "UPDATE long_haul_bookings SET payment_id = $1 WHERE id = $2",
      [charge.paymentId, bookingId]
    );

    if (driverId) {
      await createNotification({
        userId: driverId,
        type: "LONGHAUL_BOOKING",
        title: "New long-haul booking",
        body: `${seats} seat${seats === 1 ? "" : "s"} — ${trip.origin} → ${trip.destination}`
      });
    }

    res.status(201).json({
      bookingId,
      tripId,
      seats,
      amountMyr,
      payment: charge
    });
  })
);

// Rider's bookings. Joins back through long_haul_trips so the iOS
// list can render origin/destination/depart-at without a second fetch.
app.get(
  "/longhaul/bookings/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT b.id, b.trip_id, b.seats, b.status, b.payment_id, b.created_at,
              t.origin, t.destination, t.depart_at, t.price_per_seat_myr,
              u.display_name AS driver_name,
              u.phone        AS driver_phone
         FROM long_haul_bookings b
         JOIN long_haul_trips t  ON t.id = b.trip_id
         LEFT JOIN users u       ON u.id::text = t.driver_id
        WHERE b.rider_id = $1
        ORDER BY t.depart_at DESC
        LIMIT 50`,
      [req.user.id]
    );
    // Caller is the booking owner — they need the driver's real
    // phone to call. Reveal unmasked here.
    res.json(result.rows.map((row) => ({
      id: String(row.id),
      tripId: String(row.trip_id),
      seats: Number(row.seats),
      status: row.status,
      paymentId: row.payment_id ? String(row.payment_id) : null,
      origin: row.origin,
      destination: row.destination,
      departAt: row.depart_at,
      pricePerSeatMyr: Number(row.price_per_seat_myr),
      driverName: row.driver_name || null,
      driverPhone: row.driver_phone || null,
      driverPhoneRevealed: true
    })));
  })
);

// Driver's posted trips, including a rolling booked-seats count.
app.get(
  "/longhaul/trips/driver/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT t.id, t.driver_id, t.origin, t.destination, t.depart_at,
              t.seats_total, t.seats_available, t.price_per_seat_myr, t.status, t.notes,
              u.display_name AS driver_name,
              u.phone        AS driver_phone,
              dr.average_rating
         FROM long_haul_trips t
         LEFT JOIN users u             ON u.id::text = t.driver_id
         LEFT JOIN driver_reliability dr ON dr.driver_id = t.driver_id
        WHERE t.driver_id = $1
        ORDER BY t.depart_at DESC
        LIMIT 100`,
      [req.user.id]
    );
    // Caller is the driver of every row in this result by definition,
    // so revealPhone = true. Avoids confusing them with a mask on
    // their own dashboard.
    res.json(result.rows.map((row) => toLongHaulTripDto(row, { revealPhone: true })));
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
    const tier = String(bodyValue(body, "tier") || "MONTHLY").toUpperCase();
    if (!SUBSCRIPTION_TIERS.has(tier)) {
      res.status(400).json({ detail: "invalid_tier" });
      return;
    }
    if (!subscriptionId) {
      res.status(400).json({ detail: "subscriptionId is required" });
      return;
    }

    // Look up the subscription + its route. Authorising the caller AND
    // computing the price from server-truth, so a tampered iOS build
    // can't ask to be charged RM 1 for a RM 220 monthly tier.
    const subRes = await pool.query(
      `SELECT s.id, s.rider_id, s.route_id, s.start_date, s.end_date,
              s.status, r.price_per_seat
         FROM route_subscriptions s
         JOIN recurring_routes r ON r.id = s.route_id
        WHERE s.id = $1
        LIMIT 1`,
      [subscriptionId]
    );
    if (subRes.rowCount === 0) {
      res.status(404).json({ detail: "subscription_not_found" });
      return;
    }
    const sub = subRes.rows[0];
    if (String(sub.rider_id) !== req.user.id) {
      res.status(403).json({ detail: "not_your_subscription" });
      return;
    }
    if (sub.status === "CANCELLED") {
      res.status(409).json({ detail: "subscription_cancelled" });
      return;
    }

    // Idempotency: refuse to open a second pending charge for the same
    // subscription+tier. Riders who tap "Pay" twice (or whose redirect
    // bounces) shouldn't end up with two Billplz bills.
    const dupRes = await pool.query(
      `SELECT id, billplz_payment_url
         FROM payments
        WHERE subscription_id = $1
          AND tier = $2
          AND status = 'PENDING'
        ORDER BY created_at DESC
        LIMIT 1`,
      [subscriptionId, tier]
    );
    if (dupRes.rowCount > 0) {
      res.json({
        paymentId: dupRes.rows[0].id,
        status: "PENDING",
        paymentUrl: dupRes.rows[0].billplz_payment_url,
        reused: true
      });
      return;
    }

    // Server-truth price. Mirrors `SubscriptionPricing.totalForTier` on
    // iOS (Models/Trust.swift) — keep these two in sync until they share
    // a code path. Days are derived from the subscription range so a
    // partial-month signup pays the right pro-rated amount.
    //
    // SECURITY: `days` is *never* read from the request body. The
    // previous version preferred a client-supplied `days` if present,
    // which let a modified client send `days: 1` on a MONTHLY tier
    // and pay ~RM 1 instead of the ~22-day total. The server now
    // unconditionally derives days from the subscription's stored
    // start/end dates.
    const days = subscriptionWorkingDays(sub.start_date, sub.end_date);
    const amountMyr = computeSubscriptionAmount(
      Number(sub.price_per_seat),
      tier,
      days
    );
    if (!Number.isFinite(amountMyr) || amountMyr < 1) {
      res.status(500).json({ detail: "amount_computation_failed" });
      return;
    }

    const result = await chargeSubscription(pool, {
      userId: req.user.id,
      subscriptionId: sub.id,
      routeId: sub.route_id,
      amountMyr,
      tier,
      contact: bodyValue(body, "contact") || {}
    });
    res.json({ ...result, amountMyr });
  })
);

const SUBSCRIPTION_TIERS = new Set(["DAILY", "MONTHLY", "QUARTERLY"]);

function tierBillingDays(tier) {
  switch (tier) {
    case "DAILY":     return 1;
    case "QUARTERLY": return 66;
    case "MONTHLY":
    default:          return 22;
  }
}

function tierDiscountFactor(tier) {
  switch (tier) {
    case "DAILY":     return 1.00;
    case "QUARTERLY": return 0.85;
    case "MONTHLY":
    default:          return 0.90;
  }
}

function clampDays(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.max(1, Math.min(Math.floor(n), 90));
}

function subscriptionWorkingDays(start, end) {
  if (!start || !end) return 22;
  const startMs = new Date(start).getTime();
  const endMs   = new Date(end).getTime();
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs < startMs) return 22;
  let count = 0;
  for (let t = startMs; t <= endMs; t += 86_400_000) {
    const wd = new Date(t).getUTCDay();
    if (wd >= 1 && wd <= 5) count += 1;
  }
  return Math.max(1, count);
}

function computeSubscriptionAmount(pricePerSeatMyr, tier, days) {
  if (!Number.isFinite(pricePerSeatMyr) || pricePerSeatMyr < 1) return 0;
  const perSeat = Math.max(1, Math.round(pricePerSeatMyr * tierDiscountFactor(tier)));
  const billable = Math.max(1, Math.min(days, tierBillingDays(tier)));
  return perSeat * billable;
}

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
      // Schema column is `billplz_bill_id` (payments.js:30,40,154,168).
      // Previous `billplz_id` typo silently swallowed every PAYMENT_SUCCEEDED
      // notification — riders never knew their card cleared. Audit catch.
      const lookup = await pool.query(
        `SELECT user_id, route_id, subscription_id, amount_myr
           FROM payments
          WHERE billplz_bill_id = $1
          LIMIT 1`,
        [billId]
      );
      const row = lookup.rows[0];

      if (paid) {
        await markPaymentPaid(pool, { billId });
        if (row?.user_id) {
          // Long-haul payments have neither subscription_id nor route_id
          // — keep the body copy honest in that case.
          const isSubscription = !!row.subscription_id;
          await createNotification({
            userId: row.user_id,
            type: "PAYMENT_SUCCEEDED",
            title: "Payment received",
            body: isSubscription
              ? `Your subscription is active. RM ${row.amount_myr} charged.`
              : `RM ${row.amount_myr} charged.`,
            routeId: row.route_id,
            subscriptionId: row.subscription_id
          });
        }
      } else if (row?.user_id) {
        // Treat any non-paid callback (cancelled, expired, refused)
        // as a failed-payment signal so the rider sees an honest
        // notification + can retry from the wallet.
        const isSubscription = !!row.subscription_id;
        await createNotification({
          userId: row.user_id,
          type: "PAYMENT_FAILED",
          title: "Payment didn't go through",
          body: isSubscription
            ? "Your subscription is paused. Retry from My Subscriptions."
            : "We couldn't charge your card. Try again from My Bookings.",
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
      // SECURITY: require an explicit subscriptionId AND verify it
      // belongs to this rider on this route. The previous version
      // accepted a null subscriptionId and passed the access check
      // via *any* of the rider's subs on the route, then wrote the
      // refund row referencing the body-supplied subscriptionId
      // (potentially someone else's). That credited the attacker's
      // wallet while pointing the ledger at a victim's subscription_id
      // — ledger corruption + small-bounty self-refund attack.
      if (!subscriptionId) {
        res.status(400).json({ detail: "subscriptionId required for rider cancellations" });
        return;
      }
      const riderAccess = await pool.query(
        `SELECT id
           FROM route_subscriptions
          WHERE id::text = $1::text
            AND route_id = $2
            AND rider_id = $3
          LIMIT 1`,
        [subscriptionId, routeId, req.user.id]
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
    case "RIDER_CANCEL_MID_MONTH": {
      // 10% admin fee, capped at MYR 20, expressed as a refund (negative).
      // Previous formula was `Math.floor(pricePerSeat / 10) * 22` — wrong
      // unit math (a price of RM 9 yielded a RM 0 refund; a price of
      // RM 15 yielded RM 22 before cap). We compute the actual 10% fee
      // and floor at MYR 1 so a tiny refund doesn't disappear entirely.
      const fee = Math.max(1, Math.floor(pricePerSeat * 22 * 0.1));
      return -Math.min(20, fee);
    }
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

  // Boot-time SMTP verify. Doesn't block listen() — runs async so a
  // dead SMTP host doesn't delay the health check, but the result is
  // surfaced both in stdout and via /admin/email-status so ops sees
  // EAUTH / ETIMEDOUT immediately instead of waiting for first OTP.
  if (emailConfigured()) {
    const provider = activeProvider();
    verifyEmailTransport().then((result) => {
      if (result.ok) {
        console.log(`[email] ${provider} verify OK`);
      } else {
        console.warn(
          `[email] ${provider} verify FAILED: code=${result.code || "?"} ` +
          `responseCode=${result.responseCode || "?"} ` +
          `command=${result.command || "?"} reason=${result.reason} ` +
          `message="${result.message || result.error || ""}"`
        );
      }
    });
  } else {
    console.log("[email] no provider configured — OTP will fall back to dev-echo");
  }

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
