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

const billplzApiKey = process.env.BILLPLZ_API_KEY || "";
const billplzCollectionId = process.env.BILLPLZ_COLLECTION_ID || "";

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
    process.env.NODE_ENV !== "production",

  // Driver economics — playbook §3.2.
  voygoTakeRate: Number(process.env.VOYGO_TAKE_RATE || 0.15),
  voygoTakeCapMyrPerSeat: Number(process.env.VOYGO_TAKE_CAP_MYR || 2),

  // Billplz hosted-checkout integration. When apiKey/collectionId are unset
  // we fall back to mock mode (PAID immediately) so dev flows keep working.
  billplz: {
    apiKey: billplzApiKey,
    collectionId: billplzCollectionId,
    xSignatureKey: process.env.BILLPLZ_X_SIGNATURE_KEY || "",
    baseUrl: process.env.BILLPLZ_BASE_URL || "https://www.billplz-sandbox.com/api/v3",
    callbackUrl: process.env.BILLPLZ_CALLBACK_URL || "https://voygo-ios-api.onrender.com/payments/billplz/callback",
    redirectUrl: process.env.BILLPLZ_REDIRECT_URL || "voygo://payments/return",
    isMockMode: !(billplzApiKey && billplzCollectionId)
  }
};

module.exports = { config };
