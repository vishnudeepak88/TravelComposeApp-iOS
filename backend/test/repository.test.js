const assert = require("node:assert/strict");
const test = require("node:test");

const { publicDriverName } = require("../src/repository");

test("publicDriverName never exposes UUID fallbacks", () => {
  assert.equal(
    publicDriverName("0ca6a061-177f-4534-8a7a-9fbf8e16062a"),
    "Voygo Driver"
  );
  assert.equal(publicDriverName("  "), "Voygo Driver");
});

test("publicDriverName prefers canonical display names and normalizes whitespace", () => {
  assert.equal(
    publicDriverName(null, "  Aiman   Rahman  "),
    "Aiman Rahman"
  );
});
