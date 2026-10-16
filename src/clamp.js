/**
 * value を [min, max] の範囲に収める。
 * min > max の場合は RangeError を投げる。
 */
function clamp(value, min, max) {
  if (typeof value !== "number" || typeof min !== "number" || typeof max !== "number") {
    throw new TypeError("clamp: all arguments must be numbers");
  }
  if (Number.isNaN(value) || Number.isNaN(min) || Number.isNaN(max)) {
    throw new TypeError("clamp: NaN is not allowed");
  }
  if (min > max) {
    throw new RangeError("clamp: min must be <= max");
  }
  return Math.min(Math.max(value, min), max);
}

module.exports = { clamp };
