const path = require("path");
const dotenv = require("dotenv");

dotenv.config({ path: path.resolve(process.cwd(), ".env") });

function normalizeDatabaseUrl(value) {
  if (!value) {
    return "postgresql://voygo:voygo@localhost:5432/voygo";
  }
  return value.replace(/^postgresql\+psycopg2:\/\//, "postgresql://");
}

const isProduction = process.env.NODE_ENV === "production";

// ---------------------------------------------------------------------------
// Production fail-fast guards.
//
// In production we refuse to start with insecure or ambiguous config. Better
// to crash at boot with a clear error than to silently run with a default
// JWT secret, dev OTP echo, or the Billplz mock-mode that auto-marks every
// payment PAID. Each guard collects errors first so a misconfigured deploy
// gets the full punch list in one log line, not one fix per restart.
// ---------------------------------------------------------------------------
const productionErrors = [];

if (isProduction && !process.env.AUTH_JWT_SECRET) {
  productionErrors.push(
    "AUTH_JWT_SECRET must be set in production (refusing to use the dev default)"
  );
}

const rawAuthDevMode = String(process.env.AUTH_DEV_MODE || "").toLowerCase() === "true";
if (isProduction && rawAuthDevMode) {
  productionErrors.push(
    "AUTH_DEV_MODE=true is forbidden in production"
  );
}

const billplzApiKey = process.env.BILLPLZ_API_KEY || "";
const billplzCollectionId = process.env.BILLPLZ_COLLECTION_ID || "";
const billplzXSignatureKey = process.env.BILLPLZ_X_SIGNATURE_KEY || "";

if (isProduction) {
  if (!billplzApiKey) {
    productionErrors.push("BILLPLZ_API_KEY must be set in production");
  }
  if (!billplzCollectionId) {
    productionErrors.push("BILLPLZ_COLLECTION_ID must be set in production");
  }
  if (!billplzXSignatureKey) {
    productionErrors.push(
      "BILLPLZ_X_SIGNATURE_KEY must be set in production (callback signature verification)"
    );
  }
}

if (productionErrors.length > 0) {
  console.error("[config] Refusing to start in production:");
  for (const err of productionErrors) {
    console.error(`  - ${err}`);
  }
  // Throwing here makes `node src/server.js` exit with a non-zero status
  // before binding the port, so a bad deploy fails the health check
  // immediately instead of serving traffic with unsafe defaults.
  throw new Error("invalid production configuration: " + productionErrors.join("; "));
}

// Dev-only fallback for the JWT secret. Reachable only when NODE_ENV !==
// "production" — the production guard above blocks every other path.
const authJwtSecret =
  process.env.AUTH_JWT_SECRET ||
  "voygo-dev-only-change-me-in-production-32bytes-minimum";

// authDevMode is the gate that controls dev OTP echo, console-logged OTP
// codes, and any other developer affordance. We OR it with !isProduction
// so local `node src/server.js` keeps the convenient dev flow, but in
// production it is hard-pinned false regardless of the env var.
const authDevMode = isProduction ? false : (rawAuthDevMode || true);

// Billplz mock-mode is similarly hard-pinned off in production. The
// production guards above already require the keys to be set, so this
// is a defense-in-depth check the payments code can rely on.
const billplzIsMockMode = isProduction ? false : !(billplzApiKey && billplzCollectionId);

const config = {
  isProduction,
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
  authDevMode,

  // Driver economics — playbook §3.2.
  voygoTakeRate: Number(process.env.VOYGO_TAKE_RATE || 0.15),
  voygoTakeCapMyrPerSeat: Number(process.env.VOYGO_TAKE_CAP_MYR || 2),

  // Billplz hosted-checkout integration. Mock mode is dev-only; the
  // production guards above prevent it from ever running with a
  // missing apiKey/collectionId.
  billplz: {
    apiKey: billplzApiKey,
    collectionId: billplzCollectionId,
    xSignatureKey: billplzXSignatureKey,
    baseUrl: process.env.BILLPLZ_BASE_URL || "https://www.billplz-sandbox.com/api/v3",
    callbackUrl: process.env.BILLPLZ_CALLBACK_URL || "https://voygo-ios-api.onrender.com/payments/billplz/callback",
    redirectUrl: process.env.BILLPLZ_REDIRECT_URL || "voygo://payments/return",
    isMockMode: billplzIsMockMode
  }
};

module.exports = { config };
