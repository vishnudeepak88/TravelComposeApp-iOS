const assert = require("node:assert/strict");
const test = require("node:test");
const crypto = require("crypto");

const {
  buildKycObjectKey,
  buildKycStorageUri,
  kycObjectStorageConfigured,
  resolveS3Target,
  signedPutRequest
} = require("../src/objectStorage");

const storageConfig = {
  kycStorage: {
    bucket: "voygo-kyc",
    region: "ap-southeast-1",
    endpoint: "https://storage.example.com",
    accessKeyId: "test-access-key",
    secretAccessKey: "test-secret-key",
    forcePathStyle: true
  }
};

test("KYC object storage reports whether required credentials are present", () => {
  assert.equal(kycObjectStorageConfigured({ kycStorage: {} }), false);
  assert.equal(kycObjectStorageConfigured(storageConfig), true);
});

test("KYC object keys are namespaced per user and sanitized", () => {
  assert.equal(
    buildKycObjectKey({
      userId: "user/with spaces",
      id: "doc:123",
      ext: "JPG"
    }),
    "kyc/user_with_spaces/doc_123.jpg"
  );
});

test("S3-compatible target uses path-style endpoint when configured", () => {
  const target = resolveS3Target("kyc/user-1/doc-1.jpg", storageConfig);
  assert.equal(target.protocol, "https:");
  assert.equal(target.hostname, "storage.example.com");
  assert.equal(target.path, "/voygo-kyc/kyc/user-1/doc-1.jpg");
  assert.equal(buildKycStorageUri("kyc/user-1/doc-1.jpg", storageConfig), "s3://voygo-kyc/kyc/user-1/doc-1.jpg");
});

test("signed PUT request includes AWS v4 headers without exposing the secret", () => {
  const body = Buffer.from("sample-image-bytes");
  const req = signedPutRequest({
    key: "kyc/user-1/doc-1.jpg",
    body,
    contentType: "image/jpeg",
    now: new Date("2026-05-11T00:00:00.000Z")
  }, storageConfig);

  assert.equal(req.method, "PUT");
  assert.equal(req.path, "/voygo-kyc/kyc/user-1/doc-1.jpg");
  assert.equal(req.headers["Content-Type"], "image/jpeg");
  assert.equal(req.headers["Content-Length"], body.length);
  assert.equal(
    req.headers["X-Amz-Content-Sha256"],
    crypto.createHash("sha256").update(body).digest("hex")
  );
  assert.match(req.headers.Authorization, /^AWS4-HMAC-SHA256 Credential=test-access-key\/20260511\/ap-southeast-1\/s3\/aws4_request/);
  assert.match(req.headers.Authorization, /SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date/);
  assert.equal(req.headers.Authorization.includes("test-secret-key"), false);
});
