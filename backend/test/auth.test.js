const assert = require("node:assert/strict");
const test = require("node:test");

let queryImpl = async () => ({ rows: [], rowCount: 0 });
const dbPath = require.resolve("../src/db");
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: {
    pool: {
      query: (...args) => queryImpl(...args)
    }
  }
};

const { signJwt, verifyJwt, requireAuth } = require("../src/auth");

function reqWithToken(token) {
  return {
    get(name) {
      return name.toLowerCase() === "authorization" ? `Bearer ${token}` : "";
    }
  };
}

function resRecorder() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    }
  };
}

test("JWT round-trips and expires", () => {
  const token = signJwt({ sub: "user-1", phone: "+60123456789" }, "secret", 60);
  assert.equal(verifyJwt(token, "secret").sub, "user-1");

  const expired = signJwt({ sub: "user-1" }, "secret", -1);
  assert.equal(verifyJwt(expired, "secret"), null);
});

test("requireAuth rejects a deleted account", async () => {
  const token = signJwt({ sub: "11111111-1111-4111-8111-111111111111" });
  queryImpl = async () => ({
    rows: [{
      id: "11111111-1111-4111-8111-111111111111",
      phone: "+60123456789",
      deleted_at: new Date("2026-05-11T00:00:00Z")
    }],
    rowCount: 1
  });

  const req = reqWithToken(token);
  const res = resRecorder();
  let nextCalled = false;
  await requireAuth(req, res, () => { nextCalled = true; });

  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 410);
  assert.equal(res.body.detail, "account_deleted");
});

test("requireAuth hydrates active user from the database", async () => {
  const token = signJwt({ sub: "22222222-2222-4222-8222-222222222222", phone: "+60000000000" });
  queryImpl = async () => ({
    rows: [{
      id: "22222222-2222-4222-8222-222222222222",
      phone: "+60129876543",
      deleted_at: null
    }],
    rowCount: 1
  });

  const req = reqWithToken(token);
  const res = resRecorder();
  let nextCalled = false;
  await requireAuth(req, res, () => { nextCalled = true; });

  assert.equal(nextCalled, true);
  assert.deepEqual(req.user, {
    id: "22222222-2222-4222-8222-222222222222",
    phone: "+60129876543"
  });
});
