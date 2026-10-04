import Foundation

let W: Double = 1600
let H: Double = 900
let HORIZON: Double = 590

enum Species: String, CaseIterable {
  case fern, bush, banana, palm, roundTree, tallTree, cherry
}

private struct SpeciesInfo {
  var grow: Double
  var weight: Double
  var maxDepth: Double
  var fruits: Bool
}

/// In the same order as the web version's object, which `pickSpecies` depends on.
private let SPECIES: [(Species, SpeciesInfo)] = [
  (.fern, SpeciesInfo(grow: 120, weight: 3, maxDepth: 1, fruits: false)),
  (.bush, SpeciesInfo(grow: 300, weight: 3, maxDepth: 1, fruits: false)),
  (.banana, SpeciesInfo(grow: 600, weight: 2, maxDepth: 0.95, fruits: true)),
  (.palm, SpeciesInfo(grow: 1200, weight: 1.4, maxDepth: 0.8, fruits: true)),
  (.roundTree, SpeciesInfo(grow: 1500, weight: 2, maxDepth: 0.85, fruits: true)),
  (.tallTree, SpeciesInfo(grow: 2400, weight: 1.2, maxDepth: 0.7, fruits: true)),
  (.cherry, SpeciesInfo(grow: 1200, weight: 1.6, maxDepth: 0.85, fruits: true)),
]
private func info(_ s: Species) -> SpeciesInfo { SPECIES.first { $0.0 == s }!.1 }

/// Perch points in plant-local coordinates (base of the trunk at 0,0).
let PERCHES: [Species: [(Double, Double)]] = [
  .roundTree: [(0, -271), (-30, -263), (33, -261), (-70, -208)],
  .tallTree: [(0, -375), (-60, -357), (62, -354), (-36, -229)],
  .palm: [(18, -228)],
  .cherry: [(-5, -267), (-30, -248), (35, -245)],
]

/// Timeline after a fruiting plant matures, in focused seconds.
private let BLOOM_END: Double = 240
private let FRUIT_START: Double = 180
private let FRUIT_GROWN: Double = 420
private let RIPE_START: Double = 360
private let RIPE_DONE: Double = 600

private let FIRST_TREE_GROW: Double = 15 * 60
let FIRST_FRUIT_AT = FIRST_TREE_GROW + RIPE_DONE

/// Reached after about 15 hours of focus; rendering cost grows with every plant.
private let MAX_PLANTS = 400

struct PlantSpec {
  var id: Int
  var species: Species
  var x: Double
  var depth: Double
  var baseY: Double
  var scale: Double
  var flip: Double
  var spawnAt: Double
  var grow: Double
  var hue: Double
  var fruitKind: Double
  /// 0, 1 or 2. Changes trunk, canopy and fruit shape.
  var form: Int
  /// -1 to 1, a slight lean so neighbouring trees are not identical.
  var lean: Double
  var swayDur: Double
  var swayDelay: Double
}

struct PlantState: Equatable {
  var growth: Double
  var opacity: Double
  var bloom: Double
  var fruitSize: Double
  var ripeness: Double
  var vine: Double
  /// Cherry trees only: how pink the canopy is, and how much foliage remains.
  var sakura: Double
  var foliage: Double
}

/// Port of the web version's `rng`, bit for bit, so a seed grows the same jungle.
final class Rng {
  private var h: UInt32
  init(_ seed: Int, _ a: Int, _ b: Int = 0) {
    h = UInt32(truncatingIfNeeded: seed) ^ (UInt32(truncatingIfNeeded: a + 1) &* 0x9e37_79b1)
      ^ (UInt32(truncatingIfNeeded: b + 1) &* 0x85eb_ca77)
  }
  func callAsFunction() -> Double {
    h = h &+ 0x6d2b_79f5
    var t = h
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4_294_967_296
  }
}

private func clamp(_ v: Double) -> Double { v < 0 ? 0 : v > 1 ? 1 : v }

func depthToY(_ depth: Double) -> Double { HORIZON + 8 + depth * 282 }
func depthToScale(_ depth: Double) -> Double { 0.28 + depth * 0.82 }

/// Plants arrive quickly at first, then ever more slowly.
private func spawnTime(_ i: Int) -> Double { 30 * pow(Double(i), 1.25) }

func plantCount(_ focus: Double) -> Int {
  min(MAX_PLANTS, Int(pow(max(0, focus) / 30, 0.8).rounded(.down)) + 1)
}

private func pickSpecies(_ roll: Double) -> Species {
  let total = SPECIES.reduce(0) { $0 + $1.1.weight }
  var acc = roll * total
  for (name, info) in SPECIES {
    acc -= info.weight
    if acc <= 0 { return name }
  }
  return .fern
}

func makePlant(_ seed: Int, _ i: Int) -> PlantSpec {
  let r = Rng(seed, i)
  let species: Species
  let x: Double
  let depth: Double
  // The first plants are placed by hand, clear of the centre panel, so every
  // jungle opens with a tree in view that fruits within 25 minutes.
  switch i {
  case 0: species = .roundTree; x = 360 + r() * 80; depth = 0.74
  case 1: species = .fern; x = 1150 + r() * 60; depth = 0.9
  case 2: species = .bush; x = 1260 + r() * 80; depth = 0.82
  case 3: species = .cherry; x = 1330 + r() * 80; depth = 0.6
  default:
    species = pickSpecies(r())
    depth = r() * info(species).maxDepth
    x = 30 + r() * (W - 60)
  }
  let size = 0.85 + r() * 0.3
  return PlantSpec(
    id: i, species: species, x: x, depth: depth, baseY: depthToY(depth), scale: depthToScale(depth) * size,
    flip: r() < 0.5 ? -1 : 1, spawnAt: spawnTime(i),
    grow: i == 0 ? FIRST_TREE_GROW : info(species).grow * (0.85 + r() * 0.3),
    hue: r() * 2 - 1, fruitKind: r(), form: Int((r() * 3).rounded(.down)), lean: r() * 2 - 1,
    swayDur: 5 + r() * 4, swayDelay: -r() * 9)
}

func plantState(_ p: PlantSpec, _ focus: Double, _ w: [Double]) -> PlantState {
  let age = focus - p.spawnAt
  let t = clamp(age / p.grow)
  let mature = age - p.grow
  let inSeason = 1 - w[WINTER]
  var bloom = 0.0, fruitSize = 0.0, ripeness = 0.0, sakura = 0.0, foliage = 1.0
  if p.species == .bush {
    bloom = clamp(mature / 120) * inSeason * (1 - w[AUTUMN] * 0.6 - w[MONSOON] * 0.4)
  } else if p.species == .cherry {
    let ready = clamp(mature / 120)
    sakura = w[SPRING] * clamp(0.35 + t)
    foliage = 1 - w[WINTER] * 0.9
    fruitSize = ready * (w[SUMMER] + w[MONSOON] * 0.5)
    ripeness = 1
  } else if info(p.species).fruits && mature > 0 {
    bloom = (mature < BLOOM_END ? clamp(mature / 60) : clamp(1 - (mature - BLOOM_END) / 90)) * inSeason
    fruitSize = clamp((mature - FRUIT_START) / (FRUIT_GROWN - FRUIT_START)) * inSeason
    ripeness = clamp((mature - RIPE_START) / (RIPE_DONE - RIPE_START))
  }
  return PlantState(
    growth: 0.06 + 0.94 * (1 - pow(1 - t, 2.2)), opacity: clamp(0.2 + age / 8), bloom: bloom,
    fruitSize: fruitSize, ripeness: ripeness, vine: p.species == .tallTree ? clamp(mature / 1800) : 0,
    sakura: sakura, foliage: foliage)
}

func isFruiting(_ p: PlantSpec, _ focus: Double, _ w: [Double]) -> Bool {
  if p.species == .cherry { return focus - p.spawnAt - p.grow >= 120 && w[SUMMER] + w[MONSOON] > 0.5 }
  return w[WINTER] < 0.5 && info(p.species).fruits && focus - p.spawnAt - p.grow >= RIPE_DONE
}

struct Flora {
  var id: Int
  var isFlower: Bool
  var x, depth, baseY, scale: Double
  var blades: Int
  var hue: Double
}

private let MAX_FLORA = 220

/// Grass and wildflowers carpet the ground a little more every 25 focused seconds.
func floraCount(_ focus: Double) -> Int { min(MAX_FLORA, 12 + Int((focus / 25).rounded(.down))) }

func makeFlora(_ seed: Int, _ i: Int) -> Flora {
  let r = Rng(seed, i, 31)
  let depth = 0.05 + r() * 0.95
  return Flora(
    id: i, isFlower: r() < 0.28, x: r() * W, depth: depth, baseY: depthToY(depth) + 2,
    scale: depthToScale(depth) * (0.8 + r() * 0.5), blades: 3 + Int((r() * 3).rounded(.down)), hue: r())
}

struct BirdPlacement {
  var key: String
  var sp: BirdSpecies
  var arriveAt: Double
  var x, y, sortY, scale, depth, flip: Double
}

/// Extra visitors on top of each species' debut; spaced further apart over time.
private func extraBirdTime(_ j: Int) -> Double { 420 + 480 * pow(Double(j), 1.15) }
private let MAX_EXTRA_BIRDS = 36

func placeBirds(_ seed: Int, _ plants: [PlantSpec], _ focus: Double) -> [BirdPlacement] {
  var events: [(t: Double, id: Int, key: String, sp: BirdSpecies?)] = []
  for (i, sp) in BIRDS.enumerated() where sp.unlockAt <= focus {
    events.append((sp.unlockAt, 1000 + i, sp.id, sp))
  }
  for j in 0..<MAX_EXTRA_BIRDS {
    let t = extraBirdTime(j)
    if t > focus { break }
    events.append((t, j, "v\(j)", nil))
  }
  events.sort { $0.t < $1.t }

  var taken = Set<String>()
  var out: [BirdPlacement] = []
  for ev in events {
    let r = Rng(seed, ev.id, 99)
    let unlocked = BIRDS.filter { $0.unlockAt <= ev.t }
    if unlocked.isEmpty { continue }
    let sp = ev.sp ?? unlocked[min(unlocked.count - 1, Int((pow(r(), 0.7) * Double(unlocked.count)).rounded(.down)))]
    let flip: Double = r() < 0.5 ? -1 : 1
    let hosts = plants.filter { PERCHES[$0.species] != nil && $0.spawnAt + $0.grow <= ev.t }

    var placed = false
    var attempt = 0
    while attempt < 6 && !hosts.isEmpty {
      attempt += 1
      let p = hosts[Int((r() * Double(hosts.count)).rounded(.down))]
      let perches = PERCHES[p.species]!
      let k = Int((r() * Double(perches.count)).rounded(.down))
      let slot = "\(p.id):\(k)"
      if taken.contains(slot) { continue }
      taken.insert(slot)
      let (px, py) = perches[k]
      out.append(
        BirdPlacement(
          key: ev.key, sp: sp, arriveAt: ev.t, x: p.x + px * p.scale * p.flip, y: p.baseY + py * p.scale,
          sortY: p.baseY + 0.01, scale: p.scale * 1.25 * sp.size, depth: p.depth, flip: flip))
      placed = true
      break
    }
    if !placed {
      let depth = 0.55 + r() * 0.4
      let y = depthToY(depth)
      out.append(
        BirdPlacement(
          key: ev.key, sp: sp, arriveAt: ev.t, x: 100 + r() * (W - 200), y: y, sortY: y,
          scale: depthToScale(depth) * 1.25 * sp.size, depth: depth, flip: flip))
    }
  }
  return out
}
