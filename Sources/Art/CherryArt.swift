import CoreGraphics

/// Cherry trees come in a few shapes per form, so a grove does not repeat.
let CHERRY_VARIANTS = 4

private struct Cluster {
  var center: CGPoint
  var radius: Double
}

/// A cherry tree's branches and the clumps of blossom or leaves they carry.
private struct CherryShape {
  var limbs: [(d: String, width: Double)] = []
  var twigs: [String] = []
  var clusters: [Cluster] = []
  var top = 0.0
  var bottom = 0.0
}

/// Builds the skeleton for one form and variant: a gnarled trunk forking into
/// spreading limbs, each with a side branch and clumps at the tips.
private func cherryShape(form: Int, variant: Int) -> CherryShape {
  let r = Rng(9000 + form * 10 + variant, 1, 3)
  var shape = CherryShape()
  let fork = CGPoint(x: -6 + r() * 12, y: -104 - r() * 12)
  let limbs = 5 + Int(r() * 2)
  for i in 0..<limbs {
    // Spread from up-left to up-right, wider than tall, like a sakura.
    let t = Double(i) / Double(limbs - 1)
    let angle = (-162 + t * 144 + (r() - 0.5) * 14) * .pi / 180
    // Reaches about 260 units up at the top, where birds perch.
    let length = 76 + r() * 36 - abs(t - 0.5) * 16
    let tip = CGPoint(x: fork.x + cos(angle) * length * 0.95, y: fork.y + sin(angle) * length)
    let bend = CGPoint(x: fork.x + cos(angle) * length * 0.5 + (r() - 0.5) * 14, y: fork.y + sin(angle) * length * 0.5 - 6)
    shape.limbs.append(("M\(f(fork.x)) \(f(fork.y)) Q\(f(bend.x)) \(f(bend.y)) \(f(tip.x)) \(f(tip.y))", 5.2))
    // A side branch from partway along.
    let mid = CGPoint(x: (fork.x + 2 * bend.x + tip.x) / 4, y: (fork.y + 2 * bend.y + tip.y) / 4)
    let side = angle + (r() < 0.5 ? -1 : 1) * (0.45 + r() * 0.3)
    let sideTip = CGPoint(x: mid.x + cos(side) * length * 0.48, y: mid.y + sin(side) * length * 0.42)
    shape.limbs.append(("M\(f(mid.x)) \(f(mid.y)) L\(f(sideTip.x)) \(f(sideTip.y))", 2.6))
    // Twigs fanning from the tips.
    for k in 0..<3 {
      let a = angle + (Double(k) - 1) * 0.5 + (r() - 0.5) * 0.3
      let l = 10 + r() * 10
      shape.twigs.append("M\(f(tip.x)) \(f(tip.y)) l\(f(cos(a) * l)) \(f(sin(a) * l))")
    }
    shape.clusters.append(Cluster(center: tip, radius: 24 + r() * 10))
    shape.clusters.append(Cluster(center: sideTip, radius: 16 + r() * 8))
    if r() < 0.6 {
      shape.clusters.append(Cluster(center: CGPoint(x: (mid.x + tip.x) / 2, y: (mid.y + tip.y) / 2 - 6), radius: 15 + r() * 7))
    }
  }
  shape.top = shape.clusters.map { $0.center.y - $0.radius }.min() ?? -250
  shape.bottom = shape.clusters.map { $0.center.y + $0.radius }.max() ?? -100
  return shape
}

private var shapes: [Int: CherryShape] = [:]
private func shapeFor(form: Int, variant: Int) -> CherryShape {
  let key = form * 100 + variant
  if let s = shapes[key] { return s }
  let s = cherryShape(form: form, variant: variant)
  shapes[key] = s
  return s
}

/// One soft cloud of blossom or leaves: the union of a few overlapping
/// circles, so its edge is gently scalloped but it reads as one mass.
private func cloud(_ c: Cluster, _ r: Rng) -> CGPath {
  let path = CGMutablePath()
  for _ in 0..<(7 + Int(c.radius / 6)) {
    let a = r() * 2 * .pi
    let d = c.radius * r().squareRoot() * 0.6
    let rr = c.radius * (0.38 + r() * 0.2)
    path.addEllipse(in: CGRect(x: c.center.x + cos(a) * d - rr, y: c.center.y + sin(a) * d * 0.8 - rr, width: 2 * rr, height: 2 * rr))
  }
  return path
}

/// A soft sheen on the sunlit top of a cloud, diffuse rather than glossy.
private func sheen(_ c: Cluster, _ r: Rng, _ color: String, _ strength: Double) -> Op {
  let a = -.pi / 2 + (r() - 0.5) * 1.2
  return .fill(
    ellipsePath(c.center.x + cos(a) * c.radius * 0.35, c.center.y + sin(a) * c.radius * 0.35, c.radius * 0.6, c.radius * 0.42),
    .radial(cx: 0.5, cy: 0.5, r: 0.5, stops: [(0, color, strength), (1, color, 0)]))
}

/// A cherry tree with its base at (0, 0). Blossom (`s.sakura`) and leaves
/// (`s.foliage`) fade independently, so the tree moves from bare branches to
/// full bloom, to green leaves with cherries, to autumn colour and back.
func cherryOps(_ p: PlantSpec, _ s: PlantState, _ pal: Palette, fruitFill: String) -> [Op] {
  let variant = p.id % CHERRY_VARIANTS
  let shape = shapeFor(form: p.form, variant: variant)
  let bark = shade(pal.trunk, -0.22)
  let barkLight = shade(pal.trunk, 0.12)
  var ops: [Op] = []

  // Fallen petals around the foot of the tree in full bloom.
  if s.sakura > 0.3 {
    let r = Rng(9200 + variant, 2)
    for _ in 0..<26 {
      let x = (r() - 0.5) * 150, y = (r() - 0.5) * 7
      ops.append(.fill(ellipsePath(x, y, 1.8, 1), .solid(r() < 0.5 ? "#f7c6d6" : "#fde6ee"), opacity: (s.sakura - 0.3) * 1.3))
    }
  }

  // A gnarled trunk with the horizontal bark bands cherries have.
  ops.append(.fill("M-12 0 Q-3 -40 -12 -78 Q-17 -100 -6 -116 L6 -116 Q-2 -96 8 -76 Q16 -40 12 0Z", .solid(bark)))
  ops.append(.stroke("M-3 -10 Q2 -50 -4 -100", Stroke(color: barkLight, width: 2.4, cap: .round), opacity: 0.35))
  for y in stride(from: -14.0, through: -104, by: -15) {
    ops.append(.stroke("M-6 \(f(y)) l9 -1", Stroke(color: barkLight, width: 1.1, cap: .round), opacity: 0.55))
  }

  var inner: [Op] = []
  for limb in shape.limbs {
    inner.append(.stroke(limb.d, Stroke(color: bark, width: limb.width, cap: .round)))
  }
  for twig in shape.twigs { inner.append(.stroke(twig, Stroke(color: bark, width: 1.3, cap: .round))) }

  // Each cloud is wholly blossom, wholly leaf, or gone, never a see-through
  // mix: as spring ends more clouds turn green, and in winter they drop away.
  let r = Rng(9300 + variant, 3)
  var shadows: [Op] = []
  var clouds: [Op] = []
  var details: [Op] = []
  for c in shape.clusters.sorted(by: { $0.center.y < $1.center.y }) {
    let path = cloud(c, r)
    let stays = r(), blooms = r()
    // Fully bare by deep winter, when foliage bottoms out at 0.1.
    let leafy = (s.foliage - 0.1) / 0.9
    guard stays < leafy || blooms < s.sakura * leafy else { continue }
    if blooms < s.sakura {
      shadows.append(.fill(path, .solid("#c27c98"), opacity: 0.5, translate(2, 4)))
      clouds.append(.fill(path, .vertical([(0, "#ffeef3", 1), (0.45, "#f7c3d3", 1), (1, "#e293b0", 1)])))
      details.append(sheen(c, r, "#fff8fa", 0.5))
      // A scatter of petals, deeper pink and white, for texture.
      for _ in 0..<7 {
        let a = r() * 2 * .pi, d = c.radius * r() * 0.8
        details.append(.fill(circlePath(c.center.x + cos(a) * d, c.center.y + sin(a) * d * 0.8, 1.2), .solid(r() < 0.5 ? "#d67597" : "#ffffff"), opacity: 0.75))
      }
    } else {
      shadows.append(.fill(path, .solid(shade(pal.leafDark, -0.25)), opacity: 0.5, translate(2, 4)))
      clouds.append(.fill(path, .vertical([(0, shade(pal.leafLight, 0.08), 1), (0.5, pal.leafMid, 1), (1, pal.leafDark, 1)])))
      details.append(sheen(c, r, shade(pal.leafLight, 0.35), 0.35))
    }
  }
  inner += shadows + clouds + details

  // Cherries hang in pairs below the clumps in summer.
  if s.fruitSize > 0.01 {
    let r = Rng(9400 + variant, 4)
    for c in shape.clusters where r() < 0.8 {
      let x = c.center.x + (r() - 0.5) * c.radius, y = c.center.y + c.radius * 0.6
      inner.append(
        .stroke("M\(f(x)) \(f(y - 9)) L\(f(x - 3)) \(f(y)) M\(f(x)) \(f(y - 9)) L\(f(x + 3)) \(f(y + 1))", Stroke(color: "#5b4a2a", width: 0.8)))
      inner.append(.fill(circlePath(x - 3, y, 3.2 * s.fruitSize), .solid(fruitFill)))
      inner.append(.fill(circlePath(x + 3, y + 1, 3.2 * s.fruitSize), .solid(fruitFill)))
    }
  }

  let form = p.form == 1 ? scale(1.18, 0.92) : p.form == 2 ? scale(0.84, 1.1) : .identity
  ops.append(.group(inner, form))
  return ops
}
