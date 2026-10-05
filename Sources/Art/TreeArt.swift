import CoreGraphics

/// Trees come in a few shapes per form, so a grove does not repeat.
let TREE_VARIANTS = 4

/// One soft cloud of leaves or blossom: the union of a few overlapping
/// circles, so its edge is gently scalloped but it reads as one mass.
/// `flatten` squashes it vertically, for the layered tops of tall trees.
func cloudPath(_ center: CGPoint, _ radius: Double, _ r: Rng, flatten: Double = 0.8) -> CGPath {
  let path = CGMutablePath()
  for _ in 0..<(7 + Int(radius / 6)) {
    let a = r() * 2 * .pi
    let d = radius * r().squareRoot() * 0.6
    let rr = radius * (0.38 + r() * 0.2)
    path.addEllipse(
      in: CGRect(x: center.x + cos(a) * d - rr, y: center.y + sin(a) * d * flatten - rr * (flatten + 0.2), width: 2 * rr, height: 2 * rr * (flatten + 0.2)))
  }
  return path
}

/// A soft sheen on the sunlit top of a cloud, diffuse rather than glossy.
func cloudSheen(_ center: CGPoint, _ radius: Double, _ r: Rng, _ color: String, _ strength: Double, flatten: Double = 0.8) -> Op {
  let a = -.pi / 2 + (r() - 0.5) * 1.2
  return .fill(
    ellipsePath(center.x + cos(a) * radius * 0.35, center.y + sin(a) * radius * 0.35 * flatten, radius * 0.6, radius * 0.42 * flatten),
    .radial(cx: 0.5, cy: 0.5, r: 0.5, stops: [(0, color, strength), (1, color, 0)]))
}

/// Leaf colours for a tree's hue bucket: lit top, middle, shaded underside.
private func leafTones(_ pal: Palette, _ bucket: Int) -> (light: String, mid: String, dark: String) {
  let k = LEAF_BUCKETS[bucket]
  return (shade(shade(pal.leafLight, k), 0.06), shade(pal.leafMid, k), shade(pal.leafDark, k))
}

/// A crown of leaf clouds: a dark mass behind for depth, each cloud lit from
/// above, and a soft sheen on the upper ones.
private func crown(_ clouds: [(c: CGPoint, r: Double)], _ tones: (light: String, mid: String, dark: String), _ r: Rng, flatten: Double = 0.8) -> [Op] {
  let sorted = clouds.sorted { $0.c.y < $1.c.y }
  let paths = sorted.map { cloudPath($0.c, $0.r, r, flatten: flatten) }
  let top = sorted.map { $0.c.y - $0.r }.min() ?? 0
  var ops: [Op] = paths.map { .fill($0, .solid(shade(tones.dark, -0.18)), opacity: 0.6, translate(2, 5)) }
  for (cl, path) in zip(sorted, paths) {
    // Upper clouds catch more light than the ones beneath them.
    let lift = max(0, min(1, 1 - (cl.c.y - top) / 140))
    ops.append(.fill(path, .vertical([(0, mix(tones.mid, tones.light, 0.4 + lift * 0.6), 1), (0.55, tones.mid, 1), (1, tones.dark, 1)])))
  }
  for cl in sorted.prefix(max(1, sorted.count / 2)) {
    ops.append(cloudSheen(cl.c, cl.r, r, shade(tones.light, 0.4), 0.32, flatten: flatten))
  }
  return ops
}

/// Where fruit and blossom hang: the lower halves of a crown's clouds.
private func hangingPoints(_ clouds: [(c: CGPoint, r: Double)], _ r: Rng, count: Int) -> [(Double, Double)] {
  (0..<count).map { k in
    let cl = clouds[k % clouds.count]
    let a = (0.15 + r() * 0.7) * .pi
    let d = cl.r * (0.35 + r() * 0.45)
    return (cl.c.x + cos(a) * d, cl.c.y + sin(a) * d * 0.7)
  }
}

/// A tree drawing and where its fruit and blossom go.
struct TreeArtResult {
  var back: [Op]
  var crown: [Op]
  var hang: [(Double, Double)]
  /// Leaves drawn over the fruit, so some of it hangs half hidden.
  var cover: [Op] = []
}

// MARK: - Fruit tree

/// A scalloped mass: an oval with a ring of round bumps around its edge.
private func scallopedPath(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ r: Rng, bumps: Int, bump: Double) -> CGPath {
  let path = CGMutablePath()
  for k in 0..<bumps {
    let a = Double(k) / Double(bumps) * 2 * .pi + (r() - 0.5) * 0.15
    let x = cx + cos(a) * rx * 0.86, y = cy + sin(a) * ry * 0.86
    let rr = bump * (0.8 + r() * 0.4)
    path.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr))
  }
  path.addEllipse(in: CGRect(x: cx - rx * 0.9, y: cy - ry * 0.9, width: rx * 1.8, height: ry * 1.8))
  return path
}

/// A fruit tree like a mango, orange or apple: a short, thick trunk forking
/// low into strong limbs under a wide crown in three crisp leaf tones (shaded
/// back, middle, sunlit top). Its top sits near 260 units up, where birds perch.
func roundTreeArt(_ p: PlantSpec, _ pal: Palette) -> TreeArtResult {
  let variant = p.id % TREE_VARIANTS
  let r = Rng(9600 + p.form * 10 + variant, 1, 9)
  let tones = leafTones(pal, leafBucket(p.hue))
  let bark = pal.trunk

  let shape = [(118.0, 72.0), (104, 80), (126, 66)][p.form]
  let rx = shape.0 + r() * 12, ry = shape.1 + r() * 8
  let cx = (r() - 0.5) * 16
  let cy = -232 + ry * 0.86

  var back: [Op] = [
    .fill("M-17 0 Q-11 -30 -12 -62 Q-13 -78 -8 -88 L8 -88 Q13 -78 12 -62 Q11 -30 17 0Z", .solid(bark)),
    .fill("M-17 0 Q-25 0 -30 3 L-10 -14Z M17 0 Q25 0 30 3 L10 -14Z", .solid(shade(bark, -0.12))),
    .stroke("M-4 -6 Q-2 -40 -3 -80", Stroke(color: shade(bark, 0.16), width: 3, cap: .round), opacity: 0.35),
  ]
  for k in 0..<4 {
    let a = (-155 + Double(k) * 43 + (r() - 0.5) * 12) * .pi / 180
    let len = 60 + r() * 30
    back.append(
      .stroke(
        "M0 -84 Q\(f(cos(a) * len * 0.4)) \(f(-100 + sin(a) * len * 0.3)) \(f(cos(a) * len * 0.9)) \(f(-90 + sin(a) * len * 0.8))",
        Stroke(color: bark, width: 7 - Double(k % 2) * 2, cap: .round)))
  }

  let crownOps: [Op] = [
    .fill(scallopedPath(cx + 4, cy + 6, rx, ry, r, bumps: 16, bump: 26), .solid(tones.dark)),
    .fill(scallopedPath(cx - 6, cy - 8, rx * 0.86, ry * 0.8, r, bumps: 14, bump: 24), .solid(tones.mid)),
    .fill(scallopedPath(cx - 26, cy - 26, rx * 0.5, ry * 0.42, r, bumps: 9, bump: 18), .solid(tones.light)),
  ]

  // Fruit hangs from the lower and outer parts of the crown.
  let hang: [(Double, Double)] = (0..<7).map { _ in
    let a = (0.08 + r() * 0.84) * .pi, d = 0.55 + r() * 0.35
    return (cx + cos(a) * rx * d, cy + sin(a) * ry * d)
  }
  return TreeArtResult(back: back, crown: crownOps, hang: hang)
}

/// Real-looking fruit for fruit trees, hanging from a short stem at each
/// point: 0 orange, 1 mango, 2 apple. Green while unripe, colouring as
/// `ripeness` goes from 0 to 1.
func realFruitOps(_ kind: Int, _ points: [(Double, Double)], size: Double, ripeness t: Double, seed: Int) -> [Op] {
  guard size > 0.3 else { return [] }
  let r = Rng(9900 + seed, kind)
  let stemColor = "#6b4a2b", leafColor = "#4f8a3c"
  var ops: [Op] = []
  for (x, y) in points {
    let s = size * (0.88 + r() * 0.24)
    let tilt = (r() - 0.5) * 30
    switch kind {
    case 1:
      // Mango: a slanted teardrop on a long stem, blushing red as it ripens.
      let color = mix("#7fa64a", "#f3b53b", t)
      let cy = y + s * 1.25
      ops.append(.stroke("M\(f(x)) \(f(y - 2)) L\(f(x + 1)) \(f(cy - s * 1.15))", Stroke(color: stemColor, width: 0.9, cap: .round)))
      let body = Op.group(
        [
          .fill(
            "M0 \(f(-s * 1.25)) C\(f(s * 0.95)) \(f(-s * 1.1)) \(f(s * 0.9)) \(f(s * 0.9)) 0 \(f(s * 1.15)) C\(f(-s * 0.85)) \(f(s * 1.1)) \(f(-s * 0.8)) \(f(-s * 1.05)) 0 \(f(-s * 1.25))Z",
            // The blush is part of the shading, so it stays inside the fruit.
            .radial(cx: 0.7, cy: 0.25, r: 0.95, stops: [(0, mix(shade(color, 0.15), "#e0563b", 0.6 * t), 1), (0.5, color, 1), (1, shade(color, -0.18), 1)])),
          .fill(ellipsePath(-s * 0.3, -s * 0.55, s * 0.18, s * 0.3), .solid("#ffffff"), opacity: 0.35),
        ], translate(x + 1, cy).then(rotate(20 + tilt)))
      ops.append(body)
    case 2:
      // Apple: rounded, with the dip at the top, a short stem and a leaf.
      let color = mix("#9cc25a", "#d9453b", t)
      let cy = y + s * 0.95
      ops.append(.stroke("M\(f(x)) \(f(y - 1)) Q\(f(x + 1.5)) \(f(cy - s * 1.1)) \(f(x + 0.5)) \(f(cy - s * 0.65))", Stroke(color: stemColor, width: 1.1, cap: .round)))
      ops.append(
        .fill(
          "M0 \(f(-s * 0.7)) C\(f(s * 0.5)) \(f(-s * 1.15)) \(f(s * 1.2)) \(f(-s * 0.8)) \(f(s * 1.05)) \(f(s * 0.05)) C\(f(s * 0.95)) \(f(s * 0.85)) \(f(s * 0.35)) \(f(s * 1.0)) 0 \(f(s * 0.92)) C\(f(-s * 0.35)) \(f(s * 1.0)) \(f(-s * 0.95)) \(f(s * 0.85)) \(f(-s * 1.05)) \(f(s * 0.05)) C\(f(-s * 1.2)) \(f(-s * 0.8)) \(f(-s * 0.5)) \(f(-s * 1.15)) 0 \(f(-s * 0.7))Z",
          .radial(cx: 0.35, cy: 0.3, r: 0.9, stops: [(0, shade(color, 0.3), 1), (0.6, color, 1), (1, shade(color, -0.22), 1)]),
          translate(x, cy).then(rotate(tilt * 0.4))))
      ops.append(.fill(ellipsePath(x - s * 0.2, cy + s * 0.1, s * 0.12, s * 0.45), .solid("#f2d45c"), opacity: 0.18 * t, rotate(-15, x - s * 0.2, cy + s * 0.1)))
      ops.append(.fill(ellipsePath(x - s * 0.4, cy - s * 0.3, s * 0.2, s * 0.15), .solid("#ffffff"), opacity: 0.4))
      ops.append(.fill(ellipsePath(x + s * 0.55, cy - s * 0.85, s * 0.5, s * 0.2), .solid(leafColor), rotate(-25, x + s * 0.55, cy - s * 0.85)))
    default:
      // Orange: round, a dimpled peel, a green calyx, a stem and a leaf.
      let color = mix("#8fae4a", "#f08a24", t)
      let cy = y + s
      ops.append(.stroke("M\(f(x)) \(f(y - 1)) L\(f(x)) \(f(cy - s * 0.85))", Stroke(color: stemColor, width: 1, cap: .round)))
      ops.append(
        .fill(
          circlePath(x, cy, s),
          .radial(cx: 0.36, cy: 0.32, r: 0.85, stops: [(0, shade(color, 0.35), 1), (0.6, color, 1), (1, shade(color, -0.2), 1)])))
      for _ in 0..<5 {
        let a = r() * 2 * .pi, d = s * (0.3 + r() * 0.5)
        ops.append(.fill(circlePath(x + cos(a) * d, cy + sin(a) * d, s * 0.06), .solid(shade(color, -0.15)), opacity: 0.6))
      }
      ops.append(.fill(ellipsePath(x - s * 0.35, cy - s * 0.38, s * 0.24, s * 0.18), .solid("#ffffff"), opacity: 0.4))
      ops.append(.fill(ellipsePath(x, cy - s * 0.88, s * 0.28, s * 0.13), .solid("#4c6e2c")))
      ops.append(.fill(ellipsePath(x + s * 0.55, cy - s * 0.95, s * 0.5, s * 0.2), .solid(leafColor), rotate(-30, x + s * 0.55, cy - s * 0.95)))
    }
  }
  return ops
}

// MARK: - Tall rainforest tree

/// An emergent rainforest tree: a tall trunk on buttress roots and a wide,
/// flat, layered canopy, its top near 370 units up.
func tallTreeArt(_ p: PlantSpec, _ pal: Palette) -> TreeArtResult {
  let variant = p.id % TREE_VARIANTS
  let r = Rng(9700 + p.form * 10 + variant, 1, 7)
  let tones = leafTones(pal, leafBucket(p.hue))
  let bark = pal.trunk
  let top = p.form == 1 ? -325.0 : p.form == 2 ? -280 : -300
  var back: [Op] = [
    .fill("M-9 0 Q-5 \(f(top * 0.5)) -4 \(f(top)) L4 \(f(top)) Q5 \(f(top * 0.5)) 9 0Z", .solid(bark)),
    // Buttress roots flaring out at the base.
    .fill("M-9 0 Q-18 -6 -30 1 Q-14 -16 -7 -46Z M9 0 Q18 -6 30 1 Q14 -16 7 -46Z", .solid(shade(bark, -0.12))),
    .stroke("M-1 -10 Q1 \(f(top * 0.5)) 0 \(f(top + 20))", Stroke(color: shade(bark, 0.15), width: 2, cap: .round), opacity: 0.4),
  ]
  // A few bare side branches partway up, as emergent trees have.
  for k in 0..<2 {
    let y = top * (0.55 + Double(k) * 0.15)
    let s = k == 0 ? -1.0 : 1.0
    back.append(.stroke("M0 \(f(y)) q\(f(s * 14)) -8 \(f(s * 30)) -20", Stroke(color: bark, width: 3, cap: .round)))
  }
  // Limbs fanning out under the canopy layers.
  for a in [-150.0, -120, -60, -30] {
    let rad = (a + (r() - 0.5) * 10) * .pi / 180
    back.append(.stroke("M0 \(f(top + 4)) l\(f(cos(rad) * 70)) \(f(sin(rad) * 34))", Stroke(color: bark, width: 4, cap: .round)))
  }
  let y0 = top - 16
  let clouds: [(c: CGPoint, r: Double)] = [
    (CGPoint(x: -58 - r() * 10, y: y0 + 8), 44 + r() * 8),
    (CGPoint(x: 58 + r() * 10, y: y0 + 6), 42 + r() * 8),
    (CGPoint(x: (r() - 0.5) * 20, y: y0 - 10), 62 + r() * 8),
    (CGPoint(x: -30 + r() * 10, y: y0 - 42 - r() * 8), 42 + r() * 6),
    (CGPoint(x: 26 + r() * 10, y: y0 - 38 - r() * 8), 36 + r() * 6),
  ]
  let hang = hangingPoints(clouds, r, count: 7)
  return TreeArtResult(back: back, crown: crown(clouds, tones, r, flatten: 0.45), hang: hang)
}

/// Hanging vines from a tall tree's canopy, growing with `vine` (0 to 1).
func tallTreeVines(_ p: PlantSpec, _ pal: Palette, _ vine: Double) -> [Op] {
  guard vine > 0 else { return [] }
  let top = p.form == 1 ? -325.0 : p.form == 2 ? -280 : -300
  let r = Rng(9750 + p.id % TREE_VARIANTS, 2)
  let color = shade(pal.leafMid, -0.1)
  return (0..<4).map { i in
    let x = -70 + Double(i) * 45 + (r() - 0.5) * 16
    let len = 30 + vine * (80 + r() * 50)
    return .stroke(
      "M\(f(x)) \(f(top + 2)) q6 \(f(len * 0.25)) 0 \(f(len * 0.5)) q-6 \(f(len * 0.25)) 0 \(f(len * 0.5))",
      Stroke(color: color, width: 1.5, cap: .round))
  }
}

// MARK: - Palm

/// A palm's crown: feathery fronds of many leaflets along drooping stems.
/// `fronds` is (angle, mirror) pairs, as before, so the silhouette stays familiar.
func palmFronds(_ p: PlantSpec, _ pal: Palette, center: CGPoint, fronds: [(Double, Double)]) -> [Op] {
  let tones = leafTones(pal, leafBucket(p.hue))
  let r = Rng(9800 + p.id % TREE_VARIANTS, 1)
  var back: [Op] = []
  var front: [Op] = []
  for (i, (angle, mirror)) in fronds.enumerated() {
    let len = 92 + r() * 16
    let droop = 0.28 + r() * 0.12
    // The frond's stem: out, up a little, then drooping at the tip.
    func stem(_ t: Double) -> CGPoint {
      let u = 1 - t
      let c = CGPoint(x: len * 0.5, y: -len * 0.32)
      let e = CGPoint(x: len, y: len * droop)
      return CGPoint(x: 2 * u * t * c.x + t * t * e.x, y: 2 * u * t * c.y + t * t * e.y)
    }
    // Fronds pointing back and down are drawn first and darker.
    let behind = i % 3 == 2
    let color = behind ? tones.dark : i % 2 == 0 ? tones.mid : mix(tones.mid, tones.light, 0.5)
    var ops: [Op] = []
    var d = "M0 0"
    for k in 1...12 {
      let pt = stem(Double(k) / 12)
      d += " L\(f(pt.x)) \(f(pt.y))"
    }
    ops.append(.stroke(d, Stroke(color: shade(color, -0.2), width: 1.6, cap: .round)))
    var t = 0.08
    while t < 0.97 {
      let a = stem(t), b = stem(min(1, t + 0.02))
      let ax = Double(a.x), ay = Double(a.y)
      let dir = atan2(Double(b.y) - ay, Double(b.x) - ax)
      let leaflet = 6 + 20 * pow(sin(.pi * t), 0.7)
      for side in [-1.0, 1.0] {
        // Leaflets angle forward and hang a little under their own weight.
        let la = dir + side * 1.1 + 0.25
        let tx = ax + cos(la) * leaflet, ty = ay + sin(la) * leaflet + leaflet * 0.25
        let mx = (ax + tx) / 2 + cos(dir) * 3, my = (ay + ty) / 2 + 2
        ops.append(
          .stroke(
            "M\(f(ax)) \(f(ay)) Q\(f(mx)) \(f(my)) \(f(tx)) \(f(ty))",
            Stroke(color: side > 0 ? color : shade(color, -0.08), width: 2.4, cap: .round)))
      }
      t += 0.045
    }
    let group = Op.group(ops, translate(center.x, center.y).then(scale(mirror, 1)).then(rotate(angle)))
    if behind { back.append(group) } else { front.append(group) }
  }
  return back + front
}
