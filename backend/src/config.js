const path = require("path");
const dotenv = require("dotenv");

dotenv.config({ path: path.resolve(process.cwd(), ".env") });

function normalizeDatabaseUrl(value) {
  if (!value) {
    return "postgresql://voygo:voygo@localhost:5432/voygo";
  }
  return value.replace(/^postgresql\+psycopg2:\/\//, "postgresql://");
}

const config = {
  port: Number(process.env.PORT || 8000),
  databaseUrl: normalizeDatabaseUrl(process.env.DATABASE_URL),
  openAiApiKey: process.env.OPENAI_API_KEY || "",
  osrmBaseUrl: process.env.OSRM_BASE_URL || "https://router.project-osrm.org",
  nominatimBaseUrl:
    process.env.NOMINATIM_BASE_URL || "https://nominatim.openstreetmap.org"
};

module.exports = { config };
