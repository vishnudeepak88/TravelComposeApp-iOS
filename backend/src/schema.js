async function initSchema(pool) {
  await pool.query("CREATE EXTENSION IF NOT EXISTS postgis");

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
}

module.exports = { initSchema };
