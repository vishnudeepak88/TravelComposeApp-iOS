const nodemailer = require("nodemailer");
const https = require("https");

// Email-based OTP delivery.
//
// Two transport options:
//   1. RESEND (HTTPS API) — preferred. Works on Render's free plan
//      because outbound port 443 isn't blocked. Sign up at resend.com,
//      grab the API key, set:
//          RESEND_API_KEY=re_xxxxxxxx
//          OTP_FROM_EMAIL=Voygo <onboarding@resend.dev>   (sandbox sender)
//          OTP_TO_EMAIL=tester@gmail.com
//      The sandbox sender works without DNS verification but the
//      "to" address must be the verified Resend account email.
//      For production, verify your own domain in Resend and use a
//      from address on that domain.
//
//   2. SMTP (Gmail / etc.) — only works if outbound port 587 isn't
//      blocked by your host. Render's free plan blocks SMTP, so this
//      path is for local dev or paid Render plans. Set:
//          SMTP_HOST=smtp.gmail.com
//          SMTP_PORT=587
//          SMTP_USER=youraccount@gmail.com
//          SMTP_PASS=app-specific-password
//          OTP_FROM_EMAIL=Voygo <youraccount@gmail.com>
//          OTP_TO_EMAIL=tester@gmail.com
//      Gmail SMTP requires 2FA + an app password
//      (https://myaccount.google.com/apppasswords). Regular passwords
//      are rejected.
//
// When both are configured, Resend wins. The OTP route only tries one;
// no point burning 8s on SMTP if the API call already worked.

function resendConfigured() {
  return Boolean(
    process.env.RESEND_API_KEY &&
    process.env.OTP_FROM_EMAIL &&
    process.env.OTP_TO_EMAIL
  );
}

function smtpConfigured() {
  return Boolean(
    process.env.SMTP_HOST &&
    process.env.SMTP_USER &&
    process.env.SMTP_PASS &&
    process.env.OTP_TO_EMAIL
  );
}

function emailConfigured() {
  return resendConfigured() || smtpConfigured();
}

function activeProvider() {
  if (resendConfigured()) return "resend";
  if (smtpConfigured())   return "smtp";
  return null;
}

let _transporter = null;
function transporter() {
  if (_transporter) return _transporter;
  _transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    // Most providers (including Gmail on 587) want STARTTLS, which
    // nodemailer auto-negotiates when `secure: false`. Set
    // SMTP_SECURE=true for SMTPS on 465.
    secure: String(process.env.SMTP_SECURE || "").toLowerCase() === "true",
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS
    },
    // Tight timeouts — nodemailer's defaults are 2+ minutes which
    // means a misconfigured SMTP host (wrong port, app password not
    // activated yet, firewall) will hang the whole HTTP request the
    // OTP endpoint is trying to satisfy. We'd rather fall through
    // to dev-echo / 502 in seconds than block the user.
    connectionTimeout: 3000,   // TCP connect — Gmail typically <500ms
    greetingTimeout:   3000,   // SMTP banner
    socketTimeout:     8000    // any single socket op (auth + send)
  });
  return _transporter;
}

/// Race a promise against a hard wall-clock timeout. The underlying
/// SMTP work may keep running in the background, but the caller
/// returns immediately with a clear `timeout` reason so the OTP
/// endpoint can fall through to its next delivery channel.
function withTimeout(promise, ms, label) {
  return new Promise((resolve) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      resolve({ ok: false, reason: "timeout", label });
    }, ms);
    promise.then(
      (value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ ok: false, reason: "send_failed", error: err?.message || String(err) });
      }
    );
  });
}

const _diag = {
  provider:   null,
  lastVerify: null,
  lastSend:   null
};

function _captureError(err) {
  if (!err) return { code: "UNKNOWN", message: "unknown error" };
  return {
    code:         err.code         || "UNKNOWN",
    responseCode: err.responseCode || null,
    command:      err.command      || null,
    message:      String(err.message || err).slice(0, 500)
  };
}

// ─── Resend HTTPS path ─────────────────────────────────────────────────
//
// Single POST to api.resend.com/emails. We use Node's built-in https
// rather than the @resend/node SDK to keep the dep surface lean —
// the request shape is small enough to inline.

function resendSend({ from, to, subject, text, html }) {
  return new Promise((resolve) => {
    const payload = JSON.stringify({ from, to, subject, text, html });
    const req = https.request(
      {
        hostname: "api.resend.com",
        path: "/emails",
        method: "POST",
        headers: {
          "Authorization": `Bearer ${process.env.RESEND_API_KEY}`,
          "Content-Type":  "application/json",
          "Content-Length": Buffer.byteLength(payload)
        },
        timeout: 8000
      },
      (resp) => {
        let chunks = "";
        resp.on("data", (c) => { chunks += c; });
        resp.on("end", () => {
          if (resp.statusCode && resp.statusCode >= 200 && resp.statusCode < 300) {
            resolve({ ok: true });
            return;
          }
          let err = { name: "ResendError", message: chunks.slice(0, 300) };
          try { err = { ...err, ...JSON.parse(chunks) }; } catch (_e) { /* keep raw */ }
          resolve({
            ok: false,
            reason: "send_failed",
            code: err.name || `HTTP_${resp.statusCode}`,
            responseCode: resp.statusCode,
            command: "POST /emails",
            message: err.message
          });
        });
      }
    );
    req.on("error", (err) => {
      resolve({ ok: false, reason: "send_failed", ..._captureError(err) });
    });
    req.on("timeout", () => req.destroy(new Error("resend_timeout")));
    req.write(payload);
    req.end();
  });
}

async function sendOtpEmail({ phone, code, expiresAt }) {
  if (!emailConfigured()) {
    return { ok: false, reason: "unconfigured" };
  }
  const expiresMin = Math.max(1, Math.round((new Date(expiresAt).getTime() - Date.now()) / 60_000));
  const subject = `Voygo verification code: ${code}`;
  const text = `Voygo verification code: ${code}\nExpires in ${expiresMin} minutes.\nRequested for ${phone}.`;
  const html = `
      <p style="font-family:-apple-system,system-ui,sans-serif;font-size:14px">
        <strong>Voygo verification code</strong><br/>
        <span style="font-size:28px;letter-spacing:4px;font-family:Menlo,monospace">${code}</span><br/>
        <span style="color:#666">Expires in ${expiresMin} minutes. Requested for ${phone}.</span>
      </p>`;
  const from = process.env.OTP_FROM_EMAIL || process.env.SMTP_USER;
  const to   = process.env.OTP_TO_EMAIL;

  let result;
  if (resendConfigured()) {
    _diag.provider = "resend";
    result = await resendSend({ from, to, subject, text, html });
  } else {
    _diag.provider = "smtp";
    const sendPromise = transporter().sendMail({ from, to, subject, text, html }).then(
      ()  => ({ ok: true }),
      (err) => ({ ok: false, reason: "send_failed", ..._captureError(err) })
    );
    result = await withTimeout(sendPromise, 8_000, "smtp_send");
  }

  if (!result.ok) {
    console.warn(`[email] sendOtpEmail (${_diag.provider}) ${result.reason}: ${result.message || result.error || ""}`);
    _diag.lastSend = { ok: false, provider: _diag.provider, ...result, at: new Date().toISOString() };
  } else {
    _diag.lastSend = { ok: true, provider: _diag.provider, at: new Date().toISOString() };
  }
  return result;
}

/// Verify the active provider is reachable + authenticated. Resend's
/// API has no formal verify endpoint, so we send a HEAD-equivalent
/// (an unauthenticated GET to /domains, which 401s on bad keys and
/// 200s on good ones) — confirms the API key works without sending
/// a real email.
async function verifyEmailTransport() {
  if (!emailConfigured()) {
    const result = { ok: false, reason: "unconfigured" };
    _diag.lastVerify = { ...result, at: new Date().toISOString() };
    return result;
  }
  let result;
  if (resendConfigured()) {
    _diag.provider = "resend";
    result = await resendVerifyApiKey();
  } else {
    _diag.provider = "smtp";
    const verifyPromise = transporter().verify().then(
      ()  => ({ ok: true }),
      (err) => ({ ok: false, reason: "verify_failed", ..._captureError(err) })
    );
    result = await withTimeout(verifyPromise, 6_000, "smtp_verify");
  }
  _diag.lastVerify = { ...result, provider: _diag.provider, at: new Date().toISOString() };
  return result;
}

function resendVerifyApiKey() {
  return new Promise((resolve) => {
    const req = https.request(
      {
        hostname: "api.resend.com",
        path: "/domains",
        method: "GET",
        headers: {
          "Authorization": `Bearer ${process.env.RESEND_API_KEY}`
        },
        timeout: 5000
      },
      (resp) => {
        // Drain so Node frees the socket; we only care about status.
        resp.on("data", () => {});
        resp.on("end", () => {
          if (resp.statusCode === 200) {
            resolve({ ok: true });
          } else {
            resolve({
              ok: false,
              reason: "verify_failed",
              code: `HTTP_${resp.statusCode}`,
              responseCode: resp.statusCode,
              command: "GET /domains",
              message: resp.statusCode === 401
                ? "Invalid Resend API key"
                : `Resend returned ${resp.statusCode}`
            });
          }
        });
      }
    );
    req.on("error", (err) => {
      resolve({ ok: false, reason: "verify_failed", ..._captureError(err) });
    });
    req.on("timeout", () => req.destroy(new Error("resend_timeout")));
    req.end();
  });
}

function emailDiagnostics() {
  return {
    configured: emailConfigured(),
    activeProvider: activeProvider(),
    env: {
      // Resend
      RESEND_API_KEY: Boolean(process.env.RESEND_API_KEY),
      // SMTP
      SMTP_HOST:      Boolean(process.env.SMTP_HOST),
      SMTP_PORT:      process.env.SMTP_PORT || null,
      SMTP_SECURE:    process.env.SMTP_SECURE || null,
      SMTP_USER:      process.env.SMTP_USER ? maskEmail(process.env.SMTP_USER) : null,
      SMTP_PASS:      Boolean(process.env.SMTP_PASS),
      // Shared
      OTP_FROM_EMAIL: process.env.OTP_FROM_EMAIL ? maskEmail(process.env.OTP_FROM_EMAIL) : null,
      OTP_TO_EMAIL:   process.env.OTP_TO_EMAIL   ? maskEmail(process.env.OTP_TO_EMAIL)   : null
    },
    lastVerify: _diag.lastVerify,
    lastSend:   _diag.lastSend
  };
}

function maskEmail(value) {
  const m = String(value).match(/<?([^@<>\s]+)@([^>\s]+)>?/);
  if (!m) return "<set>";
  const [, local, domain] = m;
  return `${local[0] || "?"}***@${domain}`;
}

module.exports = {
  sendOtpEmail,
  emailConfigured,
  activeProvider,
  verifyEmailTransport,
  emailDiagnostics
};
