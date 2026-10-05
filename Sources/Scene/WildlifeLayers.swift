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

  /// Runs `m` on an animal: `mover` follows its path with its feet on `y`,
  /// the rig turns to face its way and walks with `gait`, and each of `tracks`
  /// (layer, track name, key path) plays a named track.
  private func play(
    _ m: Roam, mover: CALayer, y: Double, rig: Rig, scale s: Double, gait: Gait? = nil,
    tracks: [(CALayer, String, String)] = [], delay: Double
  ) {
    // At rest at its starting spot, so snapshots (which skip animations) show it.
    mover.position = CGPoint(x: m.start, y: y)
    mover.loop(m.position(y: y), key: "roam", delay: delay)
    if let face = m.track("face", "transform.scale.x", scale: s, eased: false) { rig.root.loop(face, key: "face", delay: delay) }
    if let gait {
      for (leg, a) in zip(rig.legs, m.legs(gait, scale: s)) { leg.loop(a, key: "step", delay: delay) }
    }
    for (layer, name, path) in tracks {
      if let a = m.track(name, path) { layer.loop(a, key: name, delay: delay) }
    }
  }

  private func addAnimal(_ index: Int) -> CALayer {
    let sp = ANIMALS[index]
    let r = Rng(seed, 900 + index)
    let holder = CALayer()
    var depth = 0.5

    switch sp.id {
    case "rabbit":
      // A few hares about the meadow, each keeping to its own patch. Drawn
      // back to front, so nearer ones pass in front.
      let depths = (0..<3).map { _ in 0.9 + r() * 0.09 }.sorted()
      depth = depths.last!
      for (k, d) in depths.enumerated() {
        let s = depthToScale(d) * (0.9 + r() * 0.2)
        let hare = rig(hareArt(), scale: s)
        let mover = CALayer()
        mover.addSublayer(hare.root)
        holder.addSublayer(mover)
        let m = hareRoam(home: [180, 380, 580][k] + (r() - 0.5) * 80, scale: s, r)
        play(
          m, mover: mover, y: depthToY(d), rig: hare, scale: s,
          tracks: [
            (hare.front[0], "ear", "transform.rotation.z"), (hare.behind[0], "earBack", "transform.rotation.z"),
            (hare.inner, "stretch", "transform.scale.y"),
          ], delay: -r() * m.period)
      }

    case "peacock":
      depth = 0.9 + r() * 0.05
      let s = depthToScale(depth) * 1.1
      let bird = rig(peacockArt(), scale: s, flip: -1)
      holder.addSublayer(bird.root)
      bird.behind[0].transform = CATransform3DMakeScale(0.05, 0.05, 1)
      let gait = Gait.twoLegged(duty: 0.6, swing: 0.4, length: 10)
      let m = peacockRoam(home: 1190 + r() * 160, stride: gait.stride * s, scale: s, r)
      play(
        m, mover: holder, y: depthToY(depth), rig: bird, scale: s, gait: gait,
        tracks: [
          (bird.inner, "lean", "transform.rotation.z"), (bird.front[0], "neck", "transform.rotation.z"),
          (bird.behind[0], "fanAngle", "transform.rotation.z"), (bird.behind[0], "fanWidth", "transform.scale.x"),
          (bird.behind[0], "fanHeight", "transform.scale.y"),
        ], delay: -r() * m.period)

    case "deer":
      depth = 0.8 + r() * 0.04
      let s = depthToScale(depth)
      let x = 140 + r() * 120
      holder.position = CGPoint(x: x, y: depthToY(depth))
      let gait = Gait.fourLegged(duty: 0.65, swing: 0.22, length: 25)
      for (stag, dx, flip, size) in [(true, 0.0, 1.0, 1.0), (false, 70, -1, 0.9)] {
        let deer = rig(deerArt(stag: stag), scale: s * size, flip: flip)
        holder.addSublayer(deer.root)
        let m = deerRoam(home: dx, facing: flip, stride: gait.stride * s * size, r)
        play(
          m, mover: deer.root, y: 0, rig: deer, scale: s * size, gait: gait,
          tracks: [(deer.front[0], "head", "transform.rotation.z"), (deer.front[1], "tail", "transform.rotation.z")],
          delay: -r() * m.period)
      }

    case "elephant":
      // Far off along the horizon, glimpsed through the trees and mist.
      depth = 0.01 + r() * 0.03
      let s = depthToScale(depth) * 1.35
      let gait = Gait.fourLegged(duty: 0.65, swing: 0.16, length: 30)
      var m = Roam(x: -260, facing: 1, stride: gait.stride * s, rate: 6)
      // Crosses the hills slowly, stopping once or twice to browse, then is
      // away for a while before the next crossing.
      let speed = m.stride / 2.2
      var stops = [300 + r() * 400]
      if r() < 0.6 { stops.append(950 + r() * 400) }
      for stop in stops + [1900] {
        m.walk(m.strides(to: stop), speed: speed, ease: 1.5, bob: 0.8 * s)
        if stop < 1900 { m.wait(10 + r() * 15) }
      }
      m.wait(max(60, 520 - m.t))
      m.jump(to: -260)
      let delay = -r() * m.period
      for (dx, size) in [(0.0, 1.0), (-95, 0.55)] {
        let e = rig(elephantArt(), scale: s * size)
        e.root.position = CGPoint(x: dx * s, y: 0)
        holder.addSublayer(e.root)
        // The calf takes quicker steps to keep up.
        for (leg, a) in zip(e.legs, m.legs(gait, scale: s * size)) { leg.loop(a, key: "step", delay: delay) }
        e.front[0].loop(swing("transform.rotation.z", from: -0.12, to: 0.08, duration: 3 * size.squareRoot()), key: "ear", delay: -r() * 3)
        e.front[1].loop(swing("transform.rotation.z", from: -0.1, to: 0.08, duration: 2.6), key: "trunk", delay: -r() * 3)
      }
      holder.position = CGPoint(x: 800, y: depthToY(depth))
      holder.loop(m.position(y: depthToY(depth)), key: "roam", delay: delay)

    default:  // tiger
      depth = 0.9 + r() * 0.04
      let s = depthToScale(depth) * 1.15
      let t = rig(tigerArt(), scale: s, flip: -1)
      holder.addSublayer(t.root)
      let gait = Gait.fourLegged(duty: 0.62, swing: 0.3, length: 26)
      var m = Roam(x: 1900, facing: -1, stride: gait.stride * s, rate: 15)
      m.set("head", 0)
      // Pads in from the right, stops to sniff and look about, moves on,
      // pauses once more and slips out to the left.
      let speed = m.stride / 1.3
      m.walk(m.strides(to: 1150 + r() * 250), speed: speed, bob: 1.2 * s)
      m.ease("head", to: 0.3, over: 0.6)
      m.wait(2.5 + r() * 2)
      m.ease("head", to: -0.1, over: 0.7)
      m.wait(2.5 + r() * 2.5)
      m.ease("head", to: 0, over: 0.5)
      m.wait(0.6)
      m.walk(m.strides(to: 500 + r() * 300), speed: speed, bob: 1.2 * s)
      m.ease("head", to: -0.08, over: 0.6)
      m.wait(2 + r() * 2)
      m.ease("head", to: 0, over: 0.5)
      m.wait(0.5)
      m.walk(m.strides(to: -300), speed: speed, bob: 1.2 * s)
      m.wait(max(40, 170 - m.t))
      m.jump(to: 1900)
      t.behind[0].loop(swing("transform.rotation.z", from: -0.1, to: 0.12, duration: 2.4), key: "tail")
      play(
        m, mover: holder, y: depthToY(depth), rig: t, scale: s, gait: gait,
        tracks: [(t.front[0], "head", "transform.rotation.z")], delay: -r() * m.period)
      holder.position.x = 800
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

  /// Sits about with its ears twitching, now and then sitting up to look
  /// round, and bounds off a few hops at a time. It ranges either side of
  /// `home` and ends each loop back there, facing right.
  private func hareRoam(home: Double, scale s: Double, _ r: Rng) -> Roam {
    var m = Roam(x: home, facing: 1)
    m.set("ear", 0)
    m.set("earBack", 0)
    m.set("stretch", 1)
    let range = 70.0
    let hopLength = 14 * s

    func sit(_ d: Double) {
      var left = d
      while left > 1.5 {
        let gap = 0.8 + r() * min(4, left - 0.8)
        m.wait(gap)
        left -= gap
        let ear = r() < 0.6 ? "ear" : "earBack"
        m.ease(ear, to: -0.35, over: 0.07)
        m.ease(ear, to: 0, over: 0.12, after: 0.12)
      }
      m.wait(left)
    }
    func sitUp() {
      m.ease("stretch", to: 1.1, over: 0.25)
      m.ease("ear", to: 0.12, over: 0.25)
      m.ease("earBack", to: 0.1, over: 0.25)
      m.wait(1.5 + r() * 2)
      m.ease("stretch", to: 1, over: 0.3)
      m.ease("ear", to: 0, over: 0.3)
      m.ease("earBack", to: 0, over: 0.3)
      m.wait(0.4)
    }
    /// A run of hops: a crouch, then each hop stretches out in the air and
    /// squashes on landing, ears laid back the whole way.
    func bound(_ hops: Int, _ length: Double) {
      m.ease("ear", to: -0.4, over: 0.1)
      m.ease("earBack", to: -0.4, over: 0.1)
      m.ease("stretch", to: 0.86, over: 0.1)
      m.wait(0.1)
      for k in 0..<hops {
        m.set("stretch", 1.12, after: 0.08)
        m.hop(length, height: 7 * s, duration: 0.3)
        m.set("stretch", 0.88, after: 0.03)
        if k < hops - 1 { m.wait(0.07) }
      }
      m.ease("stretch", to: 1, over: 0.15, after: 0.03)
      m.ease("ear", to: 0, over: 0.3, after: 0.2)
      m.ease("earBack", to: 0, over: 0.3, after: 0.2)
      m.wait(0.5)
    }
    func turn() {
      m.turn(0.25)
      m.wait(0.2 + r() * 0.4)
    }

    for _ in 0..<(3 + Int(r() * 3)) {
      sit(5 + r() * 9)
      if r() < 0.35 { sitUp() }
      let hops = 2 + Int(r() * 3)
      // Turns back rather than wander out of its patch.
      if abs(m.x + m.facing * hopLength * Double(hops) - home) > range { turn() }
      bound(hops, hopLength)
    }
    // Home, in hops of whatever length gets it there exactly.
    let back = home - m.x
    if abs(back) > 1 {
      if back * m.facing < 0 { turn() }
      let n = max(1, Int((abs(back) / hopLength).rounded()))
      bound(n, abs(back) / Double(n))
    }
    if m.facing != 1 {
      sit(2 + r() * 3)
      turn()
    }
    sit(3 + r() * 4)
    return m
  }

  /// Grazes, looks up, and ambles a few strides at a time, head low, ranging
  /// either side of `home` and flicking its tail now and then. It ends each loop
  /// back at `home` facing `facing`.
  private func deerRoam(home: Double, facing: Double, stride: Double, _ r: Rng) -> Roam {
    var m = Roam(x: home, facing: facing, stride: stride, rate: 15)
    m.set("head", 0.85)
    m.set("tail", 0)
    let speed = stride / 1.2
    let range = 110.0

    func flicks(_ d: Double) {
      var at = 0.5 + r() * 3
      while at < d - 0.4 {
        m.ease("tail", to: 0.7, over: 0.08, after: at)
        m.ease("tail", to: 0, over: 0.15, after: at + 0.12)
        at += 2 + r() * 5
      }
    }
    func graze(_ d: Double) {
      m.ease("head", to: 0.85, over: 0.8)
      flicks(d)
      m.wait(d)
    }
    func look(_ d: Double) {
      m.ease("head", to: 0, over: 0.7)
      flicks(d)
      m.wait(d)
    }
    func amble(_ strides: Int) {
      m.ease("head", to: 0.55, over: 0.6)
      m.wait(0.3)
      m.walk(strides, speed: speed, bob: 0.6)
    }
    func turn() {
      look(1 + r())
      m.turn(0.6)
    }

    let length = 60 + r() * 30
    while m.t < length {
      let roll = r()
      if roll < 0.3 {
        graze(3 + r() * 4)
      } else if roll < 0.45 {
        look(1.5 + r() * 2)
      } else {
        let n = 2 + Int(r() * 4)
        if abs(m.x + m.facing * Double(n) * stride - home) > range { turn() }
        amble(n)
      }
    }
    // Walk home, which is always whole strides away, and face the start way.
    let back = home - m.x
    if abs(back) > stride / 2 {
      if back * m.facing < 0 { turn() }
      amble(Int((abs(back) / stride).rounded()))
    }
    if m.facing != facing { turn() }
    graze(4 + r() * 4)
    return m
  }

  /// Pecks about, takes a few steps, and once a loop raises its train into a
  /// full, shivering fan. It wanders within reach of `home` and ends each
  /// loop back there, facing left.
  private func peacockRoam(home: Double, stride: Double, scale s: Double, _ r: Rng) -> Roam {
    var m = Roam(x: home, facing: -1, stride: stride)
    m.set("lean", 0)
    m.set("neck", 0)
    // Folded away inside the train.
    m.set("fanAngle", 0)
    m.set("fanWidth", 0.05)
    m.set("fanHeight", 0.05)
    let speed = stride / 0.8
    let range = 80.0

    func pecks(_ n: Int) {
      for _ in 0..<n {
        m.ease("lean", to: 0.25, over: 0.15)
        m.ease("neck", to: 1, over: 0.15)
        m.wait(0.25)
        m.ease("lean", to: 0, over: 0.2)
        m.ease("neck", to: 0, over: 0.2)
        m.wait(0.3 + r() * 0.6)
      }
    }
    func step(_ n: Int) {
      if abs(m.x + m.facing * Double(n) * stride - home) > range {
        m.turn(0.4)
        m.wait(0.3)
      }
      m.walk(n, speed: speed, ease: 0.3, bob: 0.6 * s)
      m.wait(0.3 + r() * 1.2)
    }
    func fan(_ angle: Double, _ width: Double, _ height: Double, over d: Double) {
      m.ease("fanAngle", to: angle, over: d)
      m.ease("fanWidth", to: width, over: d)
      m.ease("fanHeight", to: height, over: d)
      m.wait(d)
    }
    /// Lifts the train, raises it upright, spreads it, shivers it, then
    /// lowers it the same way.
    func display() {
      fan(-0.9, 0.12, 0.7, over: 0.6)
      fan(-0.05, 0.18, 1, over: 0.7)
      fan(0, 1, 1, over: 0.8)
      let hold = 6 + r() * 6
      var at = 1.0
      while at < hold - 1.5 {
        for k in 0..<10 { m.set("fanAngle", k % 2 == 0 ? 0.035 : -0.035, after: at + Double(k) * 0.07) }
        m.set("fanAngle", 0, after: at + 0.7)
        at += 2.5 + r() * 2
      }
      m.wait(hold)
      fan(-0.05, 0.18, 1, over: 0.7)
      fan(-0.9, 0.12, 0.7, over: 0.6)
      fan(0, 0.05, 0.05, over: 0.4)
    }

    let length = 70 + r() * 30
    let showAt = r() * length
    var shown = false
    while m.t < length {
      if !shown && m.t >= showAt {
        display()
        shown = true
      }
      m.wait(0.5 + r() * 2)
      pecks(1 + Int(r() * 3))
      if r() < 0.6 { step(2 + Int(r() * 3)) }
    }
    if !shown { display() }
    let back = home - m.x
    if abs(back) > stride / 2 {
      if back * m.facing < 0 {
        m.turn(0.4)
        m.wait(0.3)
      }
      m.walk(Int((abs(back) / stride).rounded()), speed: speed, ease: 0.3, bob: 0.6 * s)
    }
    if m.facing != -1 { m.turn(0.4) }
    m.wait(1)
    pecks(2)
    return m
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
