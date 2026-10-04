import QuartzCore

/// Ground animals and rare sky events. Everything is built once as Core
/// Animation layers and loops, then only shown, hidden or faded per update,
/// so wildlife adds no work for the app between clock ticks.
@MainActor
final class Wildlife {
  private let bands: [CALayer]
  /// In the sky, behind clouds and hills.
  private let sky: CALayer
  /// Above all plants, below the canopy.
  private let air: CALayer
  private let density: (Double) -> Double

  private var seed = -1
  private var animals: [String: CALayer] = [:]
  private let meteors = CALayer()
  private let aurora = CALayer()
  private let comet = CALayer()
  private let flock = CALayer()
  private let butterflies = CALayer()

  init(bands: [CALayer], sky: CALayer, air: CALayer, density: @escaping (Double) -> Double) {
    self.bands = bands
    self.sky = sky
    self.air = air
    self.density = density
    aurora.compositingFilter = "screenBlendMode"
    comet.compositingFilter = "screenBlendMode"
    meteors.compositingFilter = "screenBlendMode"
    for l in [aurora, comet, meteors] { sky.addSublayer(l) }
    for l in [butterflies, flock] { air.addSublayer(l) }
  }

  /// Drops every layer, to be rebuilt for a new seed or resolution.
  func reset() {
    for l in animals.values { l.removeFromSuperlayer() }
    animals.removeAll()
    for l in [meteors, aurora, comet, flock, butterflies] { l.sublayers?.forEach { $0.removeFromSuperlayer() } }
    seed = -1
  }

  func update(_ input: SceneInput) {
    if input.seed != seed {
      reset()
      seed = input.seed
      buildSky()
      buildAir()
    }
    let e = input.events
    let w = input.season.weights
    let night = input.day.night

    for (i, sp) in ANIMALS.enumerated() where input.focus >= sp.unlockAt {
      let layer = animals[sp.id] ?? addAnimal(i)
      let wanted: Float = sp.id == "tiger" && !e.tiger ? 0 : 1
      if layer.opacity != wanted {
        // A slow fade in or out while running. The scene's clock is frozen
        // while stopped, so then the change is immediate.
        if input.running {
          transaction(2.5) { layer.opacity = wanted }
        } else {
          layer.opacity = wanted
        }
      }
    }
    for (id, layer) in animals where input.focus < ANIMALS.first(where: { $0.id == id })!.unlockAt {
      layer.removeFromSuperlayer()
      animals[id] = nil
    }

    show(meteors, e.shootingStars, night * (1 - w[MONSOON]))
    show(aurora, e.aurora, night)
    show(comet, e.comet, night)
    show(flock, e.flock, 1)
    show(butterflies, e.butterflies, input.day.day)
  }

  private func show(_ layer: CALayer, _ on: Bool, _ opacity: Double) {
    layer.isHidden = !on
    layer.opacity = Float(opacity)
  }

  // MARK: - Animals

  private struct Rig {
    let root = CALayer()
    let inner = CALayer()
    var behind: [CALayer] = []
    var legs: [CALayer] = []
    var front: [CALayer] = []
  }

  /// Builds an animal's layers at `scale`, facing right, or left if `flip` is -1.
  private func rig(_ art: AnimalArt, scale s: Double, flip: Double = 1) -> Rig {
    var r = Rig()
    r.root.transform = CATransform3DMakeScale(s * flip, s, 1)
    r.root.addSublayer(r.inner)
    let px = density(s)
    r.behind = art.behind.map { r.inner.addSprite(render($0.ops, pixelsPerUnit: px), pivot: $0.pivot) }
    r.legs = art.legs.map { r.inner.addSprite(render($0.ops, pixelsPerUnit: px), pivot: $0.pivot) }
    _ = r.inner.addSprite(render(art.body, pixelsPerUnit: px))
    r.front = art.front.map { r.inner.addSprite(render($0.ops, pixelsPerUnit: px), pivot: $0.pivot) }
    return r
  }

  /// Swings walking legs in diagonal pairs, like a real gait.
  private func walk(_ legs: [CALayer], angle: Double, period: Double) {
    for (i, leg) in legs.enumerated() {
      let offbeat = i == 1 || i == 2
      leg.loop(swing("transform.rotation.z", from: -angle, to: angle, duration: period), key: "step", delay: offbeat ? -period : 0)
    }
  }

  /// Moves `layer` along x from `from` to `to` over `share` of each `period`,
  /// then keeps it off screen until the next crossing.
  private func cross(_ layer: CALayer, from: Double, to: Double, period: Double, share: Double, delay: Double) {
    let a = CAKeyframeAnimation(keyPath: "position.x")
    a.values = [from, to, to]
    a.keyTimes = [0, NSNumber(value: share), 1]
    a.duration = period
    // Mid-crossing at rest, so snapshots (which skip animations) show the walker.
    layer.position.x = (from + to) / 2
    layer.loop(a, key: "cross", delay: delay)
  }

  private func addAnimal(_ index: Int) -> CALayer {
    let sp = ANIMALS[index]
    let r = Rng(seed, 900 + index)
    let holder = CALayer()
    var depth = 0.5

    switch sp.id {
    case "rabbit":
      depth = 0.95 + r() * 0.04
      let hare = rig(hareArt(), scale: depthToScale(depth))
      holder.position = CGPoint(x: 330 + r() * 110, y: depthToY(depth))
      holder.addSublayer(hare.root)
      // Sits, hops off to the right, sits, turns and hops back.
      let hx = CAKeyframeAnimation(keyPath: "transform.translation.x")
      hx.values = [0, 0, 22, 22, 0, 0]
      hx.keyTimes = [0, 0.3, 0.4, 0.7, 0.8, 1]
      let hy = CAKeyframeAnimation(keyPath: "transform.translation.y")
      hy.values = [0, 0, -10, 0, 0, -10, 0, 0]
      hy.keyTimes = [0, 0.3, 0.35, 0.4, 0.7, 0.75, 0.8, 1]
      let face = CAKeyframeAnimation(keyPath: "transform.scale.x")
      face.values = [1, -1, 1]
      face.keyTimes = [0, 0.62, 0.95, 1]
      face.calculationMode = .discrete
      let hop = CAAnimationGroup()
      hop.animations = [hx, hy, face]
      hop.duration = 16
      for a in [hx, hy, face] { a.duration = 16 }
      hare.inner.loop(hop, key: "hop", delay: -r() * 16)

    case "peacock":
      depth = 0.9 + r() * 0.05
      let bird = rig(peacockArt(), scale: depthToScale(depth) * 1.1, flip: -1)
      holder.position = CGPoint(x: 1190 + r() * 160, y: depthToY(depth))
      holder.addSublayer(bird.root)
      let peck = CAKeyframeAnimation(keyPath: "transform.rotation.z")
      peck.values = [0, 0, 0.35, 0, 0]
      peck.keyTimes = [0, 0.7, 0.75, 0.8, 1]
      peck.duration = 8
      bird.inner.loop(peck, key: "peck", delay: -r() * 8)
      // The train stays folded most of the time, then opens in a full display.
      let fan = CAKeyframeAnimation(keyPath: "transform.scale")
      fan.values = [0.05, 0.05, 1, 1, 0.05, 0.05]
      fan.keyTimes = [0, 0.55, 0.62, 0.85, 0.92, 1]
      fan.duration = 40
      fan.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      bird.behind[0].transform = CATransform3DMakeScale(0.05, 0.05, 1)
      bird.behind[0].loop(fan, key: "display", delay: -r() * 40)

    case "deer":
      depth = 0.8 + r() * 0.04
      let s = depthToScale(depth)
      let x = 140 + r() * 120
      holder.position = CGPoint(x: x, y: depthToY(depth))
      for (stag, dx, flip, size) in [(true, 0.0, 1.0, 1.0), (false, 70, -1, 0.9)] {
        let deer = rig(deerArt(stag: stag), scale: s * size, flip: flip)
        deer.root.position = CGPoint(x: dx, y: 0)
        holder.addSublayer(deer.root)
        // Lowers its head to graze, then looks up.
        let graze = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        graze.values = [0, 0, 0.85, 0.85, 0, 0]
        graze.keyTimes = [0, 0.3, 0.38, 0.75, 0.83, 1]
        graze.duration = 14
        graze.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        deer.front[0].loop(graze, key: "graze", delay: -r() * 14)
      }

    case "elephant":
      // Far off along the horizon, glimpsed through the trees and mist.
      depth = 0.01 + r() * 0.03
      let s = depthToScale(depth) * 1.35
      holder.position = CGPoint(x: -260, y: depthToY(depth))
      for (dx, size) in [(0.0, 1.0), (-95, 0.55)] {
        let e = rig(elephantArt(), scale: s * size)
        e.root.position = CGPoint(x: dx * s, y: 0)
        holder.addSublayer(e.root)
        walk(e.legs, angle: 0.12, period: 1.2 / size.squareRoot())
        e.inner.loop(swing("transform.translation.y", from: 0, to: -1.5, duration: 0.6), key: "bob")
        e.front[0].loop(swing("transform.rotation.z", from: -0.12, to: 0.08, duration: 3), key: "ear")
      }
      cross(holder, from: -260, to: 1860, period: 520, share: 0.7, delay: -r() * 520)

    default:  // tiger
      depth = 0.9 + r() * 0.04
      let t = rig(tigerArt(), scale: depthToScale(depth) * 1.15, flip: -1)
      holder.position = CGPoint(x: 1900, y: depthToY(depth))
      holder.addSublayer(t.root)
      walk(t.legs, angle: 0.28, period: 0.7)
      t.inner.loop(swing("transform.translation.y", from: 0, to: -1.2, duration: 0.35), key: "bob")
      cross(holder, from: 1900, to: -300, period: 170, share: 0.55, delay: -r() * 170)
    }

    holder.opacity = 0
    // In a grown jungle, plants would hide animals at their true depth, so
    // the near ones stand in front of the foliage and the elephants walk
    // behind every tree.
    if sp.id == "elephant" {
      bands[0].insert(holder, sortY: -1)
    } else {
      bands[2].insert(holder, sortY: 10_000 + depthToY(depth))
    }
    animals[sp.id] = holder
    return holder
  }

  // MARK: - Sky

  private func buildSky() {
    let px = density(1)

    let streak = render(meteorOps(), pixelsPerUnit: px)
    for (i, (x, y, period)) in [(1300.0, 60.0, 53.0), (700, 90, 89), (1500, 140, 131)].enumerated() {
      let m = meteors.addSprite(streak)
      m.transform = CATransform3DMakeRotation(60 * .pi / 180, 0, 0, 1)
      m.opacity = 0
      let path = CABasicAnimation(keyPath: "position")
      path.fromValue = NSValue(point: CGPoint(x: x, y: y))
      path.toValue = NSValue(point: CGPoint(x: x - 260, y: y + 150))
      path.duration = 1.1
      let glow = CAKeyframeAnimation(keyPath: "opacity")
      glow.values = [0, 1, 0.9, 0]
      glow.keyTimes = [0, 0.15, 0.7, 1]
      glow.duration = 1.1
      // A brief streak, then a long wait before the next one.
      let g = CAAnimationGroup()
      g.animations = [path, glow]
      g.duration = period
      m.loop(g, key: "meteor", delay: Double(-i) * 19)
    }

    for (i, (color, y)) in [("#5ef2a2", 190.0), ("#49c9e0", 230), ("#b07be8", 165)].enumerated() {
      let curtain = aurora.addSprite(render(auroraOps(color, width: 1800, phase: Double(i) * 2.1, height: 170), pixelsPerUnit: px * 0.5))
      curtain.position = CGPoint(x: -100, y: y)
      curtain.loop(swing("transform.translation.x", from: -70, to: 70, duration: 46 + Double(i) * 9), key: "drift")
      curtain.loop(swing("opacity", from: 0.55, to: 1, duration: 11 + Double(i) * 3), key: "glow", delay: Double(-i) * 4)
    }

    let c = comet.addSprite(render(cometOps(), pixelsPerUnit: px))
    c.position = CGPoint(x: 1180, y: 150)
    c.loop(swing("transform.translation.x", from: 0, to: -40, duration: 300), key: "drift")
  }

  // MARK: - Air

  private func buildAir() {
    let px = density(1)
    let r = Rng(seed, 950)

    // A V of migrating birds crossing autumn skies every couple of minutes.
    let v = CALayer()
    let bird = render(flockBirdOps(), pixelsPerUnit: px * 1.5)
    for k in 0..<9 {
      let side = k == 0 ? 0.0 : (k % 2 == 1 ? 1.0 : -1.0)
      let rank = Double((k + 1) / 2)
      let b = v.addSprite(bird)
      b.position = CGPoint(x: rank * 16, y: side * rank * 9)
      b.loop(swing("transform.scale.y", from: 1, to: -0.6, duration: 0.45), key: "flap", delay: -Double(k) * 0.13)
    }
    v.position = CGPoint(x: 1750, y: 150)
    let fly = CAKeyframeAnimation(keyPath: "position")
    fly.values = [CGPoint(x: 1750, y: 150), CGPoint(x: -200, y: 105), CGPoint(x: -200, y: 105)].map { NSValue(point: $0) }
    fly.keyTimes = [0, 0.35, 1]
    fly.duration = 150
    v.loop(fly, key: "migrate", delay: -r() * 150)
    flock.addSublayer(v)

    // Butterflies wandering over the meadow and the flowers on the right.
    let colors = ["#f2b84b", "#e86f9a", "#7fc4e8", "#f7f3e6", "#f2b84b", "#b48be0"]
    for (i, color) in colors.enumerated() {
      let homeX = i < 3 ? 80 + r() * 320 : 1140 + r() * 340
      let homeY = 700 + r() * 140
      let wander = CGMutablePath()
      let points = (0..<6).map { _ in CGPoint(x: homeX + (r() - 0.5) * 140, y: homeY + (r() - 0.5) * 70) }
      wander.move(to: points[0])
      for k in 1...points.count {
        let p = points[k % points.count]
        let prev = points[k - 1]
        wander.addQuadCurve(to: p, control: CGPoint(x: (prev.x + p.x) / 2 + (r() - 0.5) * 60, y: min(prev.y, p.y) - 30))
      }
      let fly = CALayer()
      fly.position = points[0]
      let path = CAKeyframeAnimation(keyPath: "position")
      path.path = wander
      path.calculationMode = .paced
      path.duration = 22 + r() * 10
      fly.loop(path, key: "wander", delay: -r() * 30)
      let wings = fly.addSprite(render(butterflyOps(color), pixelsPerUnit: px * 2))
      wings.loop(swing("transform.scale.x", from: 1, to: 0.25, duration: 0.18), key: "flap", delay: -r())
      butterflies.addSublayer(fly)
    }
  }
}
