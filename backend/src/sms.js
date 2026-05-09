const https = require("https");

// SMS provider — Twilio REST. We don't pull in the Twilio Node SDK to
// keep the dependency surface small; the REST call is a single POST.
//
// Configure via env:
//   TWILIO_ACCOUNT_SID    — required
//   TWILIO_AUTH_TOKEN     — required
//   TWILIO_FROM_NUMBER    — E.164 sender (e.g. +12025550123) OR
//   TWILIO_MESSAGING_SID  — Messaging Service SID (preferred for MY)
//
// In production, if env is unset the call returns { ok: false, reason: "unconfigured" }
// and the caller is expected to fail loudly. In dev (AUTH_DEV_MODE / NODE_ENV !== production)
// we no-op silently and let the dev-OTP code fall through.

function smsConfigured() {
  return Boolean(
    process.env.TWILIO_ACCOUNT_SID &&
    process.env.TWILIO_AUTH_TOKEN &&
    (process.env.TWILIO_FROM_NUMBER || process.env.TWILIO_MESSAGING_SID)
  );
}

function isProd() {
  return process.env.NODE_ENV === "production";
}

function sendSms({ to, body }) {
  return new Promise((resolve) => {
    if (!smsConfigured()) {
      // In production this is a config bug — the caller should refuse to
      // continue. In dev we just no-op.
      resolve({ ok: false, reason: "unconfigured" });
      return;
    }
    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const params = new URLSearchParams({ To: to, Body: body });
    if (process.env.TWILIO_MESSAGING_SID) {
      params.set("MessagingServiceSid", process.env.TWILIO_MESSAGING_SID);
    } else {
      params.set("From", process.env.TWILIO_FROM_NUMBER);
    }
    const payload = params.toString();
    const auth = Buffer.from(`${accountSid}:${authToken}`).toString("base64");

    const req = https.request(
      {
        hostname: "api.twilio.com",
        path: `/2010-04-01/Accounts/${accountSid}/Messages.json`,
        method: "POST",
        headers: {
          "Authorization": `Basic ${auth}`,
          "Content-Type": "application/x-www-form-urlencoded",
          "Content-Length": Buffer.byteLength(payload)
        },
        timeout: 10_000
      },
      (resp) => {
        let chunks = "";
        resp.on("data", (c) => { chunks += c; });
        resp.on("end", () => {
          if (resp.statusCode && resp.statusCode >= 200 && resp.statusCode < 300) {
            resolve({ ok: true });
          } else {
            console.warn(`[sms] twilio ${resp.statusCode}: ${chunks.slice(0, 200)}`);
            resolve({ ok: false, reason: "provider_error", status: resp.statusCode });
          }
        });
      }
    );
    req.on("error", (err) => {
      console.warn(`[sms] twilio error: ${err.message}`);
      resolve({ ok: false, reason: "network" });
    });
    req.on("timeout", () => {
      req.destroy(new Error("timeout"));
    });
    req.write(payload);
    req.end();
  });
}

module.exports = { sendSms, smsConfigured, isProd };
