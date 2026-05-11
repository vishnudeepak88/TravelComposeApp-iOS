async function initSchema(pool) {
  await pool.query("CREATE EXTENSION IF NOT EXISTS postgis");

  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY,
      phone TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL DEFAULT '',
      kyc_status TEXT NOT NULL DEFAULT 'NOT_STARTED',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  // Vehicle identity lives on the driver, not per-route. A driver
  // who lists one plate on a route then shows up in a different car
  // is an obvious safety/trust hole. These columns let every route
  // the driver creates inherit their single vehicle identity at
  // read time via the users JOIN. Future: validate against the
  // KYC vehicle registration document on PUT /users/me/vehicle.
  await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS plate_number TEXT NULL");
  await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS car_color   TEXT NULL");
  await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS car_model   TEXT NULL");

  // Aggregate rating + count. Default NULL so iOS can render "New
  // rider" until ratingCount crosses the social-proof threshold
  // (3, defined client-side in User.minRatingsForDisplay). The
  // previous version hardcoded 5.0 for every freshly-installed user
  // — a fake stat that made every rating elsewhere in the app feel
  // theatrical. These columns are populated by the reviews fan-out
  // when ride_reviews lands; until then they stay NULL and Profile
  // shows the honest empty state.
  await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS average_rating DOUBLE PRECISION NULL");
  await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS rating_count INTEGER NOT NULL DEFAULT 0");

  // PDPA / App Store 5.1.1(v) account deletion. We soft-delete first
  // (deleted_at != NULL) so a misclick can be reversed within a 30-day
  // grace window. After the grace window an ops sweep anonymizes
  // display_name and scrubs phone — that runs separately, here we
  // just store the timestamp.
  await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL");

  // User preferences. Simple JSONB so we can add new toggles without
  // a migration per setting. Defaults to '{}' so every existing user
  // gets sensible "everything on" behavior.
  await pool.query(
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS preferences JSONB NOT NULL DEFAULT '{}'::jsonb"
  );

  // Block list — who has this user blocked from matching with them?
  // Used by /commute/search and /commute/route-requests to filter
  // routes whose driver the rider has blocked. Bidirectional: if
  // either side blocked the other, no match. Soft cap at 200 entries
  // per user (enforced in the POST handler).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_blocks (
      blocker_id TEXT NOT NULL,
      blocked_id TEXT NOT NULL,
      reason     TEXT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (blocker_id, blocked_id)
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_user_blocks_blocker ON user_blocks(blocker_id, created_at DESC)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_user_blocks_blocked ON user_blocks(blocked_id)"
  );

  // Plate uniqueness. Case-insensitive partial index so two drivers
  // can't both claim "PEN 1234". Partial-WHERE excludes NULLs so users
  // who haven't set a plate yet don't collide on the empty-key.
  // Whitespace differences (`"PEN 1234"` vs `"PEN1234"`) are
  // normalised by squashing spaces in the index expression.
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS ux_users_plate_number
      ON users (LOWER(REGEXP_REPLACE(plate_number, '\\s+', '', 'g')))
      WHERE plate_number IS NOT NULL AND plate_number <> ''
  `);

  // Audit log for vehicle-identity changes. Every write goes through
  // PUT /users/me/vehicle and lands a row here so a driver who swaps
  // plates between rides leaves a trail. Ops can query historical
  // values when investigating a rider report.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_vehicle_history (
      id            UUID PRIMARY KEY,
      user_id       TEXT NOT NULL,
      plate_number  TEXT NULL,
      car_color     TEXT NULL,
      car_model     TEXT NULL,
      changed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      source_ip     TEXT NULL
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_user_vehicle_history_user ON user_vehicle_history(user_id, changed_at DESC)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS otp_codes (
      id UUID PRIMARY KEY,
      phone TEXT NOT NULL,
      code_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      used_at TIMESTAMPTZ NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_otp_codes_phone ON otp_codes(phone)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS driver_reliability (
      driver_id TEXT PRIMARY KEY,
      on_time_rate DOUBLE PRECISION NOT NULL DEFAULT 0.9,
      cancellation_rate DOUBLE PRECISION NOT NULL DEFAULT 0.05,
      repeat_riders INTEGER NOT NULL DEFAULT 0,
      average_rating DOUBLE PRECISION NOT NULL DEFAULT 4.5,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS recurring_routes (
      id UUID PRIMARY KEY,
      driver_id TEXT NOT NULL,
      driver_name TEXT NOT NULL DEFAULT '',
      start_location TEXT NOT NULL,
      end_location TEXT NOT NULL,
      departure_time TIME NOT NULL,
      days_of_week JSONB NOT NULL,
      seat_count INTEGER NOT NULL,
      price_per_seat INTEGER NOT NULL,
      car_type TEXT NOT NULL DEFAULT 'SEDAN',
      active_status BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_recurring_routes_driver_id ON recurring_routes(driver_id)"
  );
  await pool.query(
    "ALTER TABLE recurring_routes ADD COLUMN IF NOT EXISTS driver_name TEXT NOT NULL DEFAULT ''"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS route_points (
      id UUID PRIMARY KEY,
      route_id UUID NOT NULL REFERENCES recurring_routes(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      label TEXT NOT NULL,
      cluster_id TEXT NULL,
      lat DOUBLE PRECISION NOT NULL,
      lng DOUBLE PRECISION NOT NULL,
      geom geometry(Point, 4326) NOT NULL
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_route_points_route_id ON route_points(route_id)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS route_subscriptions (
      id UUID PRIMARY KEY,
      route_id UUID NOT NULL REFERENCES recurring_routes(id) ON DELETE CASCADE,
      rider_id TEXT NOT NULL,
      rider_name TEXT NOT NULL DEFAULT '',
      start_date DATE NOT NULL,
      end_date DATE NOT NULL,
      selected_pickup_point_id UUID NOT NULL REFERENCES route_points(id),
      selected_drop_point_id UUID NOT NULL REFERENCES route_points(id),
      status TEXT NOT NULL DEFAULT 'ACTIVE',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_route_subscriptions_route_id ON route_subscriptions(route_id)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_route_subscriptions_rider_id ON route_subscriptions(rider_id)"
  );
  await pool.query(
    "ALTER TABLE route_subscriptions ADD COLUMN IF NOT EXISTS rider_name TEXT NOT NULL DEFAULT ''"
  );
  await pool.query(
    `CREATE UNIQUE INDEX IF NOT EXISTS uq_active_subscription_rider_route
     ON route_subscriptions(route_id, rider_id)
     WHERE status = 'ACTIVE'`
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS commute_ride_instances (
      id UUID PRIMARY KEY,
      route_id UUID NOT NULL REFERENCES recurring_routes(id) ON DELETE CASCADE,
      date DATE NOT NULL,
      seat_availability INTEGER NOT NULL,
      ride_status TEXT NOT NULL DEFAULT 'SCHEDULED',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_route_date UNIQUE (route_id, date)
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_commute_ride_instances_route_id ON commute_ride_instances(route_id)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_commute_ride_instances_date ON commute_ride_instances(date)"
  );

  // Solo-seat columns. A rider can claim a SPECIFIC day's ride
  // exclusively (no other passengers picked up) by paying ~2x the
  // normal seat price. The driver doesn't need to deviate routes —
  // they're going there anyway — so this stays inside the cost-
  // sharing legal model (no LPKP / PSV trigger). When `is_solo` is
  // true, server-side booking logic must:
  //   - reject any new commute_ride_passengers inserts for this
  //     instance (other riders are locked out for that day);
  //   - reveal the driver's phone to `solo_rider_id` the same way
  //     it would to an ACTIVE subscriber on the route.
  // Idempotent ALTERs so existing deploys migrate forward without
  // touching any data.
  await pool.query("ALTER TABLE commute_ride_instances ADD COLUMN IF NOT EXISTS is_solo BOOLEAN NOT NULL DEFAULT FALSE");
  await pool.query("ALTER TABLE commute_ride_instances ADD COLUMN IF NOT EXISTS solo_rider_id TEXT NULL");
  await pool.query("ALTER TABLE commute_ride_instances ADD COLUMN IF NOT EXISTS solo_price_myr INTEGER NULL");
  await pool.query("ALTER TABLE commute_ride_instances ADD COLUMN IF NOT EXISTS solo_payment_id UUID NULL");
  await pool.query("ALTER TABLE commute_ride_instances ADD COLUMN IF NOT EXISTS solo_booked_at TIMESTAMPTZ NULL");
  // Partial index so the "is this ride still solo-available?" lookup
  // doesn't scan every instance, only the small set already flagged.
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_commute_ride_instances_solo ON commute_ride_instances(solo_rider_id) WHERE is_solo = TRUE"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS commute_ride_passengers (
      id UUID PRIMARY KEY,
      instance_id UUID NOT NULL REFERENCES commute_ride_instances(id) ON DELETE CASCADE,
      rider_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'CONFIRMED',
      CONSTRAINT uq_instance_rider UNIQUE (instance_id, rider_id)
    )
  `);
  // Idempotent migration for installations created before the column existed.
  await pool.query(
    `ALTER TABLE commute_ride_passengers
       ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'CONFIRMED'`
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_commute_ride_passengers_instance_id ON commute_ride_passengers(instance_id)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_commute_ride_passengers_rider_id ON commute_ride_passengers(rider_id)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_threads (
      id UUID PRIMARY KEY,
      route_id UUID NULL REFERENCES recurring_routes(id) ON DELETE SET NULL,
      title TEXT NOT NULL,
      last_message TEXT NOT NULL DEFAULT '',
      unread_count INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_chat_threads_route_id ON chat_threads(route_id)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_chat_threads_updated_at ON chat_threads(updated_at DESC)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_participants (
      thread_id UUID NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL,
      unread_count INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_chat_participant UNIQUE (thread_id, user_id)
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_chat_participants_user ON chat_participants(user_id)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_messages (
      id UUID PRIMARY KEY,
      thread_id UUID NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
      sender TEXT NOT NULL,
      text TEXT NOT NULL,
      timestamp_ms BIGINT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_chat_messages_thread_id ON chat_messages(thread_id)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_chat_messages_timestamp_ms ON chat_messages(timestamp_ms)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS notifications (
      id UUID PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      route_id TEXT NULL,
      subscription_id TEXT NULL,
      ride_instance_id TEXT NULL,
      read_at TIMESTAMPTZ NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_notifications_user ON notifications(user_id, created_at DESC)"
  );

  // Live ride locations — driver-side breadcrumbs the rider's
  // LiveTripView consumes via SSE. Latest row per ride wins; we keep
  // the historical trail so we can backfill the driver's actual
  // path on the receipt + drive-quality reviews. Pruned by a
  // separate cron (not implemented yet) once the ride completes.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ride_locations (
      ride_id      TEXT NOT NULL,
      driver_id    TEXT NOT NULL,
      lat          DOUBLE PRECISION NOT NULL,
      lng          DOUBLE PRECISION NOT NULL,
      heading      DOUBLE PRECISION NULL,
      speed_mps    DOUBLE PRECISION NULL,
      recorded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_ride_locations_ride_recent ON ride_locations(ride_id, recorded_at DESC)"
  );

  // Safety alerts — every SOS the rider triggers persists here for
  // the on-call queue. Notification-side dispatch (Twilio /
  // PagerDuty) reads this table; the iOS side posts the row + opens
  // the system SMS composer in parallel, so help moves without
  // waiting for the dispatch loop.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS safety_alerts (
      id           UUID PRIMARY KEY,
      user_id      TEXT NOT NULL,
      ride_id      TEXT NULL,
      route_id     TEXT NULL,
      lat          DOUBLE PRECISION NULL,
      lng          DOUBLE PRECISION NULL,
      message      TEXT NOT NULL DEFAULT '',
      status       TEXT NOT NULL DEFAULT 'OPEN',
      acknowledged_by TEXT NULL,
      acknowledged_at TIMESTAMPTZ NULL,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_safety_alerts_open ON safety_alerts(status, created_at DESC)"
  );

  // APNs device registrations. One row per token (the natural unique
  // key) — a device only ever maps to ONE user at a time. If the user
  // logs out and someone else logs in, we reassign user_id on the
  // existing row rather than creating a duplicate. Previously the PK
  // was (user_id, apns_token) which let an attacker who learned a
  // victim's APNs token register it under their own account and
  // receive the victim's push notifications.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS push_devices (
      user_id     TEXT NOT NULL,
      apns_token  TEXT NOT NULL,
      platform    TEXT NOT NULL DEFAULT 'iOS',
      locale      TEXT NULL,
      app_version TEXT NULL,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, apns_token)
    )
  `);
  // Migration: tighten the PK to `apns_token` alone. Idempotent —
  // a CHECK on pg_indexes lets us skip the rewrite on subsequent boots.
  // Step 1: collapse duplicates (same apns_token under multiple users)
  //         to a single row keyed by most-recent last_seen_at.
  // Step 2: swap the PK.
  const hasOldPk = await pool.query(`
    SELECT 1 FROM pg_indexes
     WHERE schemaname = 'public'
       AND tablename = 'push_devices'
       AND indexname = 'push_devices_pkey'
       AND indexdef LIKE '%(user_id, apns_token)%'
     LIMIT 1
  `);
  if (hasOldPk.rowCount > 0) {
    await pool.query(`
      DELETE FROM push_devices a
       USING push_devices b
       WHERE a.apns_token = b.apns_token
         AND a.last_seen_at < b.last_seen_at
    `);
    // For any remaining ties (rare) keep an arbitrary row.
    await pool.query(`
      DELETE FROM push_devices a
       USING push_devices b
       WHERE a.apns_token = b.apns_token
         AND a.last_seen_at = b.last_seen_at
         AND a.ctid < b.ctid
    `);
    await pool.query("ALTER TABLE push_devices DROP CONSTRAINT push_devices_pkey");
    await pool.query("ALTER TABLE push_devices ADD PRIMARY KEY (apns_token)");
  }

  // KYC document storage. Until the env-configured S3 bucket is set
  // up, we accept multipart uploads and persist the bytes locally
  // under `KYC_STORAGE_DIR`. The server returns a `voygo://kyc/<id>`
  // URI that the existing kyc_documents row stores in storage_url.
  // When real S3 is configured, the same upload endpoint flips to
  // returning `s3://bucket/key` and the iOS side doesn't change.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS kyc_uploads (
      id           UUID PRIMARY KEY,
      user_id      TEXT NOT NULL,
      kind         TEXT NOT NULL,
      content_type TEXT NOT NULL,
      byte_size    BIGINT NOT NULL,
      storage_uri  TEXT NOT NULL,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_kyc_uploads_user ON kyc_uploads(user_id, created_at DESC)"
  );

  // Stripe Connect account linkage — driver-side. `stripe_account_id`
  // is set after the driver completes the Express onboarding flow;
  // payouts are gated on `payouts_enabled` which the Stripe webhook
  // flips on `account.updated` once the bank account is verified.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS driver_stripe_accounts (
      driver_id           TEXT PRIMARY KEY,
      stripe_account_id   TEXT NULL,
      onboarding_url      TEXT NULL,
      payouts_enabled     BOOLEAN NOT NULL DEFAULT FALSE,
      details_submitted   BOOLEAN NOT NULL DEFAULT FALSE,
      created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  // Route requests — riders flag interest in a corridor that nobody
  // is currently serving. Drivers see "12 people want Air Itam →
  // Bayan Lepas" as a strong signal to spin up that route. Closes
  // the cold-start liquidity gap: search returns 0, rider posts an
  // interest, the system tracks demand.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS route_requests (
      id              UUID PRIMARY KEY,
      rider_id        TEXT NOT NULL,
      origin          TEXT NOT NULL,
      destination     TEXT NOT NULL,
      origin_lat      DOUBLE PRECISION NULL,
      origin_lng      DOUBLE PRECISION NULL,
      dest_lat        DOUBLE PRECISION NULL,
      dest_lng        DOUBLE PRECISION NULL,
      preferred_time  TEXT NULL,
      days_of_week    JSONB NOT NULL DEFAULT '{}'::jsonb,
      notes           TEXT NOT NULL DEFAULT '',
      status          TEXT NOT NULL DEFAULT 'OPEN',
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query("CREATE INDEX IF NOT EXISTS ix_route_requests_rider ON route_requests(rider_id, created_at DESC)");
  await pool.query("CREATE INDEX IF NOT EXISTS ix_route_requests_status ON route_requests(status, created_at DESC)");

  // Route favorites — saved-for-later list. Lets riders compare a few
  // routes before subscribing or come back to one they liked.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS route_favorites (
      route_id    UUID NOT NULL REFERENCES recurring_routes(id) ON DELETE CASCADE,
      rider_id    TEXT NOT NULL,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (route_id, rider_id)
    )
  `);
  await pool.query("CREATE INDEX IF NOT EXISTS ix_route_favorites_rider ON route_favorites(rider_id, created_at DESC)");

  // Legacy plate/colour columns on `recurring_routes`. Replaced by
  // `users.plate_number` / `users.car_color` / `users.car_model` so
  // vehicle identity is driver-owned and not per-route (see
  // loadRouteContexts JOIN). Dropping the columns here is the
  // defense-in-depth half of the fix: even if a future code path
  // tried to write to them, there's nothing to write to.
  // IF EXISTS makes the drop idempotent.
  await pool.query("ALTER TABLE recurring_routes DROP COLUMN IF EXISTS plate_number");
  await pool.query("ALTER TABLE recurring_routes DROP COLUMN IF EXISTS car_color");

  // Saved searches — rider's daily commute query. Persist on the
  // server so it's available across devices (the iOS side mirrors
  // to UserDefaults for fast first-paint).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS commute_saved_searches (
      rider_id           TEXT PRIMARY KEY,
      origin_label       TEXT NOT NULL,
      destination_label  TEXT NOT NULL,
      origin_lat         DOUBLE PRECISION NULL,
      origin_lng         DOUBLE PRECISION NULL,
      dest_lat           DOUBLE PRECISION NULL,
      dest_lng           DOUBLE PRECISION NULL,
      earliest_time      TEXT NOT NULL DEFAULT '06:30',
      latest_time        TEXT NOT NULL DEFAULT '09:00',
      days_of_week       JSONB NOT NULL DEFAULT '{}'::jsonb,
      max_price_myr      INTEGER NULL,
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  // Long-haul: one-off inter-city trips. Orthogonal to recurring_routes
  // — riders book a single seat for a specific datetime rather than
  // subscribing to a weekday cadence. Drivers post these as
  // need-arises (going home for the weekend, festival travel) so the
  // schema is intentionally lean: no days_of_week, no pickup_points
  // (rider coordinates pickup via the driver_phone the route DTO
  // already exposes).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS long_haul_trips (
      id                 UUID PRIMARY KEY,
      driver_id          TEXT NOT NULL,
      origin             TEXT NOT NULL,
      destination        TEXT NOT NULL,
      depart_at          TIMESTAMPTZ NOT NULL,
      seats_total        INTEGER NOT NULL,
      seats_available    INTEGER NOT NULL,
      price_per_seat_myr INTEGER NOT NULL,
      status             TEXT NOT NULL DEFAULT 'OPEN',
      notes              TEXT NOT NULL DEFAULT '',
      created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_lh_trips_search ON long_haul_trips(depart_at, status)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_lh_trips_driver ON long_haul_trips(driver_id, depart_at DESC)"
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS long_haul_bookings (
      id          UUID PRIMARY KEY,
      trip_id     UUID NOT NULL REFERENCES long_haul_trips(id) ON DELETE CASCADE,
      rider_id    TEXT NOT NULL,
      seats       INTEGER NOT NULL,
      status      TEXT NOT NULL DEFAULT 'CONFIRMED',
      payment_id  UUID NULL,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_lh_booking_rider UNIQUE (trip_id, rider_id)
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_lh_bookings_rider ON long_haul_bookings(rider_id, created_at DESC)"
  );

  // Telemetry — best-effort funnel events. Append-only, fire-and-forget
  // from the client, so we tolerate missing user_id and free-form props.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS telemetry_events (
      id           BIGSERIAL PRIMARY KEY,
      user_id      TEXT NULL,
      session_id   TEXT NULL,
      name         TEXT NOT NULL,
      props        JSONB NOT NULL DEFAULT '{}'::jsonb,
      app_version  TEXT NULL,
      platform     TEXT NULL,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_telemetry_events_name ON telemetry_events(name, created_at DESC)"
  );
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_telemetry_events_user ON telemetry_events(user_id, created_at DESC)"
  );
}

module.exports = { initSchema };
