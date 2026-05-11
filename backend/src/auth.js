const crypto = require("crypto");
const { config } = require("./config");
const { pool } = require("./db");

function base64urlEncode(input) {
  const buf = input instanceof Buffer ? input : Buffer.from(input);
  return buf
    .toString("base64")
    .replace(/=+$/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function base64urlDecode(input) {
  let padded = input.replace(/-/g, "+").replace(/_/g, "/");
  while (padded.length % 4) padded += "=";
  return Buffer.from(padded, "base64");
}

function signJwt(payload, secret = config.authJwtSecret, ttlSeconds = config.authJwtTtlSeconds) {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const body = { ...payload, iat: now, exp: now + ttlSeconds };
  const encodedHeader = base64urlEncode(JSON.stringify(header));
  const encodedBody = base64urlEncode(JSON.stringify(body));
  const data = `${encodedHeader}.${encodedBody}`;
  const sigBuf = crypto.createHmac("sha256", secret).update(data).digest();
  return `${data}.${base64urlEncode(sigBuf)}`;
}

function verifyJwt(token, secret = config.authJwtSecret) {
  if (typeof token !== "string") return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [encodedHeader, encodedBody, providedSig] = parts;
  const data = `${encodedHeader}.${encodedBody}`;
  const expectedSigBuf = crypto.createHmac("sha256", secret).update(data).digest();
  let providedSigBuf;
  try {
    providedSigBuf = base64urlDecode(providedSig);
  } catch {
    return null;
  }
  if (providedSigBuf.length !== expectedSigBuf.length) return null;
  if (!crypto.timingSafeEqual(providedSigBuf, expectedSigBuf)) return null;
  try {
    const body = JSON.parse(base64urlDecode(encodedBody).toString("utf8"));
    if (typeof body.exp === "number" && Math.floor(Date.now() / 1000) >= body.exp) {
      return null;
    }
    return body;
  } catch {
    return null;
  }
}

async function requireAuth(req, res, next) {
  const header = req.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  const token = match ? match[1].trim() : null;
  if (!token) {
    res.status(401).json({ detail: "missing token" });
    return;
  }
  const payload = verifyJwt(token);
  if (!payload || !payload.sub) {
    res.status(401).json({ detail: "invalid or expired token" });
    return;
  }
  const userId = String(payload.sub);
  try {
    const userRes = await pool.query(
      "SELECT id, phone, deleted_at FROM users WHERE id = $1 LIMIT 1",
      [userId]
    );
    const user = userRes.rows[0];
    if (!user) {
      res.status(401).json({ detail: "user not found" });
      return;
    }
    if (user.deleted_at) {
      res.status(410).json({
        detail: "account_deleted",
        deletedAt: new Date(user.deleted_at).toISOString()
      });
      return;
    }
    req.user = { id: userId, phone: user.phone || payload.phone || "" };
    next();
  } catch (err) {
    next(err);
  }
}

function generateOtp() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, "0");
}

function hashOtp(code, salt) {
  return crypto
    .createHash("sha256")
    .update(`${salt}:${code}`)
    .digest("hex");
}

function normalizePhone(value) {
  if (!value) return "";
  const digits = String(value).trim().replace(/[^\d+]/g, "");
  if (!digits) return "";
  if (digits.startsWith("+")) return digits;
  // Default to Malaysia (+60) when no country code is provided
  const local = digits.replace(/^0+/, "");
  return `+60${local}`;
}

module.exports = {
  signJwt,
  verifyJwt,
  requireAuth,
  generateOtp,
  hashOtp,
  normalizePhone
};
