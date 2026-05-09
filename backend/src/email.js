const nodemailer = require("nodemailer");

// Email-based OTP delivery for staging / pilot testing.
//
// Useful when Twilio isn't set up but the team needs the OTP to land
// somewhere reachable (a Gmail inbox they all share, or the
// developer's own). Production should still use SMS — this is a
// staging convenience, gated by config.isProduction in server.js.
//
// Configure via env (Gmail SMTP example):
//   SMTP_HOST=smtp.gmail.com
//   SMTP_PORT=587
//   SMTP_USER=youraccount@gmail.com
//   SMTP_PASS=app-specific-password   # NOT your real Gmail password
//   OTP_FROM_EMAIL="Voygo <youraccount@gmail.com>"
//   OTP_TO_EMAIL=tester@gmail.com     # where the OTP gets sent
//
// Gmail's SMTP requires 2FA on the account + an app-specific
// password (https://myaccount.google.com/apppasswords). The regular
// password won't work.

function emailConfigured() {
  return Boolean(
    process.env.SMTP_HOST &&
    process.env.SMTP_USER &&
    process.env.SMTP_PASS &&
    process.env.OTP_TO_EMAIL
  );
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
    }
  });
  return _transporter;
}

async function sendOtpEmail({ phone, code, expiresAt }) {
  if (!emailConfigured()) {
    return { ok: false, reason: "unconfigured" };
  }
  try {
    const expiresMin = Math.max(1, Math.round((new Date(expiresAt).getTime() - Date.now()) / 60_000));
    await transporter().sendMail({
      from: process.env.OTP_FROM_EMAIL || process.env.SMTP_USER,
      to: process.env.OTP_TO_EMAIL,
      subject: `Voygo verification code: ${code}`,
      // Plain text + minimal HTML — keeps the message out of spam
      // filters that flag image-heavy or boilerplate-laden bodies.
      text: `Voygo verification code: ${code}\nExpires in ${expiresMin} minutes.\nRequested for ${phone}.`,
      html: `
        <p style="font-family:-apple-system,system-ui,sans-serif;font-size:14px">
          <strong>Voygo verification code</strong><br/>
          <span style="font-size:28px;letter-spacing:4px;font-family:Menlo,monospace">${code}</span><br/>
          <span style="color:#666">Expires in ${expiresMin} minutes. Requested for ${phone}.</span>
        </p>`
    });
    return { ok: true };
  } catch (err) {
    console.warn(`[email] sendOtpEmail failed: ${err.message}`);
    return { ok: false, reason: "send_failed", error: err.message };
  }
}

module.exports = { sendOtpEmail, emailConfigured };
