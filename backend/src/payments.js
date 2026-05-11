// Billplz integration + payment lifecycle.
//
// Mock mode is the default: when BILLPLZ_API_KEY / BILLPLZ_COLLECTION_ID are
// unset, we record payments in our DB and immediately mark them as PAID so
// dev/test flows work end-to-end without provisioning Billplz. When real
// credentials are set, we create a real Billplz bill and rely on the webhook
// to flip status to PAID.

const crypto = require("crypto");
const { config } = require("./config");

const BILLPLZ_TIMEOUT_MS = 8000;

// ---------- Schema ----------

async function ensurePaymentsSchema(pool) {
  // Per-charge record. One subscription typically maps to one payment for
  // the whole tier period (monthly / quarterly upfront). For daily-tier
  // signups we still create one row per charge so receipts roll up cleanly.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS payments (
      id UUID PRIMARY KEY,
      user_id TEXT NOT NULL,
      subscription_id TEXT NULL,
      route_id TEXT NULL,
      amount_myr INTEGER NOT NULL,
      currency TEXT NOT NULL DEFAULT 'MYR',
      status TEXT NOT NULL DEFAULT 'PENDING',
      tier TEXT NOT NULL DEFAULT 'MONTHLY',
      billplz_bill_id TEXT NULL,
      billplz_payment_url TEXT NULL,
      paid_at TIMESTAMPTZ NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_payments_user ON payments(user_id, created_at DESC)"
  );
  await pool.query(
    "CREATE UNIQUE INDEX IF NOT EXISTS ix_payments_billplz ON payments(billplz_bill_id) WHERE billplz_bill_id IS NOT NULL"
  );
  // Subscription reconciliation reads payments by `subscription_id`
  // (e.g. when cancelling a subscription we look up the most recent
  // PAID row to decide refund eligibility). Without this index every
  // such lookup degenerates to a full scan once payments grows.
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_payments_subscription ON payments(subscription_id, created_at DESC) WHERE subscription_id IS NOT NULL"
  );
  // Restrict status to the documented lifecycle so a bug or a
  // tampered webhook can't stamp an arbitrary string. Idempotent —
  // only added when absent and named the same so re-runs are no-ops.
  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'payments_status_check'
      ) THEN
        ALTER TABLE payments
          ADD CONSTRAINT payments_status_check
          CHECK (status IN ('PENDING','PAID','FAILED','REFUNDED','CANCELED'));
      END IF;
    END $$;
  `);
  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'payments_amount_check'
      ) THEN
        ALTER TABLE payments
          ADD CONSTRAINT payments_amount_check
          CHECK (amount_myr >= 0);
      END IF;
    END $$;
  `);

  // Per-driver weekly payout aggregate. Computed by `payouts.js` on demand.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS payouts (
      id UUID PRIMARY KEY,
      driver_id TEXT NOT NULL,
      week_start DATE NOT NULL,
      week_end DATE NOT NULL,
      gross_myr INTEGER NOT NULL DEFAULT 0,
      voygo_fee_myr INTEGER NOT NULL DEFAULT 0,
      penalty_myr INTEGER NOT NULL DEFAULT 0,
      net_myr INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'PENDING',
      paid_at TIMESTAMPTZ NULL,
      bank_last4 TEXT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_payout_driver_week UNIQUE (driver_id, week_start)
    )
  `);
  await pool.query(
    "CREATE INDEX IF NOT EXISTS ix_payouts_driver ON payouts(driver_id, week_start DESC)"
  );
}

// ---------- Billplz HTTP client ----------

async function callBillplz(method, path, body) {
  if (config.billplz.isMockMode) {
    throw new Error("Billplz mock mode is active; refusing to call live API");
  }
  const url = `${config.billplz.baseUrl.replace(/\/$/, "")}${path}`;
  const auth = Buffer.from(`${config.billplz.apiKey}:`).toString("base64");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), BILLPLZ_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method,
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body: body ? new URLSearchParams(body).toString() : undefined,
      signal: controller.signal
    });
    const text = await response.text();
    if (!response.ok) {
      const error = new Error(`Billplz error ${response.status}: ${text}`);
      error.status = response.status;
      throw error;
    }
    return text ? JSON.parse(text) : {};
  } finally {
    clearTimeout(timer);
  }
}

async function createBillplzBill({ amountMyr, name, email, mobile, description, paymentId }) {
  // Billplz amounts are in cents. We round explicitly so RM 8 → 800, RM 8.50 → 850.
  const amountCents = Math.max(100, Math.round(amountMyr * 100));
  const body = {
    collection_id: config.billplz.collectionId,
    email: email || "rider@voygo.my",
    name: name || "Voygo rider",
    amount: String(amountCents),
    description: (description || "Voygo subscription").slice(0, 200),
    callback_url: config.billplz.callbackUrl,
    redirect_url: config.billplz.redirectUrl,
    reference_1_label: "payment_id",
    reference_1: paymentId
  };
  if (mobile) body.mobile = mobile;
  return callBillplz("POST", "/bills", body);
}

// ---------- Webhook signature ----------
//
// Billplz signs callback bodies with HMAC-SHA256 over a sorted concatenation
// of `key|value` pairs. We verify with timing-safe comparison.

function verifyBillplzSignature(body, providedSignature) {
  if (config.billplz.isMockMode) {
    return true; // mock mode trusts the caller
  }
  if (!config.billplz.xSignatureKey || !providedSignature) return false;
  const orderedKeys = Object.keys(body)
    .filter((k) => k !== "x_signature")
    .sort();
  const source = orderedKeys.map((k) => `${k}${body[k]}`).join("|");
  const expected = crypto
    .createHmac("sha256", config.billplz.xSignatureKey)
    .update(source)
    .digest("hex");
  if (expected.length !== providedSignature.length) return false;
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(providedSignature));
}

// ---------- Lifecycle helpers ----------

async function recordPendingPayment(pool, { userId, subscriptionId, routeId, amountMyr, tier }) {
  const id = crypto.randomUUID();
  await pool.query(
    `INSERT INTO payments
       (id, user_id, subscription_id, route_id, amount_myr, status, tier)
       VALUES ($1, $2, $3, $4, $5, 'PENDING', $6)`,
    [id, userId, subscriptionId || null, routeId || null, amountMyr, tier || "MONTHLY"]
  );
  return id;
}

async function attachBillplzBill(pool, paymentId, bill) {
  await pool.query(
    `UPDATE payments
        SET billplz_bill_id = $2, billplz_payment_url = $3
      WHERE id = $1`,
    [paymentId, bill.id, bill.url]
  );
}

async function markPaymentPaid(pool, { billId, paymentId }) {
  // Either input works; one of the two will be present from a webhook,
  // the other from a "force complete in mock mode" path.
  let result;
  if (billId) {
    result = await pool.query(
      `UPDATE payments
          SET status = 'PAID', paid_at = NOW()
        WHERE billplz_bill_id = $1
        RETURNING id, subscription_id, route_id, user_id, amount_myr`,
      [billId]
    );
  } else {
    result = await pool.query(
      `UPDATE payments
          SET status = 'PAID', paid_at = NOW()
        WHERE id = $1
        RETURNING id, subscription_id, route_id, user_id, amount_myr`,
      [paymentId]
    );
  }
  return result.rows[0] || null;
}

async function listUserPayments(pool, userId, limit = 20) {
  const result = await pool.query(
    `SELECT id, subscription_id, route_id, amount_myr, currency, status, tier,
            billplz_payment_url, paid_at, created_at
       FROM payments
      WHERE user_id = $1
      ORDER BY created_at DESC
      LIMIT $2`,
    [userId, limit]
  );
  return result.rows.map((row) => ({
    id: row.id,
    subscriptionId: row.subscription_id,
    routeId: row.route_id,
    amountMyr: row.amount_myr,
    currency: row.currency,
    status: row.status,
    tier: row.tier,
    paymentUrl: row.billplz_payment_url,
    paidAt: row.paid_at,
    createdAt: row.created_at
  }));
}

// ---------- Top-level: charge a subscription ----------

async function chargeSubscription(pool, { userId, subscriptionId, routeId, amountMyr, tier, contact }) {
  const paymentId = await recordPendingPayment(pool, {
    userId,
    subscriptionId,
    routeId,
    amountMyr,
    tier
  });

  if (config.billplz.isMockMode) {
    // Defense-in-depth: config.js already refuses to start in production
    // when Billplz keys are missing, but the mock path is dangerous
    // enough that we double-check here. Better to throw than to mark
    // a real charge PAID without taking the rider's money.
    if (config.isProduction) {
      console.error(
        "[payments] mock-mode reached in production — refusing to mock-pay"
      );
      const err = new Error("payments_unconfigured");
      err.statusCode = 503;
      throw err;
    }
    if (config.isStaging) {
      // Staging is allowed to mock-pay so pre-launch flows work, but
      // we log every charge so the audit trail is unambiguous about
      // which payments were never actually billed.
      console.warn(
        `[payments] STAGING mock-charge: payment ${paymentId} marked PAID without contacting Billplz`
      );
    }
    // Dev only: resolve the payment immediately so the rest of the flow
    // (subscription activation, receipts) works without external IO.
    console.warn(
      `[payments] mock-mode: marking payment ${paymentId} PAID without charging`
    );
    await markPaymentPaid(pool, { paymentId });
    return {
      paymentId,
      status: "PAID",
      paymentUrl: null,
      mockMode: true
    };
  }

  const bill = await createBillplzBill({
    amountMyr,
    name: contact?.name,
    email: contact?.email,
    mobile: contact?.mobile,
    description: `Voygo ${(tier || "monthly").toLowerCase()} subscription`,
    paymentId
  });
  await attachBillplzBill(pool, paymentId, bill);
  return {
    paymentId,
    status: "PENDING",
    paymentUrl: bill.url,
    billId: bill.id,
    mockMode: false
  };
}

module.exports = {
  ensurePaymentsSchema,
  verifyBillplzSignature,
  chargeSubscription,
  markPaymentPaid,
  listUserPayments
};
