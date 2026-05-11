const crypto = require("crypto");
const https = require("https");
const http = require("http");
const { URL } = require("url");
const { config } = require("./config");

function hmac(key, value, encoding) {
  return crypto.createHmac("sha256", key).update(value).digest(encoding);
}

function sha256(value, encoding = "hex") {
  return crypto.createHash("sha256").update(value).digest(encoding);
}

function encodeKeyPath(key) {
  return String(key)
    .split("/")
    .map((part) => encodeURIComponent(part))
    .join("/");
}

function sanitizeKeyPart(value) {
  return String(value || "")
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .slice(0, 120);
}

function kycObjectStorageConfigured(rootConfig = config) {
  const kycStorage = rootConfig.kycStorage || {};
  return Boolean(
    kycStorage.bucket &&
    kycStorage.region &&
    kycStorage.accessKeyId &&
    kycStorage.secretAccessKey
  );
}

function buildKycObjectKey({ userId, id, ext }) {
  const safeUserId = sanitizeKeyPart(userId);
  const safeId = sanitizeKeyPart(id);
  const safeExt = sanitizeKeyPart(ext || "bin").toLowerCase() || "bin";
  return `kyc/${safeUserId}/${safeId}.${safeExt}`;
}

function buildKycStorageUri(key, rootConfig = config) {
  const kycStorage = rootConfig.kycStorage || {};
  return `s3://${kycStorage.bucket}/${key}`;
}

function resolveS3Target(key, rootConfig = config) {
  const kycStorage = rootConfig.kycStorage || {};
  const encodedKey = encodeKeyPath(key);

  if (kycStorage.endpoint) {
    const endpoint = new URL(kycStorage.endpoint);
    const basePath = endpoint.pathname.replace(/\/+$/, "");
    const pathStyle = kycStorage.forcePathStyle !== false;
    return {
      protocol: endpoint.protocol,
      hostname: endpoint.hostname,
      port: endpoint.port,
      path: pathStyle
        ? `${basePath}/${encodeURIComponent(kycStorage.bucket)}/${encodedKey}`
        : `${basePath}/${encodedKey}`,
      host: endpoint.host
    };
  }

  const hostname = kycStorage.forcePathStyle
    ? `s3.${kycStorage.region}.amazonaws.com`
    : `${kycStorage.bucket}.s3.${kycStorage.region}.amazonaws.com`;
  const path = kycStorage.forcePathStyle
    ? `/${encodeURIComponent(kycStorage.bucket)}/${encodedKey}`
    : `/${encodedKey}`;

  return {
    protocol: "https:",
    hostname,
    port: "",
    path,
    host: hostname
  };
}

function signingKey(secretAccessKey, date, region) {
  const kDate = hmac(`AWS4${secretAccessKey}`, date);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, "s3");
  return hmac(kService, "aws4_request");
}

function formatAmzDate(date = new Date()) {
  const iso = date.toISOString().replace(/[:-]|\.\d{3}/g, "");
  return {
    amzDate: iso,
    shortDate: iso.slice(0, 8)
  };
}

function signedPutRequest({ key, body, contentType, now = new Date() }, rootConfig = config) {
  const kycStorage = rootConfig.kycStorage || {};
  if (!kycObjectStorageConfigured(rootConfig)) {
    throw new Error("KYC object storage is not configured");
  }

  const payloadHash = sha256(body);
  const { amzDate, shortDate } = formatAmzDate(now);
  const target = resolveS3Target(key, rootConfig);
  const canonicalHeaders = [
    `content-type:${contentType}`,
    `host:${target.host}`,
    `x-amz-content-sha256:${payloadHash}`,
    `x-amz-date:${amzDate}`
  ].join("\n") + "\n";
  const signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date";
  const canonicalRequest = [
    "PUT",
    target.path,
    "",
    canonicalHeaders,
    signedHeaders,
    payloadHash
  ].join("\n");
  const scope = `${shortDate}/${kycStorage.region}/s3/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    sha256(canonicalRequest)
  ].join("\n");
  const signature = hmac(signingKey(kycStorage.secretAccessKey, shortDate, kycStorage.region), stringToSign, "hex");

  return {
    protocol: target.protocol,
    hostname: target.hostname,
    port: target.port,
    path: target.path,
    method: "PUT",
    headers: {
      Authorization: `AWS4-HMAC-SHA256 Credential=${kycStorage.accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`,
      "Content-Length": body.length,
      "Content-Type": contentType,
      Host: target.host,
      "X-Amz-Content-Sha256": payloadHash,
      "X-Amz-Date": amzDate
    }
  };
}

function uploadKycObject({ key, body, contentType }, rootConfig = config) {
  const requestOptions = signedPutRequest({ key, body, contentType }, rootConfig);
  const transport = requestOptions.protocol === "http:" ? http : https;

  return new Promise((resolve, reject) => {
    const req = transport.request(requestOptions, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(buildKycStorageUri(key, rootConfig));
          return;
        }
        const detail = Buffer.concat(chunks).toString("utf8").slice(0, 500);
        reject(new Error(`KYC object upload failed with status ${res.statusCode}: ${detail}`));
      });
    });
    req.on("error", reject);
    req.setTimeout(15000, () => {
      req.destroy(new Error("KYC object upload timed out"));
    });
    req.end(body);
  });
}

module.exports = {
  buildKycObjectKey,
  buildKycStorageUri,
  kycObjectStorageConfigured,
  resolveS3Target,
  signedPutRequest,
  uploadKycObject
};
