// Presentation helpers for menu labels and stable route ids.

/**
 * Creates a stable route id from display text.
 * @param {*} value - Display text.
 * @returns {string} Stable route id.
 */
function slugify(value) {
  return (
    String(value || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "item"
  )
}

if (typeof module !== "undefined") module.exports = { slugify: slugify }
