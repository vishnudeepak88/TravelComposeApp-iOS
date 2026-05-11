// In-process rate limiter and request-id middleware.
//
// Closes Engineering gap #4 from the playbook: the search-on-keystroke
// pattern combined with no rate limiting will burn money fast on third-party
// geocoding and run up DB cost. We use a token-bucket per (ip + path) keyed
// in memory. For multi-instance deploys this should move to Redis — call
// site stays the same.

class TokenBucket {
  constructor(capacity, refillPerSecond) {
    this.capacity = capacity;
    this.refillPerSecond = refillPerSecond;
    this.tokens = capacity;
    this.lastRefill = Date.now();
  }

  tryConsume(amount = 1) {
    const now = Date.now();
    const elapsedMs = now - this.lastRefill;
    if (elapsedMs > 0) {
      this.tokens = Math.min(
        this.capacity,
        this.tokens + (elapsedMs / 1000) * this.refillPerSecond
      );
      this.lastRefill = now;
    }
    if (this.tokens >= amount) {
      this.tokens -= amount;
      return true;
    }
    return false;
  }
}

const buckets = new Map();

function bucketKey(req, scope) {
  const ip = req.ip || req.socket.remoteAddress || "unknown";
  return `${scope}:${ip}`;
}

/// Reasonable default: 60 requests / minute per IP across all routes.
function rateLimitGlobal(req, res, next) {
  const key = bucketKey(req, "global");
  let bucket = buckets.get(key);
  if (!bucket) {
    bucket = new TokenBucket(60, 1.0); // 60 burst, 1/sec sustained
    buckets.set(key, bucket);
  }
  if (!bucket.tryConsume()) {
    res.status(429).json({ detail: "Too many requests" });
    return;
  }
  next();
}

/// Strict limit on search/autocomplete-style keystroke endpoints.
function rateLimitSearch(req, res, next) {
  const key = bucketKey(req, "search");
  let bucket = buckets.get(key);
  if (!bucket) {
    bucket = new TokenBucket(10, 10 / 60); // 10 burst, 10/minute sustained
    buckets.set(key, bucket);
  }
  if (!bucket.tryConsume()) {
    res.status(429).json({ detail: "Slow down — too many search requests" });
    return;
  }
  next();
}

/// Auth-related endpoints: lower ceiling, since OTP abuse is a known vector.
function rateLimitAuth(req, res, next) {
  const key = bucketKey(req, "auth");
  let bucket = buckets.get(key);
  if (!bucket) {
    bucket = new TokenBucket(5, 5 / 60); // 5 burst, 5/minute sustained
    buckets.set(key, bucket);
  }
  if (!bucket.tryConsume()) {
    res.status(429).json({ detail: "Too many auth attempts" });
    return;
  }
  next();
}

/// Write endpoints (favorites toggle, route requests, chat send, saved
/// search PUT). Higher ceiling than auth but tight enough to block a
/// runaway client from spamming the DB. Keyed by IP — once we have
/// a sticky user id at this layer we can flip to per-user bucketing.
function rateLimitWrite(req, res, next) {
  const key = bucketKey(req, "write");
  let bucket = buckets.get(key);
  if (!bucket) {
    bucket = new TokenBucket(30, 30 / 60); // 30 burst, 30/min sustained
    buckets.set(key, bucket);
  }
  if (!bucket.tryConsume()) {
    res.status(429).json({ detail: "Too many writes — slow down" });
    return;
  }
  next();
}

module.exports = {
  rateLimitGlobal,
  rateLimitSearch,
  rateLimitAuth,
  rateLimitWrite
};
