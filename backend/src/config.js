const path = require("path");
const dotenv = require("dotenv");

dotenv.config({ path: path.resolve(process.cwd(), ".env") });

function normalizeDatabaseUrl(value) {
  if (!value) {
    return "postgresql://voygo:voygo@localhost:5432/voygo";
  }
  return value.replace(/^postgresql\+psycopg2:\/\//, "postgresql://");
}

const authJwtSecret =
  process.env.AUTH_JWT_SECRET ||
  "voygo-dev-only-change-me-in-production-32bytes-minimum";
if (
  process.env.NODE_ENV === "production" &&
  !process.env.AUTH_JWT_SECRET
) {
  console.warn(
    "[config] AUTH_JWT_SECRET is not set in production — tokens will use the unsafe default"
  );
}

const config = {
  port: Number(process.env.PORT || 8000),
  databaseUrl: normalizeDatabaseUrl(process.env.DATABASE_URL),
  openAiApiKey: process.env.OPENAI_API_KEY || "",
  osrmBaseUrl: process.env.OSRM_BASE_URL || "https://router.project-osrm.org",
  nominatimBaseUrl:
    process.env.NOMINATIM_BASE_URL || "https://nominatim.openstreetmap.org",
  authJwtSecret,
  authJwtTtlSeconds: Number(process.env.AUTH_JWT_TTL_SECONDS || 60 * 60 * 24 * 30),
  otpTtlSeconds: Number(process.env.AUTH_OTP_TTL_SECONDS || 5 * 60),
  otpMaxAttempts: Number(process.env.AUTH_OTP_MAX_ATTEMPTS || 5),
  authDevMode:
    String(process.env.AUTH_DEV_MODE || "").toLowerCase() === "true" ||
    process.env.NODE_ENV !== "production"
};

module.exports = { config };
