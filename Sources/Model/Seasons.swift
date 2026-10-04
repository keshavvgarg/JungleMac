import Foundation

struct Palette: Equatable {
  var skyTop, skyMid, skyBottom, sun, mist, cloud: String
  var hillFar, hillMid, hillNear: String
  var groundFar, groundNear: String
  var leafDark, leafMid, leafLight, trunk, blossom: String

  /// Identity for image caches: two palettes with the same key draw identically.
  var key: String {
    [skyTop, skyMid, skyBottom, sun, mist, cloud, hillFar, hillMid, hillNear, groundFar, groundNear, leafDark, leafMid, leafLight, trunk, blossom].joined()
  }

  func mixed(with b: Palette, _ t: Double) -> Palette {
    if t == 0 { return self }
    return Palette(
      skyTop: mix(skyTop, b.skyTop, t), skyMid: mix(skyMid, b.skyMid, t), skyBottom: mix(skyBottom, b.skyBottom, t),
      sun: mix(sun, b.sun, t), mist: mix(mist, b.mist, t), cloud: mix(cloud, b.cloud, t),
      hillFar: mix(hillFar, b.hillFar, t), hillMid: mix(hillMid, b.hillMid, t), hillNear: mix(hillNear, b.hillNear, t),
      groundFar: mix(groundFar, b.groundFar, t), groundNear: mix(groundNear, b.groundNear, t),
      leafDark: mix(leafDark, b.leafDark, t), leafMid: mix(leafMid, b.leafMid, t), leafLight: mix(leafLight, b.leafLight, t),
      trunk: mix(trunk, b.trunk, t), blossom: mix(blossom, b.blossom, t))
  }
}

let SEASONS = ["Spring", "Summer", "Monsoon", "Autumn", "Winter"]
let SPRING = 0, SUMMER = 1, MONSOON = 2, AUTUMN = 3, WINTER = 4

/// Focused seconds per season; a full year is five of these.
let SEASON_SECONDS: Double = 60 * 60

/// Fraction at the end of each season spent fading into the next one.
private let BLEND = 0.12

/// Steps per season blend. Blending is quantized so plant images are redrawn
/// every few seconds of a blend rather than on every clock tick.
private let BLEND_STEPS = 24.0

private let PALETTES: [Palette] = [
  Palette(
    skyTop: "#b9c9d6", skyMid: "#e8dcc8", skyBottom: "#f6e3c4", sun: "#fff1d0", mist: "#f1ece0", cloud: "#fbf6ee",
    hillFar: "#b7c4bf", hillMid: "#93aca0", hillNear: "#6f9281", groundFar: "#7f9f74", groundNear: "#4f7a4f",
    leafDark: "#2f5b3c", leafMid: "#4f8a55", leafLight: "#86b66f", trunk: "#5b4636", blossom: "#f4c1cf"),
  Palette(
    skyTop: "#a8c3cf", skyMid: "#e6e2c6", skyBottom: "#f8e6b8", sun: "#fff4c8", mist: "#eef0df", cloud: "#fffaf0",
    hillFar: "#a9bfae", hillMid: "#7ea18a", hillNear: "#56826a", groundFar: "#6b925e", groundNear: "#3c6a41",
    leafDark: "#1f4a30", leafMid: "#357a45", leafLight: "#6aa85a", trunk: "#4f3b2d", blossom: "#fbe7a1"),
  Palette(
    skyTop: "#66737f", skyMid: "#949fa2", skyBottom: "#b3bab2", sun: "#d9dccf", mist: "#c3ccc7", cloud: "#5f6b77",
    hillFar: "#8a9996", hillMid: "#6a827b", hillNear: "#4b695e", groundFar: "#557a52", groundNear: "#2c5233",
    leafDark: "#1a4230", leafMid: "#2c6a44", leafLight: "#55935a", trunk: "#3d3127", blossom: "#e3ecee"),
  Palette(
    skyTop: "#c2b9c4", skyMid: "#ecd3bd", skyBottom: "#f5d2a8", sun: "#ffe2b8", mist: "#f1e4d6", cloud: "#f6e8da",
    hillFar: "#c4bba8", hillMid: "#a99a78", hillNear: "#8a7a55", groundFar: "#9a8d5c", groundNear: "#6e6238",
    leafDark: "#7a3f22", leafMid: "#b8672e", leafLight: "#e0a04a", trunk: "#4d382a", blossom: "#f2c38a"),
  Palette(
    skyTop: "#b4bfcc", skyMid: "#dde2e6", skyBottom: "#eae6e0", sun: "#f7f3ea", mist: "#eef1f3", cloud: "#eef1f4",
    hillFar: "#c3ccd1", hillMid: "#a6b4ba", hillNear: "#899ba1", groundFar: "#c9d3d3", groundNear: "#a9b8b6",
    leafDark: "#3d5750", leafMid: "#5f7d73", leafLight: "#9bb3a9", trunk: "#4a4040", blossom: "#ffffff"),
]

struct SeasonState {
  var index: Int
  var name: String { SEASONS[index] }
  var progress: Double
  var year: Int
  var palette: Palette
  /// Presence of each season, indexed like SEASONS; sums to 1.
  var weights: [Double]
}

func seasonAt(_ focus: Double) -> SeasonState {
  let n = SEASONS.count
  let cycle = focus / SEASON_SECONDS
  let whole = Int(cycle.rounded(.down))
  let idx = whole % n
  let next = (idx + 1) % n
  let within = cycle - Double(whole)
  var raw = within > 1 - BLEND ? (within - (1 - BLEND)) / BLEND : 0
  raw = (raw * BLEND_STEPS).rounded(.down) / BLEND_STEPS
  let t = raw * raw * (3 - 2 * raw)
  var weights = [Double](repeating: 0, count: n)
  weights[idx] = 1 - t
  weights[next] += t
  return SeasonState(
    index: idx, progress: within, year: whole / n + 1,
    palette: PALETTES[idx].mixed(with: PALETTES[next], t), weights: weights)
}
