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

  await pool.query(`
    CREATE TABLE IF NOT EXISTS commute_ride_passengers (
      id UUID PRIMARY KEY,
      instance_id UUID NOT NULL REFERENCES commute_ride_instances(id) ON DELETE CASCADE,
      rider_id TEXT NOT NULL,
      CONSTRAINT uq_instance_rider UNIQUE (instance_id, rider_id)
    )
  `);
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

  // APNs device registrations. One row per (user, token) pair so a
  // user can have multiple devices. Removed lazily when a delivery
  // attempt comes back as `BadDeviceToken`.
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
