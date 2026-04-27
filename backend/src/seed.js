const { randomUUID } = require("crypto");
const { createRoute, createSubscription } = require("./repository");
const { generateRideInstances } = require("./generation");

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function addDays(dateIso, days) {
  const date = new Date(`${dateIso}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

async function seedDefaultChatThread(pool) {
  const existingThread = await pool.query("SELECT id FROM chat_threads LIMIT 1");
  if (existingThread.rows.length > 0) {
    return;
  }

  const routeRes = await pool.query(
    `SELECT id, driver_name
     FROM recurring_routes
     ORDER BY created_at ASC
     LIMIT 1`
  );
  if (routeRes.rows.length === 0) {
    return;
  }

  const route = routeRes.rows[0];
  const title = `${route.driver_name || "Driver"} - Morning Commute`;
  const threadId = randomUUID();
  const initialMessages = [
    { sender: "OTHER", text: "Morning! Pickup at Kota Damansara MRT works for you?" },
    { sender: "ME", text: "Yes, that works. See you at 8:15 AM." },
    { sender: "OTHER", text: "Great, drive safe and see you soon." }
  ];
  const nowMs = Date.now();

  await pool.query(
    `INSERT INTO chat_threads (id, route_id, title, last_message, unread_count)
     VALUES ($1, $2, $3, $4, 0)`,
    [threadId, route.id, title, initialMessages[2].text]
  );
  for (let i = 0; i < initialMessages.length; i += 1) {
    const message = initialMessages[i];
    await pool.query(
      `INSERT INTO chat_messages (id, thread_id, sender, text, timestamp_ms)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        randomUUID(),
        threadId,
        message.sender,
        message.text,
        nowMs - (initialMessages.length - i) * 60_000
      ]
    );
  }
}

async function seedIfEmpty(pool) {
  const existsRes = await pool.query(
    "SELECT id FROM recurring_routes LIMIT 1"
  );
  if (existsRes.rows.length > 0) {
    await seedDefaultChatThread(pool);
    return;
  }

  await pool.query(
    `INSERT INTO driver_reliability (
      driver_id, on_time_rate, cancellation_rate, repeat_riders, average_rating
    ) VALUES
      ('driver-1', 0.95, 0.03, 20, 4.8),
      ('driver-2', 0.90, 0.05, 12, 4.6)
    ON CONFLICT (driver_id) DO NOTHING`
  );

  const weekdays = {
    monday: true,
    tuesday: true,
    wednesday: true,
    thursday: true,
    friday: true,
    saturday: false,
    sunday: false
  };

  const route1Id = await createRoute(pool, {
    driverId: "driver-1",
    driverName: "Aina Rahman",
    startLocation: "Damansara",
    endLocation: "KLCC",
    pickupPoints: [
      {
        label: "Kota Damansara MRT",
        clusterId: "cluster-damansara",
        lat: 3.1502,
        lng: 101.5939
      },
      {
        label: "Mutiara Damansara",
        clusterId: "cluster-damansara",
        lat: 3.1565,
        lng: 101.6085
      },
      {
        label: "TTDI MRT",
        clusterId: "cluster-ttdi",
        lat: 3.1363,
        lng: 101.6304
      },
      {
        label: "Masjid Jamek Hub",
        clusterId: "cluster-central",
        lat: 3.149,
        lng: 101.6967
      }
    ],
    dropPoints: [
      {
        label: "KLCC Office Park",
        clusterId: "cluster-klcc",
        lat: 3.1571,
        lng: 101.7123
      },
      {
        label: "Mid Valley Offices",
        clusterId: "cluster-midvalley",
        lat: 3.1183,
        lng: 101.6787
      }
    ],
    departureTime: "08:15:00",
    daysOfWeek: weekdays,
    seatCount: 3,
    pricePerSeat: 8,
    carType: "SEDAN",
    activeStatus: "ACTIVE"
  });

  await createRoute(pool, {
    driverId: "driver-2",
    driverName: "Wei Jian Tan",
    startLocation: "Putrajaya",
    endLocation: "Mid Valley",
    pickupPoints: [
      {
        label: "Putrajaya Sentral",
        clusterId: "cluster-putra",
        lat: 2.9291,
        lng: 101.6967
      }
    ],
    dropPoints: [
      {
        label: "Mid Valley Offices",
        clusterId: "cluster-midvalley",
        lat: 3.1183,
        lng: 101.6787
      },
      {
        label: "Cerdas Tech Hub",
        clusterId: "cluster-cerdas",
        lat: 3.088,
        lng: 101.689
      }
    ],
    departureTime: "08:00:00",
    daysOfWeek: weekdays,
    seatCount: 4,
    pricePerSeat: 7,
    carType: "EV",
    activeStatus: "ACTIVE"
  });

  await createRoute(pool, {
    driverId: "driver-3",
    driverName: "Siti Rahman",
    startLocation: "Damansara",
    endLocation: "Penang",
    pickupPoints: [
      {
        label: "Kota Damansara MRT",
        clusterId: "cluster-damansara",
        lat: 3.1502,
        lng: 101.5939
      },
      {
        label: "KL Sentral",
        clusterId: "cluster-klsentral",
        lat: 3.134,
        lng: 101.6869
      },
      {
        label: "TBS Kuala Lumpur",
        clusterId: "cluster-tbs",
        lat: 3.0766,
        lng: 101.7114
      }
    ],
    dropPoints: [
      {
        label: "George Town",
        clusterId: "cluster-penang",
        lat: 5.4141,
        lng: 100.3288
      },
      {
        label: "Penang Airport",
        clusterId: "cluster-penang",
        lat: 5.2971,
        lng: 100.277
      },
      {
        label: "Motorola Solutions, Bayan Lepas",
        clusterId: "cluster-bayanlepas",
        lat: 5.28577,
        lng: 100.2688
      }
    ],
    departureTime: "07:45:00",
    daysOfWeek: weekdays,
    seatCount: 2,
    pricePerSeat: 32,
    carType: "SUV",
    activeStatus: "ACTIVE"
  });

  const routePoints = await pool.query(
    `SELECT id, kind
     FROM route_points
     WHERE route_id = $1`,
    [route1Id]
  );
  const pickup = routePoints.rows.find((row) => row.kind === "pickup");
  const drop = routePoints.rows.find((row) => row.kind === "drop");
  if (pickup && drop) {
    const today = todayIso();
    await createSubscription(pool, {
      routeId: route1Id,
      riderId: "rider-1",
      riderName: "Rider One",
      startDate: addDays(today, -2),
      endDate: addDays(today, 30),
      pickupPointId: String(pickup.id),
      dropPointId: String(drop.id),
      status: "ACTIVE"
    });
  }

  await generateRideInstances(pool, todayIso(), 7);

  await seedDefaultChatThread(pool);
}

module.exports = { seedIfEmpty };
