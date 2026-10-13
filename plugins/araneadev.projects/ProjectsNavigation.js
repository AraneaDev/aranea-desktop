/** @typedef {{id:string,path:string,branch?:string|null}} NavigationCheckout */
/** @typedef {{id:string,name:string,lastCheckoutId:string,checkouts:NavigationCheckout[]}} NavigationProject */
/** @typedef {{lastProjectId?:string|null,pinnedProjectIds?:string[],visitedAt?:{[key:string]:number}}} NavigationState */
/** @typedef {{id:string,name:string,path:string,branch:string,pinned:boolean,visitedAt:number}} NavigationRow */

/**
 * Build searchable project rows without changing registered or frozen identities.
 * Display the selected checkout only; search includes all registered checkouts.
 * Pins precede visits, with case-insensitive names and IDs breaking ties.
 * Frozen matches retain their order and new matches append in ranked order.
 * @param {NavigationProject[]|null} projects Registered projects.
 * @param {NavigationState|null} navigation Optional saved navigation metadata.
 * @param {string} query Search text.
 * @param {string[]|null} frozenIds Current result identities, in navigation order.
 * @returns {NavigationRow[]} Matching rows with stable identity and order.
 */
function rows(projects, navigation, query, frozenIds) {
  var saved = navigation || {}
  var pins = saved.pinnedProjectIds || []
  var visits = saved.visitedAt || {}
  var search = (query || "").trim().toLowerCase()
  var matching = (projects || [])
    .filter(function (project) {
      return (
        !search ||
        project.name.toLowerCase().indexOf(search) >= 0 ||
        (project.checkouts || []).some(function (checkout) {
          return (
            checkout.path.toLowerCase().indexOf(search) >= 0 ||
            (checkout.branch || "").toLowerCase().indexOf(search) >= 0
          )
        })
      )
    })
    .map(function (project) {
      var checkout = (project.checkouts || []).filter(function (candidate) {
        return candidate.id === project.lastCheckoutId
      })[0]
      return {
        id: project.id,
        name: project.name,
        path: checkout ? checkout.path : "",
        branch: checkout ? checkout.branch || "" : "",
        pinned: pins.indexOf(project.id) >= 0,
        visitedAt: visits[project.id] || 0
      }
    })
  matching.sort(function (a, b) {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
    if (a.visitedAt !== b.visitedAt) return b.visitedAt - a.visitedAt
    var aName = a.name.toLowerCase(),
      bName = b.name.toLowerCase()
    if (aName !== bName) return aName < bName ? -1 : 1
    return a.id === b.id ? 0 : a.id < b.id ? -1 : 1
  })
  /** @type {NavigationRow[]} */
  var result = []
  ;(frozenIds || []).forEach(function (id) {
    var row = matching.filter(function (candidate) {
      return candidate.id === id
    })[0]
    if (
      row &&
      !result.some(function (candidate) {
        return candidate.id === id
      })
    )
      result.push(row)
  })
  matching.forEach(function (row) {
    if (
      !result.some(function (candidate) {
        return candidate.id === row.id
      })
    )
      result.push(row)
  })
  return result
}

/**
 * Restore only a registered project, preferring the explicit requested identity.
 * No fallback selection or repository execution occurs when both IDs are absent.
 * @param {NavigationProject[]|null} projects Registered projects.
 * @param {string|null} requestedId Explicit destination.
 * @param {string|null} savedId Last inspected project.
 * @returns {string} Registered project identity or the empty list destination.
 */
function restoreSelection(projects, requestedId, savedId) {
  var ids = (projects || []).map(function (project) {
    return project.id
  })
  return ids.indexOf(requestedId) >= 0 ? requestedId : ids.indexOf(savedId) >= 0 ? savedId : ""
}

if (typeof module !== "undefined") module.exports = { rows, restoreSelection }
