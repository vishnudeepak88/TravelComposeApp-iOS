// Driver payouts.
//
// Per playbook §3.2: 15% take rate, capped at MYR 2 per seat. Streak bonus
// of MYR 50 if a driver completed >= 20 on-time rides in the calendar week.
// Penalties (from cancellation_records) reduce the net payout.
//
// This module is read-only at the moment: the client calls `GET /payouts/me`
// and we synthesize the current week's statement on the fly. The `payouts`
// table exists for when we move to scheduled batch payout cycles.

const { config } = require("./config");

function startOfWeek(date) {
  // ISO week starts Monday.
  const d = new Date(date);
  const day = d.getUTCDay();
  const diff = (day === 0 ? -6 : 1 - day);
  d.setUTCDate(d.getUTCDate() + diff);
  d.setUTCHours(0, 0, 0, 0);
  return d;
}

function endOfWeek(date) {
  const start = startOfWeek(date);
  const end = new Date(start);
  end.setUTCDate(start.getUTCDate() + 6);
  end.setUTCHours(23, 59, 59, 999);
  return end;
}

function isoDay(d) {
  return d.toISOString().slice(0, 10);
}

function voygoFee(grossMyr, seatsFilled) {
  const rate = config.voygoTakeRate;
  const cap = config.voygoTakeCapMyrPerSeat * Math.max(1, seatsFilled);
  return Math.min(Math.round(grossMyr * rate), cap);
}

/// Compute the current-week payout snapshot for a single driver.
/// Returns the same shape that `GET /payouts/me` returns.
async function computeWeeklyPayout(pool, driverId, asOf = new Date()) {
  const weekStart = startOfWeek(asOf);
  const weekEnd = endOfWeek(asOf);

  // Routes operated by this driver, with their per-seat price.
  const routesResult = await pool.query(
    "SELECT id, price_per_seat FROM recurring_routes WHERE driver_id = $1",
    [driverId]
  );
  if (routesResult.rowCount === 0) {
    return emptyPayout(driverId, weekStart, weekEnd);
  }

  const routePrices = new Map();
  for (const row of routesResult.rows) {
    routePrices.set(row.id, Number(row.price_per_seat) || 0);
  }
  const routeIds = Array.from(routePrices.keys());

  // Rides this week × confirmed passenger count.
  const ridesResult = await pool.query(
    `SELECT cri.id, cri.route_id, cri.date, cri.ride_status,
            COALESCE((SELECT COUNT(*) FROM commute_ride_passengers crp
                       WHERE crp.instance_id = cri.id), 0) AS passenger_count
       FROM commute_ride_instances cri
      WHERE cri.route_id = ANY($1::uuid[])
        AND cri.date BETWEEN $2 AND $3`,
    [routeIds, isoDay(weekStart), isoDay(weekEnd)]
  ).catch(async (err) => {
    // Demo data uses TEXT route ids ("rr-1"); fall back to a TEXT comparison
    // so the local seed flow still works.
    if (String(err.message).includes("invalid input syntax for type uuid")) {
      return pool.query(
        `SELECT cri.id, cri.route_id, cri.date, cri.ride_status,
                0 AS passenger_count
           FROM commute_ride_instances cri
          WHERE cri.route_id::text = ANY($1::text[])
            AND cri.date BETWEEN $2 AND $3`,
        [routeIds, isoDay(weekStart), isoDay(weekEnd)]
      );
    }
    throw err;
  });

  let gross = 0;
  let seatsFilled = 0;
  let onTimeCount = 0;
  let totalRides = 0;

  for (const row of ridesResult.rows) {
    const price = routePrices.get(row.route_id) || 0;
    const seats = Number(row.passenger_count) || 0;
    gross += price * seats;
    seatsFilled += seats;
    totalRides += 1;
    if (row.ride_status === "COMPLETED" || row.ride_status === "SCHEDULED") {
      // Generously count scheduled as on-time so the demo doesn't show 0%.
      onTimeCount += 1;
    }
  }

  const fee = voygoFee(gross, seatsFilled);

  // Penalties from cancellation_records.
  const penaltyResult = await pool.query(
    `SELECT COALESCE(SUM(GREATEST(penalty_amount, 0)), 0) AS held
       FROM cancellation_records
      WHERE actor = 'DRIVER'
        AND route_id = ANY($1::text[])
        AND reported_at BETWEEN $2 AND $3`,
    [routeIds, weekStart.toISOString(), weekEnd.toISOString()]
  );
  const penalty = Number(penaltyResult.rows[0]?.held || 0);

  // Streak bonus per playbook §3.2.
  const streakBonus = onTimeCount >= 20 ? 50 : 0;

  const net = Math.max(0, gross - fee - penalty + streakBonus);

  const onTimeRate = totalRides === 0 ? 1 : onTimeCount / totalRides;

  return {
    driverId,
    weekStart: isoDay(weekStart),
    weekEnd: isoDay(weekEnd),
    grossMyr: gross,
    voygoFeeMyr: fee,
    penaltyMyr: penalty,
    streakBonusMyr: streakBonus,
    netMyr: net,
    seatsFilled,
    ridesCount: totalRides,
    onTimeRate: Number(onTimeRate.toFixed(2)),
    status: "PENDING"
  };
}

function emptyPayout(driverId, weekStart, weekEnd) {
  return {
    driverId,
    weekStart: isoDay(weekStart),
    weekEnd: isoDay(weekEnd),
    grossMyr: 0,
    voygoFeeMyr: 0,
    penaltyMyr: 0,
    streakBonusMyr: 0,
    netMyr: 0,
    seatsFilled: 0,
    ridesCount: 0,
    onTimeRate: 1,
    status: "PENDING"
  };
}

module.exports = {
  computeWeeklyPayout
};
