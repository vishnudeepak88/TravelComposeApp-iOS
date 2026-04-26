const { randomUUID } = require("crypto");
const {
  addDaysUtc,
  formatDateUtc,
  isRouteScheduled,
  parseDate,
  pickConfirmedRiders
} = require("./utils");

async function generateRideInstances(pool, startDateStr, days) {
  const client = await pool.connect();
  let generated = 0;

  try {
    await client.query("BEGIN");
    const routesRes = await client.query(
      `SELECT id, seat_count, days_of_week
       FROM recurring_routes
       WHERE active_status = TRUE`
    );
    const routes = routesRes.rows;
    const startDate = parseDate(startDateStr);

    for (let offset = 0; offset < days; offset += 1) {
      const currentDate = addDaysUtc(startDate, offset);
      const currentDateStr = formatDateUtc(currentDate);

      for (const route of routes) {
        if (!isRouteScheduled(route.days_of_week, currentDate)) {
          continue;
        }

        const instanceUpsert = await client.query(
          `INSERT INTO commute_ride_instances (
            id, route_id, date, seat_availability, ride_status
          )
          VALUES ($1, $2, $3, $4, 'SCHEDULED')
          ON CONFLICT (route_id, date)
          DO UPDATE SET seat_availability = EXCLUDED.seat_availability
          RETURNING id`,
          [randomUUID(), route.id, currentDateStr, route.seat_count]
        );
        const instanceId = instanceUpsert.rows[0].id;

        await client.query(
          "DELETE FROM commute_ride_passengers WHERE instance_id = $1",
          [instanceId]
        );

        const subsRes = await client.query(
          `SELECT rider_id, status
           FROM route_subscriptions
           WHERE route_id = $1
             AND status = 'ACTIVE'
             AND start_date <= $2
             AND end_date >= $2
           ORDER BY created_at ASC`,
          [route.id, currentDateStr]
        );

        const confirmedRiders = pickConfirmedRiders(
          route.seat_count,
          subsRes.rows.map((row) => ({
            riderId: row.rider_id,
            status: row.status
          }))
        );

        for (const riderId of confirmedRiders) {
          await client.query(
            `INSERT INTO commute_ride_passengers (id, instance_id, rider_id)
             VALUES ($1, $2, $3)
             ON CONFLICT ON CONSTRAINT uq_instance_rider DO NOTHING`,
            [randomUUID(), instanceId, riderId]
          );
        }

        await client.query(
          `UPDATE commute_ride_instances
           SET seat_availability = $2
           WHERE id = $1`,
          [instanceId, route.seat_count - confirmedRiders.length]
        );
        generated += 1;
      }
    }

    await client.query("COMMIT");
    return generated;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

module.exports = { generateRideInstances };
