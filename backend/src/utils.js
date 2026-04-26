const EARTH_RADIUS_M = 6371000.0;

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function haversineDistanceM(lat1, lon1, lat2, lon2) {
  const phi1 = (lat1 * Math.PI) / 180;
  const phi2 = (lat2 * Math.PI) / 180;
  const dPhi = ((lat2 - lat1) * Math.PI) / 180;
  const dLambda = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function scoreCandidate({
  pickupDistanceM,
  reliabilityScore,
  pricePerSeat,
  overlapScore
}) {
  const distanceScore = Math.max(0.0, 1.0 - pickupDistanceM / 5000.0);
  const reliability = clamp(reliabilityScore, 0.0, 1.0);
  const priceScore = clamp(1.0 - pricePerSeat / 100.0, 0.0, 1.0);
  const overlap = clamp(overlapScore, 0.0, 1.0);
  const value =
    distanceScore * 0.35 +
    reliability * 0.35 +
    priceScore * 0.15 +
    overlap * 0.15;
  return Number(value.toFixed(6));
}

const WEEKDAY_KEYS = [
  "sunday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday"
];

function formatDateUtc(date) {
  return date.toISOString().slice(0, 10);
}

function parseDate(dateStr) {
  return new Date(`${dateStr}T00:00:00.000Z`);
}

function addDaysUtc(date, days) {
  const clone = new Date(date.getTime());
  clone.setUTCDate(clone.getUTCDate() + days);
  return clone;
}

function isRouteScheduled(daysOfWeek, targetDate) {
  const key = WEEKDAY_KEYS[targetDate.getUTCDay()];
  return Boolean(daysOfWeek?.[key]);
}

function pickConfirmedRiders(seatCount, subscriptions) {
  return subscriptions
    .filter((entry) => entry.status === "ACTIVE")
    .slice(0, seatCount)
    .map((entry) => entry.riderId);
}

module.exports = {
  addDaysUtc,
  clamp,
  formatDateUtc,
  haversineDistanceM,
  isRouteScheduled,
  parseDate,
  pickConfirmedRiders,
  scoreCandidate
};
