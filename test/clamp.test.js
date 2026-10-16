const test = require("node:test");
const assert = require("node:assert");
const { clamp } = require("../src/clamp");

test("範囲内の値はそのまま", () => assert.strictEqual(clamp(5, 0, 10), 5));
test("下限未満は min", () => assert.strictEqual(clamp(-1, 0, 10), 0));
test("上限超過は max", () => assert.strictEqual(clamp(11, 0, 10), 10));
test("境界値", () => {
  assert.strictEqual(clamp(0, 0, 10), 0);
  assert.strictEqual(clamp(10, 0, 10), 10);
});
test("min > max は RangeError", () => assert.throws(() => clamp(1, 10, 0), RangeError));
test("数値以外は TypeError", () => assert.throws(() => clamp("1", 0, 10), TypeError));
test("NaN は TypeError", () => assert.throws(() => clamp(NaN, 0, 10), TypeError));
