import CoreGraphics

private let UNRIPE = "#8fae4a"

private let FRUIT_COLORS: [Species: [String]] = [
  .roundTree: ["#f08a24", "#f3b53b", "#d9453b"],
  .tallTree: ["#8e2f5a", "#c7352f"],
  .palm: ["#7a5230"],
  .banana: ["#f2d14a"],
  .cherry: ["#b3122e"],
]

/// Hue buckets and tone offsets for leaf gradients.
let LEAF_BUCKETS = [-0.08, 0, 0.08]
func leafBucket(_ hue: Double) -> Int { hue < -0.33 ? 0 : hue < 0.33 ? 1 : 2 }

let SHADOW_WIDTH: [Species: Double] = [
  .fern: 34, .bush: 56, .banana: 34, .palm: 42, .roundTree: 78, .tallTree: 92, .cherry: 80,
]

private func leaf(_ len: Double, _ w: Double) -> String {
  "M0 0 Q\(f(w)) \(f(-len * 0.45)) 0 \(f(-len)) Q\(f(-w)) \(f(-len * 0.45)) 0 0Z"
}

private func frond(_ len: Double) -> String {
  "M0 0 Q\(f(len * 0.5)) \(f(-len * 0.32)) \(f(len)) \(f(len * 0.3)) Q\(f(len * 0.5)) \(f(-len * 0.08)) 0 6Z"
}

private let FERN_ANGLES: [Double] = [-68, -45, -22, 0, 22, 45, 68]
private let BUSH_FLOWERS: [(Double, Double)] = [(-30, -26), (-12, -44), (8, -50), (24, -30), (-2, -22), (34, -14), (-38, -10), (14, -38)]
private let BANANA_LEAVES: [(Double, Double)] = [(-78, 70), (-42, 80), (-8, 72), (30, 82), (70, 70)]
private let BANANA_FRUIT: [(Double, Double, Double)] = [(0, 0, -20), (5, 2, -10), (-4, 6, -30), (2, 10, -15), (7, 11, -5)]
private let PALM_FRONDS: [(Double, Double)] = [(-50, 1), (-20, 1), (10, 1), (35, 1), (-50, -1), (-20, -1), (10, -1), (35, -1), (-80, 1), (-80, -1)]
private let ROUND_CANOPY: [(Double, Double, Double, Int)] = [
  (-50, -168, 46, 0), (50, -170, 44, 0), (0, -160, 48, 0),
  (-28, -205, 44, 1), (30, -207, 43, 1), (0, -218, 54, 1),
  (-18, -232, 26, 2), (22, -238, 20, 2),
]
private let ROUND_FRUIT: [(Double, Double)] = [(-45, -160), (-20, -190), (15, -175), (45, -160), (30, -200), (-5, -150), (-38, -205), (55, -185)]
private let TALL_CANOPY: [(Double, Double, Double, Double, Int)] = [
  (-36, -214, 34, 15, 1), (0, -312, 92, 32, 0), (-44, -332, 60, 26, 1),
  (46, -330, 58, 25, 1), (0, -350, 56, 26, 1), (-10, -362, 32, 14, 2),
]
private let TALL_FRUIT: [(Double, Double)] = [(-62, -296), (-28, -288), (18, -290), (60, -297), (0, -283), (-44, -306), (40, -306)]
private let TALL_VINES: [(Double, Double)] = [(-70, -300), (30, -290), (75, -305)]
private let CHERRY_BRANCHES = [
  "M-8 -108 Q-35 -130 -62 -168", "M-2 -140 Q6 -180 8 -214", "M4 -122 Q35 -135 64 -163",
  "M-30 -128 Q-55 -138 -80 -148", "M30 -130 Q55 -140 80 -146", "M-4 -170 Q-22 -195 -30 -214",
]
private let CHERRY_CANOPY: [(Double, Double, Double, Int)] = [
  (-60, -175, 34, 0), (62, -170, 32, 0), (-78, -150, 20, 1), (80, -148, 18, 1),
  (0, -200, 44, 1), (-30, -215, 34, 1), (35, -212, 34, 1), (20, -178, 30, 2), (-5, -240, 28, 2),
]
private let CHERRY_FRUIT: [(Double, Double)] = [(-50, -150), (-10, -166), (30, -160), (60, -145), (-25, -190), (15, -196), (-70, -140)]
private let CHERRY_SPECKS: [(Double, Double)] = [
  (-62, -190), (-38, -228), (-10, -258), (18, -225), (48, -198), (66, -180), (-20, -200), (8, -186), (-84, -158), (84, -156),
  (40, -228), (-48, -165),
]
private let SAKURA = ["#e493ad", "#f2b3c7", "#fcd8e3"]

/// The leaf gradient for a hue bucket and tone (0 dark, 1 mid, 2 light).
func leafPaint(_ pal: Palette, _ bucket: Int, _ tone: Int) -> Paint {
  let base = shade([pal.leafDark, pal.leafMid, pal.leafLight][tone], LEAF_BUCKETS[bucket])
  return .radial(cx: 0.36, cy: 0.3, r: 0.8, stops: [(0, shade(base, 0.22), 1), (0.55, base, 1), (1, shade(base, -0.22), 1)])
}

private func sakuraPaint(_ tone: Int) -> Paint {
  let c = SAKURA[tone]
  return .radial(cx: 0.36, cy: 0.3, r: 0.8, stops: [(0, shade(c, 0.35), 1), (0.55, c, 1), (1, mix(c, "#9a4a68", 0.35), 1)])
}

/// Rounds the parts of a plant's state that change its drawing, so plants
/// share images and are only redrawn when they visibly change.
func drawnState(_ s: PlantState) -> PlantState {
  func q(_ v: Double) -> Double { (v * 16).rounded() / 16 }
  return PlantState(
    growth: 1, opacity: 1, bloom: q(s.bloom), fruitSize: q(s.fruitSize), ripeness: q(s.ripeness), vine: q(s.vine),
    sakura: q(s.sakura), foliage: q(s.foliage))
}

/// Everything about a plant that changes its image, as a cache key.
func plantImageKey(_ p: PlantSpec, _ s: PlantState, _ pal: Palette) -> String {
  let kinds = FRUIT_COLORS[p.species]?.count ?? 1
  let fk = Int((p.fruitKind * Double(kinds)).rounded(.down))
  return "\(p.species.rawValue)|\(p.form)|\(leafBucket(p.hue))|\(fk)|\(s.bloom)|\(s.fruitSize)|\(s.ripeness)|\(s.vine)|\(s.sakura)|\(s.foliage)|\(pal.key)"
}

/// The plant's swaying body in local coordinates, trunk base at (0, 0).
/// `s` should come from `drawnState`.
func plantOps(_ p: PlantSpec, _ s: PlantState, _ pal: Palette) -> [Op] {
  let b = leafBucket(p.hue)
  let dark = shade(pal.leafDark, LEAF_BUCKETS[b])
  let mid = shade(pal.leafMid, LEAF_BUCKETS[b])
  let g = [0, 1, 2].map { leafPaint(pal, b, $0) }
  let kinds = FRUIT_COLORS[p.species]
  let ripe = kinds.map { $0[Int((p.fruitKind * Double($0.count)).rounded(.down))] } ?? UNRIPE
  let fruitFill = mix(UNRIPE, ripe, s.ripeness)

  func blossoms(_ points: [(Double, Double)], _ r: Double) -> [Op] {
    guard s.bloom > 0.01 else { return [] }
    return points.map { .fill(circlePath($0.0 + 4, $0.1 - 3, r * s.bloom), .solid(pal.blossom), opacity: 0.95) }
  }

  func fruits(_ points: [(Double, Double)], _ r: Double) -> [Op] {
    guard s.fruitSize > 0.01 else { return [] }
    return points.flatMap { (x, y) -> [Op] in
      let rx = r * s.fruitSize * (p.form == 2 ? 0.72 : 1)
      let ry = r * s.fruitSize * (p.form == 1 ? 1.35 : p.form == 2 ? 0.85 : 1)
      return [
        .fill(ellipsePath(x, y, rx, ry), .solid(fruitFill)),
        .fill(ellipsePath(x - rx * 0.3, y - ry * 0.35, rx * 0.28, ry * 0.28), .solid("#ffffff"), opacity: 0.35),
      ]
    }
  }

  var ops: [Op] = []
  switch p.species {
  case .fern:
    for (i, a) in FERN_ANGLES.enumerated() {
      let len = 58 - abs(a) * 0.25
      ops.append(
        .group(
          [
            .fill(leaf(len, 9), i % 2 == 1 ? g[1] : g[2]),
            .stroke("M0 0 L0 \(f(-len))", Stroke(color: dark, width: 0.8), opacity: 0.6),
          ], rotate(a)))
    }
    ops.append(.fill(leaf(40, 7), g[0], rotate(-10)))

  case .bush:
    ops += [
      .fill(circlePath(-26, -20, 21), g[0]),
      .fill(circlePath(26, -20, 21), g[0]),
      .fill(circlePath(0, -30, 27), g[1]),
      .fill(circlePath(-14, -14, 17), g[1]),
      .fill(circlePath(16, -13, 17), g[1]),
      .fill(circlePath(-8, -42, 12), g[2], opacity: 0.8),
    ]
    ops += blossoms(BUSH_FLOWERS, 3.2)

  case .banana:
    ops.append(.fill("M-4 0 L-3 -88 L3 -88 L4 0Z", .solid(shade(mid, -0.15))))
    for (i, (a, len)) in BANANA_LEAVES.enumerated() {
      ops.append(
        .group(
          [
            .fill(leaf(len, 15), i % 2 == 1 ? g[1] : g[2]),
            .stroke("M0 0 L0 \(f(-len))", Stroke(color: dark, width: 0.9), opacity: 0.5),
          ], translate(0, -84).then(rotate(a))))
    }
    if s.bloom > 0.01 { ops.append(.fill(ellipsePath(7, -66, 4 * s.bloom, 6 * s.bloom), .solid("#7a2f4a"))) }
    if s.fruitSize > 0.01 {
      ops.append(
        .group(
          BANANA_FRUIT.map { (x, y, r) in .fill(ellipsePath(x, y, 2.6, 8), .solid(fruitFill), rotate(r, x, y)) },
          translate(7, -78).then(scale(s.fruitSize))))
    }

  case .palm:
    let (cx, cy) = (18.0, -220.0)
    let trunk = "M-3 0 Q14 -110 \(f(cx)) \(f(cy))"
    ops.append(.stroke(trunk, Stroke(color: pal.trunk, width: 9, cap: .round)))
    ops.append(.stroke(trunk, Stroke(color: shade(pal.trunk, -0.3), width: 9, dash: [1.5, 9])))
    for (i, (r, m)) in PALM_FRONDS.enumerated() {
      ops.append(.fill(frond(96), g[i % 3], translate(cx, cy).then(scale(m, 1)).then(rotate(r))))
    }
    ops += blossoms([(cx - 10, cy + 6), (cx + 2, cy + 10), (cx + 12, cy + 5)], 3)
    ops += fruits([(cx - 6, cy + 8), (cx + 5, cy + 9), (cx, cy + 14), (cx + 11, cy + 4)], 5.5)

  case .roundTree:
    let trunk =
      p.form == 1
      ? "M-15 0 Q-9 -64 -7 -126 L7 -126 Q9 -64 15 0Z"
      : p.form == 2
        ? "M-5 0 Q16 -78 2 -154 L11 -150 Q26 -70 9 0Z"
        : "M-11 0 Q-6 -80 -5 -150 L5 -150 Q6 -80 11 0Z"
    let crown =
      p.form == 1
      ? translate(0, 18).then(scale(1.16, 0.86))
      : p.form == 2 ? translate(6, -8).then(scale(0.86, 1.08)) : .identity
    ops.append(.fill(trunk, .solid(pal.trunk)))
    ops.append(.stroke("M-3 -120 Q-25 -140 -40 -165", Stroke(color: pal.trunk, width: 5, cap: .round)))
    ops.append(.stroke("M3 -130 Q25 -150 42 -170", Stroke(color: pal.trunk, width: 5, cap: .round)))
    var crownOps: [Op] = ROUND_CANOPY.map { (x, y, r, tone) in
      .fill(circlePath(x, y, r), g[tone], opacity: tone == 2 ? 0.8 : 1)
    }
    crownOps += blossoms(ROUND_FRUIT, 3.6)
    crownOps += fruits(ROUND_FRUIT, 6.5)
    ops.append(.group(crownOps, crown))

  case .tallTree:
    ops.append(
      .fill(
        p.form == 1
          ? "M-7 0 Q-4 -170 -3 -330 L3 -330 Q4 -170 7 0Z"
          : p.form == 2 ? "M-13 0 Q-8 -140 -6 -270 L6 -270 Q8 -140 13 0Z" : "M-10 0 Q-6 -160 -4 -305 L4 -305 Q6 -160 10 0Z",
        .solid(pal.trunk)))
    ops.append(.fill("M-10 0 L-26 0 L-7 -34Z M10 0 L26 0 L7 -34Z", .solid(shade(pal.trunk, -0.1))))
    ops.append(.stroke("M-3 -190 Q-20 -200 -34 -212", Stroke(color: pal.trunk, width: 5, cap: .round)))
    let canopy =
      p.form == 1
      ? translate(0, -24).then(scale(0.86, 1.12))
      : p.form == 2 ? translate(0, 20).then(scale(1.2, 0.82)) : .identity
    ops.append(.group(TALL_CANOPY.map { (x, y, rx, ry, tone) in .fill(ellipsePath(x, y, rx, ry), g[tone]) }, canopy))
    if s.vine > 0 {
      for (i, (x, y)) in TALL_VINES.enumerated() {
        let len = 30 + s.vine * (90 + Double(i) * 20)
        ops.append(
          .stroke(
            "M\(f(x)) \(f(y)) q6 \(f(len * 0.25)) 0 \(f(len * 0.5)) q-6 \(f(len * 0.25)) 0 \(f(len * 0.5))",
            Stroke(color: mid, width: 1.6)))
      }
    }
    ops += blossoms(TALL_FRUIT, 3.2)
    ops += fruits(TALL_FRUIT, 5)

  case .cherry:
    let bark = shade(pal.trunk, -0.15)
    ops.append(.fill("M-10 0 Q-2 -60 -12 -110 Q-15 -132 -4 -152 L4 -152 Q1 -122 10 -100 Q16 -50 10 0Z", .solid(bark)))
    var inner: [Op] = CHERRY_BRANCHES.enumerated().map { (i, d) in
      .stroke(d, Stroke(color: bark, width: i < 3 ? 5 : 3, cap: .round))
    }
    var foliage: [Op] = []
    for (x, y, r, tone) in CHERRY_CANOPY {
      foliage.append(.fill(circlePath(x, y, r), g[tone]))
      if s.sakura > 0.01 { foliage.append(.fill(circlePath(x, y, r), sakuraPaint(tone), opacity: s.sakura)) }
    }
    if s.sakura > 0.01 {
      foliage += CHERRY_SPECKS.map { .fill(circlePath($0.0, $0.1, 2.4), .solid("#fff6f8"), opacity: s.sakura * 0.9) }
    }
    if s.foliage > 0.01 { inner.append(.group(foliage, opacity: s.foliage)) }
    if s.fruitSize > 0.01 {
      for (x, y) in CHERRY_FRUIT {
        inner.append(
          .stroke(
            "M\(f(x)) \(f(y - 9)) L\(f(x - 3)) \(f(y)) M\(f(x)) \(f(y - 9)) L\(f(x + 3)) \(f(y + 1))",
            Stroke(color: "#5b4a2a", width: 0.8)))
        inner.append(.fill(circlePath(x - 3, y, 3.2 * s.fruitSize), .solid(fruitFill)))
        inner.append(.fill(circlePath(x + 3, y + 1, 3.2 * s.fruitSize), .solid(fruitFill)))
      }
    }
    let form = p.form == 1 ? scale(1.18, 0.92) : p.form == 2 ? scale(0.84, 1.1) : .identity
    ops.append(.group(inner, form))
  }
  return ops
}

/// The soft contact shadow under a plant, which does not sway.
func shadowOps(_ species: Species) -> [Op] {
  let sw = SHADOW_WIDTH[species]!
  return [
    .fill(
      ellipsePath(0, 1, sw, sw * 0.16),
      .radial(cx: 0.5, cy: 0.5, r: 0.5, stops: [(0, "#12201a", 0.32), (1, "#12201a", 0)]))
  ]
}

/// Wildflower colors per season, indexed like SEASONS.
let FLOWER_COLORS: [[String]] = [
  ["#f7c6d6", "#fff4f7", "#e9a3c0"],
  ["#f6d34a", "#ffffff", "#f29a52"],
  ["#8fb0e8", "#dfe9f5", "#b59be0"],
  ["#e98a3a", "#d9453b", "#f2c14e"],
  ["#ffffff", "#e9eef0", "#ffffff"],
]

/// A grass tuft or wildflower at its local origin.
func floraOps(_ fl: Flora, grass: [String], flowers: [String]) -> [Op] {
  if !fl.isFlower {
    let color = grass[Int((fl.hue * Double(grass.count)).rounded(.down))]
    let n = Double(fl.blades)
    let d = (0..<fl.blades).map { k -> String in
      let kk = Double(k)
      let o = (kk - n / 2) * 3.5
      let h = 12 + (kk * 7 + fl.hue * 10).truncatingRemainder(dividingBy: 9)
      let lean = (kk - n / 2) * 3
      return "M\(f(o - 1.4)) 0 Q\(f(o + lean * 0.3)) \(f(-h * 0.6)) \(f(o + lean)) \(f(-h)) Q\(f(o + lean * 0.2)) \(f(-h * 0.5)) \(f(o + 1.4)) 0Z"
    }.joined(separator: " ")
    return [.fill(d, .solid(color))]
  }
  let color = flowers[Int((fl.hue * Double(flowers.count)).rounded(.down))]
  return [
    .stroke("M0 0 Q1 -7 0 -13", Stroke(color: grass[0], width: 1)),
    .fill(circlePath(0, -14, 3.2), .solid(color)),
    .fill(circlePath(0, -14, 1.1), .solid("#f4d76a")),
  ]
}
