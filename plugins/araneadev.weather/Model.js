// Pure parsing, formatting and unit-conversion helpers for the weather
// widget and its detail popup. Everything here is locale- and Qt-free so it
// can be unit tested under node; the QML owns date formatting through
// Qt.formatDate/Qt.formatDateTime.

/**
 * weather.json holds {"name": ..., "latitude": ..., "longitude": ...} (see
 * omarchy-weather-location, which owns the format). Missing, blank, or
 * unparseable means the location is auto-detected from the IP address.
 * @param {string} raw - the file's raw text
 * @returns {{name: string, latitude: ?number, longitude: ?number}} the
 *   parsed location, or the unset ("", null, null) triple
 */
function parseLocationFile(raw) {
  /** @type {{name: string, latitude: ?number, longitude: ?number}} */
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset

    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null
    }
  } catch (e) {
    return unset
  }
}

/**
 * wttr.in path segment for a configured location: exact coordinates when
 * both are present, the URL-encoded name as a fallback (hand-edited
 * weather.loc files may only carry a name), empty for IP auto-detect.
 * @param {*} location - the configured place name
 * @param {*} latitude - the configured latitude, if any
 * @param {*} longitude - the configured longitude, if any
 * @returns {string} the wttr.in path segment, "" for auto-detect
 */
function wttrLocationQuery(location, latitude, longitude) {
  var lat = parseFloat(String(latitude))
  var lon = parseFloat(String(longitude))
  if (!isNaN(lat) && !isNaN(lon)) return lat + "," + lon

  var name = String(location || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "" : encodeURIComponent(name)
}

/**
 * Open-Meteo geocoding response to suggestion rows for the location picker.
 * @param {string} raw - the response body
 * @returns {Array<{name: string, description: string, latitude: number,
 *   longitude: number}>} the matching places, [] on any parse failure
 */
function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results
    if (!results || !results.length) return []

    var out = []
    for (var i = 0; i < results.length; i++) {
      var r = results[i]
      if (!r || !r.name || r.latitude === undefined || r.longitude === undefined) continue
      var region = [r.admin1, r.country]
        .filter(function (part) {
          return !!part
        })
        .join(", ")
      out.push({
        name: String(r.name),
        description: region,
        latitude: r.latitude,
        longitude: r.longitude
      })
    }
    return out
  } catch (e) {
    return []
  }
}

/**
 * Resolves a location-field commit to the place to persist: the highlighted
 * suggestion when the text matches one, the typed name alone otherwise, or
 * the unset triple for an empty commit (back to auto-detect).
 * @param {string} text - the location field's text
 * @param {*} suggestions - the current geocoding suggestions
 * @param {*} selectedIndex - the highlighted suggestion's index
 * @returns {{name: string, latitude: ?number, longitude: ?number}} the
 *   place to persist
 */
function locationCommit(text, suggestions, selectedIndex) {
  var name = String(text || "").replace(/^\s+|\s+$/g, "")
  if (name === "") return { name: "", latitude: null, longitude: null }

  var choices = suggestions || []
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1))
  var suggestion = choices[index]
  if (suggestion) return suggestion

  return { name: name, latitude: null, longitude: null }
}

/**
 * Whether dateString falls strictly after todayString.
 * @param {string} dateString - an ISO ("yyyy-MM-dd...") date
 * @param {string} todayString - today's "yyyy-MM-dd" date
 * @returns {boolean} true when dateString is in the future
 */
function isFutureForecastDate(dateString, todayString) {
  if (!dateString) return false
  return String(dateString).slice(0, 10) > String(todayString || "")
}

/**
 * Rounds a temperature value to the nearest whole degree.
 * @param {*} value - the raw temperature value
 * @returns {string} the rounded value as text, "" when unset or unparsable
 */
function roundedTemp(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : String(Math.round(n))
}

/**
 * Converts a Celsius value to Fahrenheit.
 * @param {*} value - the Celsius value
 * @returns {(number|string)} the Fahrenheit value, "" when unset or
 *   unparsable
 */
function celsiusToFahrenheit(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : (n * 9) / 5 + 32
}

/**
 * Formats a temperature value with its unit glyph.
 * @param {*} value - the temperature value, already in the active unit
 * @param {boolean} useImperial - true to label it imperial, false for metric
 * @returns {string} the formatted text, "" when value is unset
 */
function formatTemp(value, useImperial) {
  if (value === undefined || value === null || value === "") return ""
  return value + "°" + (useImperial ? "F" : "C")
}

/**
 * Normalizes a unit setting value for comparison.
 * @param {*} value - the raw unit setting
 * @returns {string} the trimmed, lower-cased value
 */
function normalizedUnit(value) {
  return String(value || "")
    .replace(/^\s+|\s+$/g, "")
    .toLowerCase()
}

/**
 * Whether a Qt locale name's country conventionally uses imperial units.
 * @param {string} localeName - the locale name (e.g. "en_US")
 * @returns {boolean} true for the US, Liberia and Myanmar locales
 */
function localeUsesImperial(localeName) {
  var name = String(localeName || "").replace(".", "_")
  return (
    /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name)
  )
}

/**
 * Whether a country name conventionally uses imperial units.
 * @param {string} countryName - the resolved location's country name
 * @returns {?boolean} true/false for a recognized country, null when the
 *   name is empty or not recognized
 */
function countryUsesImperial(countryName) {
  var country = String(countryName || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/[._-]+/g, " ")
    .toLowerCase()
  if (!country) return null
  if (
    country === "us" ||
    country === "usa" ||
    country === "united states" ||
    country === "united states of america"
  )
    return true
  if (country === "liberia" || country === "myanmar" || country === "burma") return true
  return false
}

/**
 * Whether to show imperial units: an explicit unit setting wins, else the
 * resolved location's country, else the system locale.
 * @param {*} unitOverride - the raw unit setting ("metric"/"imperial"/"")
 * @param {string} localeName - the system locale name
 * @param {string} countryName - the resolved location's country name
 * @returns {boolean} true to show imperial units
 */
function shouldUseImperial(unitOverride, localeName, countryName) {
  var unit = normalizedUnit(unitOverride)
  if (unit === "imperial") return true
  if (unit === "metric") return false

  var countryPreference = countryUsesImperial(countryName)
  if (countryPreference !== null) return countryPreference

  return localeUsesImperial(localeName)
}

/**
 * The English weekday name for an ISO date string.
 * @param {string} dateString - an ISO ("yyyy-MM-dd") date
 * @param {?Function} formatter - an optional Date -> string formatter
 * @returns {string} the weekday name, "" when dateString is unset or
 *   unparsable
 */
function dayName(dateString, formatter) {
  if (!dateString) return ""
  var d = new Date(dateString + "T12:00:00")
  if (isNaN(d.getTime())) return ""
  if (formatter) return formatter(d)
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()]
}

/**
 * Up to 3 upcoming forecast days from an open-meteo daily-forecast report.
 * @param {*} dailyForecastReport - the parsed open-meteo response
 * @param {string} todayString - today's "yyyy-MM-dd" date
 * @returns {Array<object>} the upcoming days, each with date, min/max temps
 *   in both units and the weather code; [] when the report has no daily
 *   data
 */
function openMeteoForecastDays(dailyForecastReport, todayString) {
  var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
  if (!daily || !daily.time) return []

  var result = []
  for (var i = 0; i < daily.time.length && result.length < 3; ++i) {
    var date = daily.time[i]
    if (!isFutureForecastDate(date, todayString)) continue

    var maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : ""
    var minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : ""
    result.push({
      date: date,
      maxtempC: roundedTemp(maxC),
      mintempC: roundedTemp(minC),
      maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
      mintempF: roundedTemp(celsiusToFahrenheit(minC)),
      openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
    })
  }
  return result
}

// Open-Meteo bundles current conditions with the daily forecast request and
// answers far faster than wttr.in. Normalize them to wttr's
// current_condition shape so the panel can use either source
// interchangeably. Open-Meteo reports metric (°C, km/h).
/**
 * Normalizes open-meteo's current-conditions block to wttr's
 * current_condition shape.
 * @param {*} dailyForecastReport - the parsed open-meteo response
 * @returns {?object} the normalized current conditions, null when the
 *   report has no usable current temperature
 */
function openMeteoCurrentCondition(dailyForecastReport) {
  var current =
    dailyForecastReport && dailyForecastReport.current ? dailyForecastReport.current : null
  if (!current || current.temperature_2m === undefined || current.temperature_2m === null)
    return null
  return {
    temp_C: roundedTemp(current.temperature_2m),
    temp_F: roundedTemp(celsiusToFahrenheit(current.temperature_2m)),
    FeelsLikeC: roundedTemp(current.apparent_temperature),
    FeelsLikeF: roundedTemp(celsiusToFahrenheit(current.apparent_temperature)),
    windspeedKmph: roundedTemp(current.wind_speed_10m),
    windspeedMiles: roundedTemp(current.wind_speed_10m * 0.621371),
    humidity: roundedTemp(current.relative_humidity_2m),
    openMeteoWeatherCode: current.weather_code,
    isDay: current.is_day
  }
}

/**
 * The hero icon for the current conditions, preferring open-meteo's
 * day/night-aware code over wttr's.
 * @param {*} current - the normalized current conditions
 * @param {string} fallback - the icon to use when current is unset
 * @returns {string} the nerd-font glyph
 */
function currentIcon(current, fallback) {
  if (!current) return fallback || ""
  if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(current.openMeteoWeatherCode, Number(current.isDay) === 0)
  if (current.weatherCode !== undefined && current.weatherCode !== null)
    return iconForCode(current.weatherCode, false)
  return fallback || ""
}

// wttr.in has no day/night flag. Use its icon only to fill an empty initial
// state, never to replace a day/night-aware icon resolved by Open-Meteo.
/**
 * The bar/hero icon to show while open-meteo's day/night-aware icon is not
 * yet resolved.
 * @param {?object} current - wttr's current conditions
 * @param {string} resolvedIcon - open-meteo's already-resolved icon, if any
 * @returns {string} resolvedIcon when set, else wttr's icon for current
 */
function provisionalCurrentIcon(current, resolvedIcon) {
  return resolvedIcon || currentIcon(current, "")
}

/**
 * Whether a weather response completes an in-progress location save: the
 * source that matters depends on whether coordinates are configured.
 * @param {boolean} hasConfiguredCoordinates - true when the location has
 *   coordinates
 * @param {string} source - "open-meteo" or "wttr"
 * @returns {boolean} true when this response is the one the save is
 *   waiting on
 */
function weatherResponseCompletesSave(hasConfiguredCoordinates, source) {
  return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr"
}

/**
 * Up to 3 upcoming forecast days from a wttr.in j1 report.
 * @param {*} report - the parsed wttr.in response
 * @param {string} todayString - today's "yyyy-MM-dd" date
 * @returns {Array<object>} the upcoming days, [] when report has none
 */
function wttrNextForecastDays(report, todayString) {
  var days = report && report.weather ? report.weather : []
  var result = []
  for (var i = 0; i < days.length && result.length < 3; ++i) {
    if (isFutureForecastDate(days[i].date, todayString)) result.push(days[i])
  }
  return result
}

/**
 * The forecast days to show: open-meteo's when available, else wttr's.
 * @param {?object} report - the parsed wttr.in response
 * @param {?object} dailyForecastReport - the parsed open-meteo response
 * @param {string} todayString - today's "yyyy-MM-dd" date
 * @returns {Array<object>} the upcoming forecast days
 */
function buildForecastDays(report, dailyForecastReport, todayString) {
  var days = openMeteoForecastDays(dailyForecastReport, todayString)
  return days.length > 0 ? days : wttrNextForecastDays(report, todayString)
}

/**
 * The bare degree value (no unit letter) for a forecast day.
 * @param {*} day - a forecast day entry
 * @param {string} kind - "max" or "min"
 * @param {boolean} useImperial - true to read the Fahrenheit field
 * @returns {string} the degree text with its unit glyph, "" when day or the
 *   field is unset
 */
function bareTempForDay(day, kind, useImperial) {
  if (!day) return ""
  var v = useImperial
    ? kind === "max"
      ? day.maxtempF
      : day.mintempF
    : kind === "max"
      ? day.maxtempC
      : day.mintempC
  if (v === undefined || v === null || v === "") return ""
  return v + "°"
}

/**
 * The representative icon for a forecast day: open-meteo's daily code when
 * present, else the hourly entry nearest noon from a wttr day.
 * @param {*} day - a forecast day entry
 * @returns {string} the nerd-font glyph, "" when day has no usable code
 */
function dayIcon(day) {
  if (!day) return ""
  if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(day.openMeteoWeatherCode)
  if (!day.hourly || day.hourly.length === 0) return ""

  var best = day.hourly[0]
  var bestDist = 9999
  for (var i = 0; i < day.hourly.length; ++i) {
    var t = parseInt(String(day.hourly[i].time || "0"), 10)
    var dist = Math.abs(t - 1200)
    if (dist < bestDist) {
      bestDist = dist
      best = day.hourly[i]
    }
  }
  return iconForCode(best.weatherCode, false)
}

/**
 * Maps an open-meteo WMO weather code to the nearest wttr.in code, then to
 * its nerd-font glyph.
 * @param {*} code - the open-meteo WMO weather code
 * @param {boolean} [night] - true to use the night variant where one exists
 * @returns {string} the nerd-font glyph
 */
function iconForOpenMeteoCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return iconForCode(113, night)
  if (c === 1 || c === 2) return iconForCode(116, night)
  if (c === 3) return iconForCode(119, night)
  if (c === 45 || c === 48) return iconForCode(143, night)
  if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61)
    return iconForCode(266, night)
  if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82)
    return iconForCode(308, night)
  if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86)
    return iconForCode(338, night)
  if (c === 95 || c === 96 || c === 99) return iconForCode(389, night)
  return iconForCode(119, night)
}

/**
 * Mirrors omarchy-weather-icon's wttr.in code to nerd-font glyph mapping.
 * @param {*} code - the wttr.in weather code
 * @param {boolean} night - true to use the night variant where one exists
 * @returns {string} the nerd-font glyph
 */
function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113:
      return night ? "" : ""
    case 116:
      return night ? "" : ""
    case 119:
    case 122:
      return ""
    case 143:
    case 248:
    case 260:
      return night ? "\ue346" : "\ue313"
    case 176:
    case 263:
    case 353:
      return night ? "" : ""
    case 179:
    case 227:
    case 230:
    case 323:
    case 326:
    case 368:
      return night ? "" : ""
    case 182:
    case 185:
    case 281:
    case 284:
    case 311:
    case 314:
    case 317:
    case 320:
    case 350:
    case 362:
    case 365:
    case 374:
    case 377:
      return ""
    case 200:
    case 386:
    case 389:
    case 392:
    case 395:
      return ""
    case 266:
    case 293:
    case 296:
    case 299:
    case 302:
    case 305:
    case 308:
    case 356:
    case 359:
      return ""
    case 329:
    case 332:
    case 335:
    case 338:
    case 371:
      return ""
    default:
      return ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLocationFile: parseLocationFile,
    wttrLocationQuery: wttrLocationQuery,
    parseGeocodingResults: parseGeocodingResults,
    locationCommit: locationCommit,
    isFutureForecastDate: isFutureForecastDate,
    roundedTemp: roundedTemp,
    celsiusToFahrenheit: celsiusToFahrenheit,
    formatTemp: formatTemp,
    normalizedUnit: normalizedUnit,
    localeUsesImperial: localeUsesImperial,
    countryUsesImperial: countryUsesImperial,
    shouldUseImperial: shouldUseImperial,
    dayName: dayName,
    openMeteoForecastDays: openMeteoForecastDays,
    openMeteoCurrentCondition: openMeteoCurrentCondition,
    currentIcon: currentIcon,
    provisionalCurrentIcon: provisionalCurrentIcon,
    weatherResponseCompletesSave: weatherResponseCompletesSave,
    wttrNextForecastDays: wttrNextForecastDays,
    buildForecastDays: buildForecastDays,
    bareTempForDay: bareTempForDay,
    dayIcon: dayIcon,
    iconForOpenMeteoCode: iconForOpenMeteoCode,
    iconForCode: iconForCode
  }
}
