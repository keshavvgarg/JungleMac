import Foundation

private func clamp(_ v: Double) -> Double { v < 0 ? 0 : v > 1 ? 1 : v }
private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
  let t = clamp((x - a) / (b - a))
  return t * t * (3 - 2 * t)
}

struct DayState {
  var name: String
  var night, dawn, day, dusk, fireflies, moon: Double
  var sunX, sunY, sunVisible: Double
  /// Color wash over the whole scene: r, g, b (0-255) and alpha.
  var wash: (Double, Double, Double, Double)
}

private struct Key {
  var h: Double
  var name: String
  var night, dawn, day, dusk, moon, sunX, sunY, sunVisible: Double
}

private let KEYS: [Key] = [
  Key(h: 0, name: "Night", night: 1, dawn: 0, day: 0, dusk: 0, moon: 1, sunX: 220, sunY: 560, sunVisible: 0),
  Key(h: 4.8, name: "Night", night: 0.92, dawn: 0.15, day: 0, dusk: 0, moon: 0.7, sunX: 260, sunY: 520, sunVisible: 0),
  Key(h: 6.3, name: "Dawn", night: 0.18, dawn: 1, day: 0.15, dusk: 0, moon: 0, sunX: 420, sunY: 430, sunVisible: 0.85),
  Key(h: 8.2, name: "Daylight", night: 0, dawn: 0.15, day: 1, dusk: 0, moon: 0, sunX: 700, sunY: 300, sunVisible: 1),
  Key(h: 12.5, name: "Daylight", night: 0, dawn: 0, day: 1, dusk: 0, moon: 0, sunX: 1080, sunY: 250, sunVisible: 1),
  Key(h: 16.2, name: "Daylight", night: 0, dawn: 0, day: 0.85, dusk: 0.25, moon: 0, sunX: 1320, sunY: 330, sunVisible: 1),
  Key(h: 18.3, name: "Dusk", night: 0.22, dawn: 0, day: 0.1, dusk: 1, moon: 0, sunX: 1460, sunY: 470, sunVisible: 0.75),
  Key(h: 20.2, name: "Night", night: 0.95, dawn: 0, day: 0, dusk: 0.12, moon: 0.85, sunX: 1520, sunY: 560, sunVisible: 0),
  Key(h: 24, name: "Night", night: 1, dawn: 0, day: 0, dusk: 0, moon: 1, sunX: 220, sunY: 560, sunVisible: 0),
]

private func mixKey(_ a: Key, _ b: Key, _ t: Double) -> DayState {
  func n(_ k: KeyPath<Key, Double>) -> Double { a[keyPath: k] + (b[keyPath: k] - a[keyPath: k]) * t }
  let night = n(\.night), dawn = n(\.dawn), dusk = n(\.dusk)
  let wash: (Double, Double, Double, Double) =
    night > 0.08 || dusk > 0.08 || dawn > 0.08
    ? (
      (16 + dusk * 170 + dawn * 220).rounded(), (24 + dusk * 50 + dawn * 140).rounded(),
      (48 + dusk * 20 + dawn * 110).rounded(), night * 0.58 + dusk * 0.28 + dawn * 0.16
    )
    : (0, 0, 0, 0)
  return DayState(
    name: t < 0.5 ? a.name : b.name, night: night, dawn: dawn, day: n(\.day), dusk: dusk,
    fireflies: clamp(night * (1 - dawn) * (1 - dusk * 0.4)), moon: n(\.moon),
    sunX: n(\.sunX), sunY: n(\.sunY), sunVisible: n(\.sunVisible), wash: wash)
}

/// Local time of day, or the `-hour 18.5` launch argument while previewing.
func dayAt(_ date: Date, forcedHour: Double?) -> DayState {
  let h: Double
  if let f = forcedHour {
    h = (f.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
  } else {
    let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
  }
  var i = 0
  while i < KEYS.count - 2 && KEYS[i + 1].h <= h { i += 1 }
  let a = KEYS[i], b = KEYS[i + 1]
  return mixKey(a, b, (h - a.h) / (b.h - a.h))
}

struct WeatherState {
  var fog, drizzle: Double
  /// Multiplier for plant sway. Stays near 1, with rare slow gusts.
  var sway: Double
  var rainbow: Double
  var name: String
}

/// Weather drifts over many minutes and never flickers.
func weatherAt(_ now: Date, _ weights: [Double], _ day: DayState) -> WeatherState {
  let t = now.timeIntervalSince1970
  let breeze = 0.82 + 0.18 * (0.5 + 0.5 * sin(t / 540))
  let gust = pow(max(0, sin(t / 280)), 8) * 0.85
  let sway = breeze + gust
  let fogWave = 0.5 + 0.5 * sin(t / 1200)
  let fog = min(1, max(day.dawn * 0.8, weights[WINTER] * 0.45, day.night * 0.12) * (0.4 + 0.6 * fogWave))
  let drizzleGate = smooth(0.62, 0.92, (sin(t / 860) + 1) / 2)
  let drizzle = drizzleGate * (weights[SPRING] * 0.8 + weights[AUTUMN] * 0.65) * (1 - weights[MONSOON])
  let leavingMonsoon =
    smooth(0.12, 0.35, weights[MONSOON]) * (1 - smooth(0.42, 0.7, weights[MONSOON])) * smooth(0.08, 0.28, weights[AUTUMN])
  let rainbow = leavingMonsoon * day.sunVisible * (1 - day.night)
  let name =
    rainbow > 0.35 ? "Rainbow" : fog > 0.55 ? "Fog" : drizzle > 0.4 ? "Drizzle" : sway > 1.45 ? "Breezy" : "Calm"
  return WeatherState(fog: fog, drizzle: drizzle, sway: sway, rainbow: rainbow, name: name)
}

struct RegionState {
  var meadow, wetlands, bamboo, waterfall, canopy: Double
  /// Pond size, 0 until the wetlands unlock, then growing for several hours.
  var pond: Double
}

let REGION_MILESTONES: [(at: Double, text: String)] = [
  (5 * 60, "A flower meadow is opening"),
  (20 * 60, "A pond has gathered in the wetlands"),
  (45 * 60, "A bamboo grove has risen"),
  (2 * 60 * 60, "A waterfall has found the hills"),
  (4 * 60 * 60, "The canopy has closed overhead"),
]

func regionsAt(_ focus: Double) -> RegionState {
  func reveal(_ at: Double) -> Double { clamp((focus - at) / (8 * 60)) }
  let wetlands = reveal(20 * 60)
  return RegionState(
    meadow: reveal(5 * 60), wetlands: wetlands, bamboo: reveal(45 * 60), waterfall: reveal(2 * 60 * 60),
    canopy: reveal(4 * 60 * 60),
    pond: wetlands * (0.4 + 0.6 * clamp((focus - 20 * 60) / (3 * 60 * 60))))
}
