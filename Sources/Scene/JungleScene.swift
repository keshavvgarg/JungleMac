import QuartzCore

/// Everything the scene shows at one moment.
struct SceneInput {
  var seed: Int
  var focus: Double
  var season: SeasonState
  var day: DayState
  var weather: WeatherState
  var regions: RegionState
  var events: WorldEvents
  var running: Bool
}

/// Plants in the far band hold still: their sway is a pixel or two.
private let SWAY_MIN_DEPTH = 0.35
private func bandOf(_ depth: Double) -> Int { depth < 0.35 ? 0 : depth < 0.68 ? 1 : 2 }

/// A plant: base position and growth on `root`, a fixed lean, then the
/// swaying body. Only the body's image is ever redrawn.
private final class PlantNode {
  let root = CALayer()
  let shadow = CALayer()
  let lean = CALayer()
  let body = CALayer()
  var imageKey = ""
  var shadowKey = ""
  var swayLevel = -1.0
  var swayBegin: CFTimeInterval?

  init() {
    root.addSublayer(shadow)
    root.addSublayer(lean)
    lean.addSublayer(body)
  }
}

/// A perched bird that now and then flies off and comes back. `root` carries
/// position and size, `facing` turns it to face its flight, and the sitting
/// and flying poses swap as it takes off and lands.
private final class BirdNode {
  let root = CALayer()
  let facing = CALayer()
  let perch = CALayer()
  let image = CALayer()
  let flying = CALayer()
  var imageKey = ""
  /// The wing's beats through the flight loop, and when that loop began, so
  /// a rebuilt wing layer picks up in step with the rest of the bird.
  var wingFlight: CAAnimation?
  var flightBegin: CFTimeInterval = 0

  init() {
    root.addSublayer(facing)
    facing.addSublayer(perch)
    perch.addSublayer(image)
    flying.opacity = 0
    facing.addSublayer(flying)
  }
}

/// Builds and updates the jungle as a Core Animation layer tree. All looping
/// motion runs as Core Animation animations, drawn by the system's render
/// server, so the app itself does almost nothing between clock ticks.
@MainActor
final class JungleScene {
  /// Attach to a view. Its coordinate space is the view's (y up).
  let root = CALayer()

  // Paused together on Stop. Fog, wash, vignette and veil stay live so their
  // slow fades and the paused veil still play.
  private let liveA = CALayer()
  private let liveB = CALayer()
  /// Scales the 1600x900 world to fill the view, cropping like `xMidYMax slice`.
  private let viewport = CALayer()
  /// The world in SVG coordinates: y grows downwards.
  private let world = CALayer()

  private let sky = CAGradientLayer()
  private let stars = CALayer()
  private let moon = CALayer()
  private let sun = CALayer()
  private let sunGlow = CAGradientLayer()
  private let sunDisk = CAShapeLayer()
  private let clouds = CALayer()
  private var cloudLayers: [CALayer] = []
  private let hillFar = CAShapeLayer()
  private let hillMid = CAShapeLayer()
  private let hillNear = CAShapeLayer()
  private let mistHills = gradientLayer([], frame: CGRect(x: 0, y: 400, width: W, height: 260))
  private let ground = CAGradientLayer()
  private let groundMask = CAShapeLayer()
  private let rainbow = CAGradientLayer()
  private let bands = [CALayer(), CALayer(), CALayer()]
  private let mistFar = gradientLayer([], frame: CGRect(x: 0, y: 380, width: W, height: 400))
  private let mistMid = gradientLayer([], frame: CGRect(x: 0, y: 440, width: W, height: 400))
  private let puffs = CALayer()
  private let rays = CALayer()
  private let flyers = CALayer()
  private let skyEvents = CALayer()
  private let airEvents = CALayer()
  private lazy var wildlife = Wildlife(bands: bands, sky: skyEvents, air: airEvents) { [unowned self] in self.density($0) }
  private let frame = CALayer()

  private let waterfall = CALayer()
  private let waterfallArt = CALayer()
  private let stream = CALayer()
  private let streamWater = CAShapeLayer()
  private let streamShine = CAShapeLayer()
  private let bamboo = CALayer()
  private let meadow = CALayer()
  private let pond = CALayer()
  private let pondArt = CALayer()
  private let frog = CALayer()
  private let dragonflies = CALayer()

  private let stormDim = CALayer()
  private let weather = WeatherLayers()
  private let fog = CAGradientLayer()
  private let wash = CALayer()
  private let vignette = CAGradientLayer()
  private let veil = CALayer()

  private var plants: [Int: PlantNode] = [:]
  private var flora: [Int: CALayer] = [:]
  private var floraKeys: [Int: String] = [:]
  private var birds: [String: BirdNode] = [:]
  private var flyerIds: [String] = []
  private var specs: [PlantSpec] = []

  private var sprites: [String: Sprite] = [:]
  private var seed = -1
  private var paletteKey = ""
  private var dominant = -1
  private var worldScale = 1.0
  private var backing = 2.0
  private var last: SceneInput?
  private var morePending = false
  private var pondKey = ""

  init() {
    root.masksToBounds = true
    root.backgroundColor = cgColor("#e8dcc8")
    viewport.bounds = CGRect(x: 0, y: 0, width: W, height: H)
    viewport.anchorPoint = CGPoint(x: 0.5, y: 0)
    world.frame = viewport.bounds
    world.sublayerTransform = CATransform3DMakeScale(1, -1, 1)
    viewport.addSublayer(world)

    sky.frame = viewport.bounds
    sky.startPoint = CGPoint(x: 0.5, y: 0)
    sky.endPoint = CGPoint(x: 0.5, y: 1)
    for l in [sky, stars, moon, skyEvents, sun, clouds, hillFar, hillMid, mistHills, hillNear, ground, rainbow, bands[0], mistFar, bands[1], mistMid, puffs, bands[2], airEvents, rays, flyers, frame] {
      world.addSublayer(l)
    }
    for b in bands { b.frame = viewport.bounds }
    ground.mask = groundMask

    sunGlow.type = .radial
    sunGlow.frame = CGRect(x: 1120 - 430, y: 360 - 430, width: 860, height: 860)
    sunGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
    sunGlow.endPoint = CGPoint(x: 1, y: 1)
    sunDisk.path = circlePath(1120, 360, 52)
    sunDisk.opacity = 0.95
    sun.addSublayer(sunGlow)
    sun.addSublayer(sunDisk)

    rays.compositingFilter = "screenBlendMode"

    buildStars()
    buildMoon()
    buildRegions()

    stormDim.backgroundColor = rgba(28, 38, 50, 0.22)
    stormDim.opacity = 0
    fog.type = .radial
    fog.colors = [rgba(236, 240, 238, 0.62), rgba(236, 240, 238, 0.18), rgba(236, 240, 238, 0)]
    fog.locations = [0, 0.58, 0.78]
    fog.startPoint = CGPoint(x: 0.5, y: 0.38)
    fog.endPoint = CGPoint(x: 1.2, y: 1.13)
    vignette.type = .radial
    vignette.colors = [rgba(24, 34, 30, 0), rgba(24, 34, 30, 0), rgba(24, 34, 30, 0.3)]
    vignette.locations = [0, 0.55, 1]
    vignette.startPoint = CGPoint(x: 0.5, y: 0.58)
    vignette.endPoint = CGPoint(x: 1.22, y: 1.36)
    veil.backgroundColor = rgba(46, 58, 52, 0.16)

    liveA.addSublayer(viewport)
    liveA.addSublayer(stormDim)
    liveA.addSublayer(weather.main)
    liveB.addSublayer(weather.fireflies)
    for l in [liveA, fog, wash, liveB, vignette, veil] { root.addSublayer(l) }
    liveA.pause()
    liveB.pause()
  }

  // MARK: - Layout

  /// Fits the scene to the view. Images are redrawn for the new size once it settles.
  func layout(size: CGSize, backingScale: Double) {
    transaction {
      root.frame = CGRect(origin: .zero, size: size)
      for l in [liveA, liveB, stormDim, fog, wash, vignette, veil] { l.frame = root.bounds }
      let s = max(size.width / W, size.height / H)
      viewport.position = CGPoint(x: size.width / 2, y: 0)
      viewport.transform = CATransform3DMakeScale(s, s, 1)
      weather.layout(size: size)
      let resolutionChanged = abs(s / worldScale - 1) > 0.08 || backing != backingScale
      backing = backingScale
      if resolutionChanged {
        worldScale = s
        sprites.removeAll()
        wildlife.reset()
        if let last { update(last) }
      }
    }
  }

  // MARK: - Update

  func update(_ input: SceneInput) {
    last = input
    transaction {
      if input.seed != seed {
        seed = input.seed
        rebuildForSeed()
      }
      let pal = input.season.palette
      let dom = input.season.weights.firstIndex(of: input.season.weights.max()!)!
      if pal.key != paletteKey || dom != dominant {
        paletteKey = pal.key
        dominant = dom
        sprites.removeAll()
        recolor(pal)
      }
      updatePlants(input)
      updateFlora(input)
      updateBirds(input)
      updateFlyers(input)
      updateRegions(input)
      updateSky(input)
      wildlife.update(input)
    }
    // Slow fades, like the web version's CSS transitions.
    let w = input.season.weights
    let monsoon = w[MONSOON]
    transaction(3) {
      stormDim.opacity = Float(monsoon)
      weather.update(weights: w, drizzle: input.weather.drizzle, storm: max(0, (monsoon - 0.3) / 0.7),
                     fireflies: input.day.fireflies * (1 - w[WINTER] * 0.65))
    }
    transaction(18) { fog.opacity = Float(input.weather.fog) }
    transaction(24) {
      let c = input.day.wash
      wash.backgroundColor = rgba(c.0, c.1, c.2, c.3)
    }
    transaction(1.5) { veil.opacity = input.running ? 0 : 1 }
    if input.running {
      liveA.resume()
      liveB.resume()
    } else {
      liveA.pause()
      liveB.pause()
    }
    // Images that did not fit in this pass's time budget are drawn shortly after.
    if morePending {
      morePending = false
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self, let last = self.last else { return }
        self.update(last)
      }
    }
  }

  private func sprite(_ key: String, _ make: () -> Sprite?) -> Sprite? {
    if let s = sprites[key] { return s }
    let s = make()
    if let s { sprites[key] = s }
    return s
  }

  /// Pixels per world unit for something drawn at `localScale`, rounded up to a
  /// third of an octave so similar plants share images.
  private func density(_ localScale: Double) -> Double {
    let px = max(0.05, localScale * worldScale * backing)
    return pow(2, (log2(px) * 3).rounded(.up) / 3)
  }

  // MARK: - Seed

  private func rebuildForSeed() {
    for n in plants.values { n.root.removeFromSuperlayer() }
    for l in flora.values { l.removeFromSuperlayer() }
    for n in birds.values { n.root.removeFromSuperlayer() }
    plants.removeAll()
    flora.removeAll()
    floraKeys.removeAll()
    birds.removeAll()
    specs.removeAll()
    flyerIds.removeAll()
    flyers.sublayers?.forEach { $0.removeFromSuperlayer() }
    wildlife.reset()

    hillFar.path = ridge(1, 470, 55, 0)
    hillMid.path = ridge(2, 525, 40, 7)
    hillNear.path = ridge(3, 572, 22, 12)
    let edge = CGMutablePath()
    let r = Rng(seed, 4, 7)
    let p = r() * 6.28
    edge.move(to: CGPoint(x: 0, y: H))
    for x in stride(from: 0.0, through: W, by: 20) {
      edge.addLine(to: CGPoint(x: x, y: HORIZON - 4 + 4 * sin(x / 90 + p)))
    }
    edge.addLine(to: CGPoint(x: W, y: H))
    edge.closeSubpath()
    ground.frame = CGRect(x: 0, y: HORIZON - 10, width: W, height: H - HORIZON + 10)
    var shift = CGAffineTransform(translationX: 0, y: -(HORIZON - 10))
    groundMask.path = edge.copy(using: &shift)
    buildClouds()
  }

  private func ridge(_ salt: Int, _ y0: Double, _ amp: Double, _ bumps: Double) -> CGPath {
    let r = Rng(seed, salt, 7)
    let p0 = r() * 6.28, p1 = r() * 6.28, p2 = r() * 6.28
    func y(_ x: Double) -> Double {
      let wave = 0.5 * sin(x / 260 + p0) + 0.3 * sin(x / 120 + p1) + 0.2 * sin(x / 55 + p2)
      return y0 - amp * wave - bumps * abs(sin(x / 22 + p1))
    }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: H))
    path.addLine(to: CGPoint(x: 0, y: y(0)))
    for x in stride(from: 8.0, through: W, by: 8) { path.addLine(to: CGPoint(x: x, y: y(x))) }
    path.addLine(to: CGPoint(x: W, y: H))
    path.closeSubpath()
    return path
  }

  private struct CloudSpec {
    var y, scale, duration, delay: Double
    var puffs: [(Double, Double, Double, Double)]
  }
  private var cloudSpecs: [CloudSpec] = []

  private func buildClouds() {
    cloudLayers.forEach { $0.removeFromSuperlayer() }
    cloudLayers.removeAll()
    cloudSpecs = (0..<10).map { (i: Int) -> CloudSpec in
      let r = Rng(seed, i, 53)
      let y = 70 + r() * 250
      let s = 0.7 + r() * 0.8
      let duration = 260 + r() * 220
      let delay = -r() * 480
      let puffs = (0..<5).map { (k: Int) -> (Double, Double, Double, Double) in
        let x: Double = Double(k) * 55 - 110 + r() * 20
        let y: Double = -r() * 30
        let rx: Double = 70 + r() * 50
        let ry: Double = 28 + r() * 18
        return (x, y, rx, ry)
      }
      return CloudSpec(y: y, scale: s, duration: duration, delay: delay, puffs: puffs)
    }
    for c in cloudSpecs {
      let l = CALayer()
      l.position = CGPoint(x: -400, y: c.y)
      l.transform = CATransform3DMakeScale(c.scale, c.scale, 1)
      let a = CABasicAnimation(keyPath: "position.x")
      a.fromValue = -400
      a.toValue = 2000
      a.duration = c.duration
      l.loop(a, key: "drift", delay: c.delay)
      clouds.addSublayer(l)
      cloudLayers.append(l)
    }
  }

  // MARK: - Palette

  private func recolor(_ pal: Palette) {
    sky.colors = [cgColor(pal.skyTop), cgColor(pal.skyMid), cgColor(pal.skyBottom)]
    sky.locations = [0, 0.55, 1]
    sunGlow.colors = [cgColor(pal.sun, 0.9), cgColor(pal.sun, 0.35), cgColor(pal.sun, 0)]
    sunGlow.locations = [0, 0.35, 1]
    sunDisk.fillColor = cgColor(pal.sun)
    hillFar.fillColor = cgColor(pal.hillFar)
    hillMid.fillColor = cgColor(pal.hillMid)
    hillNear.fillColor = cgColor(pal.hillNear)
    mistHills.setStops([(0, pal.mist, 0), (0.55, pal.mist, 0.85), (1, pal.mist, 0)])
    mistFar.setStops([(0, pal.mist, 0), (0.45, pal.mist, 0.6), (0.75, pal.mist, 0.25), (1, pal.mist, 0)])
    mistMid.setStops([(0, pal.mist, 0), (0.5, pal.mist, 0.35), (1, pal.mist, 0)])
    let top = 10 / (H - HORIZON + 10)
    ground.setStops([(0, pal.groundFar, 1), (top, pal.groundFar, 1), (1, pal.groundNear, 1)])

    let px = density(1)
    for (i, c) in cloudSpecs.enumerated() {
      let paint = Paint.radial(cx: 0.5, cy: 0.5, r: 0.5, stops: [(0, pal.cloud, 0.95), (0.6, pal.cloud, 0.6), (1, pal.cloud, 0)])
      let ops = c.puffs.map { Op.fill(ellipsePath($0.0, $0.1, $0.2, $0.3), paint) }
      cloudLayers[i].sublayers?.forEach { $0.removeFromSuperlayer() }
      _ = cloudLayers[i].addSprite(render(ops, pixelsPerUnit: px * c.scale))
    }

    puffs.sublayers?.forEach { $0.removeFromSuperlayer() }
    let puffPaint = Paint.radial(cx: 0.5, cy: 0.5, r: 0.5, stops: [(0, pal.mist, 0.7), (1, pal.mist, 0)])
    for (cx, cy, rx, ry, dur, delay) in [(300.0, 640.0, 420.0, 50.0, 80.0, 0.0), (1200, 610, 380, 40, 110, -40)] {
      let l = puffs.addSprite(render([.fill(ellipsePath(0, 0, rx, ry), puffPaint)], pixelsPerUnit: px / 2), pivot: CGPoint(x: cx, y: cy))
      l.loop(swing("transform.translation.x", from: -160, to: 160, duration: dur), key: "drift", delay: delay)
    }

    rays.sublayers?.forEach { $0.removeFromSuperlayer() }
    for (i, (a, b)) in [(-260.0, -120.0), (-60, 60), (140, 260)].enumerated() {
      let tri = CGMutablePath()
      tri.move(to: CGPoint(x: 1120, y: 360))
      tri.addLine(to: CGPoint(x: 1120 + a * 3, y: H))
      tri.addLine(to: CGPoint(x: 1120 + b * 3, y: H))
      tri.closeSubpath()
      let bb = tri.boundingBoxOfPath
      let g = gradientLayer([(0, pal.sun, 0.5), (1, pal.sun, 0)], frame: bb)
      let mask = CAShapeLayer()
      var toLocal = CGAffineTransform(translationX: -bb.minX, y: -bb.minY)
      mask.path = tri.copy(using: &toLocal)
      g.mask = mask
      g.opacity = 0.5
      g.loop(swing("opacity", from: 0.25, to: 0.6, duration: 12), key: "rays", delay: Double(-i) * 4)
      rays.addSublayer(g)
    }

    buildRainbow()
    recolorRegions(pal)
    buildFrame(pal)
  }

  private func buildRainbow() {
    guard rainbow.mask == nil else { return }
    rainbow.frame = CGRect(x: 811, y: 251, width: 578, height: 228)
    rainbow.startPoint = CGPoint(x: 0, y: 0.5)
    rainbow.endPoint = CGPoint(x: 1, y: 0.5)
    rainbow.setStops([(0, "#e25b5b", 0), (0.15, "#e25b5b", 1), (0.35, "#e7b15a", 1), (0.55, "#8dbe6a", 1), (0.75, "#6aa0c8", 1), (1, "#6aa0c8", 0)])
    let arc = CGMutablePath()
    for k in 0...48 {
      let t = Double.pi + Double.pi * Double(k) / 48
      let pt = CGPoint(x: 1100 + 280 * cos(t) - 811, y: 470 + 210 * sin(t) - 251)
      k == 0 ? arc.move(to: pt) : arc.addLine(to: pt)
    }
    let m = CAShapeLayer()
    m.path = arc
    m.fillColor = nil
    m.strokeColor = cgColor("#000000")
    m.lineWidth = 18
    rainbow.mask = m
    rainbow.opacity = 0
  }

  private func buildFrame(_ pal: Palette) {
    frame.sublayers?.forEach { $0.removeFromSuperlayer() }
    let frameColor = shade(pal.leafDark, -0.35)
    let leaves: [(Double, Double)] = [(-10, 300), (18, 260), (42, 230), (66, 200), (-34, 240)]
    let ops: [Op] = leaves.enumerated().map { (i, l) in
      let (a, len) = l
      return .fill(
        "M0 0 Q\(f(len * 0.22)) \(f(-len * 0.45)) 0 \(f(-len)) Q\(f(-len * 0.22)) \(f(-len * 0.45)) 0 0Z",
        .solid(i % 2 == 1 ? frameColor : shade(frameColor, 0.12)), rotate(a + 20))
    }
    let art = render(ops, pixelsPerUnit: density(1))
    for m in [1.0, -1.0] {
      let side = CALayer()
      side.position = CGPoint(x: m == 1 ? -30 : W + 30, y: H + 30)
      side.transform = CATransform3DMakeScale(m, 1, 1)
      let body = side.addSprite(art)
      body.loop(swing("transform.rotation.z", from: -1.2 * .pi / 180, to: 1.2 * .pi / 180, duration: 9), key: "sway")
      frame.addSublayer(side)
    }
  }

  // MARK: - Sky

  private func buildStars() {
    for i in 0..<28 {
      let r = Rng(11, i, 2)
      let x = r() * W, y = 20 + r() * 280, s = 0.6 + r() * 1.5
      let star = CAShapeLayer()
      star.path = circlePath(x, y, s)
      star.fillColor = cgColor("#f7f4ea")
      star.loop(swing("opacity", from: 0.2, to: 0.95, duration: 6.5), key: "twinkle", delay: Double(-i) * 0.4)
      stars.addSublayer(star)
    }
  }

  private func buildMoon() {
    let halo = CAShapeLayer()
    halo.path = circlePath(360, 150, 78)
    halo.fillColor = cgColor("#f4efe2")
    halo.opacity = 0.16
    let disk = CAShapeLayer()
    disk.path = circlePath(360, 150, 26)
    disk.fillColor = cgColor("#f7f3e8")
    moon.addSublayer(halo)
    moon.addSublayer(disk)
  }

  private func updateSky(_ input: SceneInput) {
    let day = input.day
    let w = input.season.weights
    let monsoon = w[MONSOON]
    let sunStrength = (1 - monsoon * 0.8) * day.sunVisible
    stars.opacity = Float(day.night)
    moon.opacity = Float(day.moon)
    sun.opacity = Float(sunStrength)
    sun.position = CGPoint(x: day.sunX - 1120, y: day.sunY - 360)
    rays.position = sun.position
    rays.opacity = Float(sunStrength * (1 - w[WINTER] * 0.4))
    rainbow.opacity = Float(input.weather.rainbow * 0.55)
    for (i, l) in cloudLayers.enumerated() {
      l.opacity = Float(i < 5 ? 0.55 + monsoon * 0.4 : monsoon * 0.9)
    }
  }

  // MARK: - Plants

  private func updatePlants(_ input: SceneInput) {
    let count = plantCount(input.focus)
    while specs.count < count { specs.append(makePlant(seed, specs.count, after: specs)) }
    if specs.count > count { specs.removeLast(specs.count - count) }
    for (id, n) in plants where id >= count {
      n.root.removeFromSuperlayer()
      plants[id] = nil
    }

    let pal = input.season.palette
    let w = input.season.weights
    let swayLevel = (input.weather.sway * 10).rounded() / 10
    let firstPass = plants.isEmpty
    let deadline = CACurrentMediaTime() + (firstPass ? 5 : 0.03)

    for p in specs {
      let s = plantState(p, input.focus, w)
      let node: PlantNode
      if let n = plants[p.id] {
        node = n
      } else {
        node = PlantNode()
        node.root.position = CGPoint(x: p.x, y: p.baseY)
        node.lean.transform = CATransform3DMakeRotation(p.lean * 5 * .pi / 180, 0, 0, 1)
        bands[bandOf(p.depth)].insert(node.root, sortY: p.baseY)
        plants[p.id] = node
      }
      let k = p.scale * s.growth
      node.root.transform = CATransform3DMakeScale(k * p.flip, k, 1)
      node.root.opacity = Float(s.opacity)
      node.root.isHidden = node.imageKey.isEmpty

      // Images are drawn at the plant's full size; growth only scales the layer.
      let px = density(p.scale)
      let drawn = drawnState(s)
      let key = plantImageKey(p, drawn, pal) + "|\(px)"
      if key != node.imageKey {
        if sprites[key] != nil || CACurrentMediaTime() < deadline {
          node.body.setSprite(sprite(key) { render(plantOps(p, drawn, pal), pixelsPerUnit: px) })
          node.imageKey = key
          node.root.isHidden = false
        } else {
          morePending = true
        }
      }
      let shadowKey = "shadow|\(p.species.rawValue)|\(px)"
      if shadowKey != node.shadowKey {
        node.shadow.setSprite(sprite(shadowKey) { render(shadowOps(p.species), pixelsPerUnit: px) })
        node.shadowKey = shadowKey
      }

      if p.depth >= SWAY_MIN_DEPTH && node.swayLevel != swayLevel {
        let amp = (p.species == .fern || p.species == .banana ? 2.6 : 1.2) * swayLevel * .pi / 180
        let a = swing("transform.rotation.z", from: -amp, to: amp, duration: p.swayDur)
        // Keep the phase when only the wind strength changes.
        if let begin = node.swayBegin {
          a.beginTime = begin
          a.repeatCount = .infinity
          a.isRemovedOnCompletion = false
          a.preferredFrameRateRange = SCENE_FPS
          node.body.add(a, forKey: "sway")
        } else {
          node.body.loop(a, key: "sway", delay: p.swayDelay)
          node.swayBegin = a.beginTime
        }
        node.swayLevel = swayLevel
      }
    }
  }

  // MARK: - Ground cover

  private func updateFlora(_ input: SceneInput) {
    let pal = input.season.palette
    let winter = input.season.weights[WINTER]
    let count = floraCount(input.focus)
    let grass = [shade(pal.leafMid, -0.05), pal.leafLight, shade(pal.leafMid, 0.1)]
    let flowers = FLOWER_COLORS[dominant]
    for (id, l) in flora where id >= count {
      l.removeFromSuperlayer()
      flora[id] = nil
      floraKeys[id] = nil
    }
    for i in 0..<count {
      let fl = makeFlora(seed, i)
      let layer: CALayer
      if let l = flora[i] {
        layer = l
      } else {
        layer = CALayer()
        layer.position = CGPoint(x: fl.x, y: fl.baseY)
        bands[bandOf(fl.depth)].insert(layer, sortY: fl.baseY - 0.5)
        flora[i] = layer
      }
      layer.isHidden = fl.isFlower && winter > 0.5
      let px = density(fl.scale)
      let key = "\(paletteKey)|\(dominant)|\(px)"
      if floraKeys[i] != key {
        layer.setSprite(render(floraOps(fl, grass: grass, flowers: flowers), pixelsPerUnit: px))
        layer.position = CGPoint(x: fl.x, y: fl.baseY)
        layer.transform = CATransform3DMakeScale(fl.scale, fl.scale, 1)
        floraKeys[i] = key
      }
    }
  }

  // MARK: - Birds

  private func updateBirds(_ input: SceneInput) {
    let placed = placeBirds(seed, specs, input.focus)
    let initial = birds.isEmpty
    var seen = Set<String>()
    for (i, b) in placed.enumerated() {
      seen.insert(b.key)
      let node: BirdNode
      if let n = birds[b.key] {
        node = n
      } else {
        node = BirdNode()
        node.root.position = CGPoint(x: b.x, y: b.y)
        node.root.transform = CATransform3DMakeScale(b.scale, b.scale, 1)
        // In the tree first, so its animations share the scene's clock.
        bands[bandOf(b.depth)].insert(node.root, sortY: b.sortY)
        node.perch.loop(hop(duration: 7), key: "hop", delay: Double(-i) * 1.7)
        // A bird that turns up while you watch flies in and lands.
        addFlights(node, b, arriving: !initial && input.focus - b.arriveAt < 10)
        birds[b.key] = node
      }
      node.root.opacity = Float(min(1, (input.focus - b.arriveAt) / 4))
      let px = density(b.scale)
      let key = "bird|\(b.sp.id)|\(px)"
      if node.imageKey != key {
        node.image.setSprite(sprite(key) { render(birdParts(b.sp).all, pixelsPerUnit: px) })
        let parts = birdParts(b.sp, flying: true)
        node.flying.sublayers?.forEach { $0.removeFromSuperlayer() }
        _ = node.flying.addSprite(sprite(key + "|below") { render(parts.below, pixelsPerUnit: px) })
        let wing = node.flying.addSprite(sprite(key + "|wing") { render(parts.wing, pixelsPerUnit: px) }, pivot: CGPoint(x: 0, y: -12))
        if let flight = node.wingFlight { wing.loop(flight, key: "flap", at: node.flightBegin) }
        _ = node.flying.addSprite(sprite(key + "|above") { render(parts.above, pixelsPerUnit: px) })
        node.imageKey = key
      }
    }
    for (key, n) in birds where !seen.contains(key) {
      n.root.removeFromSuperlayer()
      birds[key] = nil
    }
  }

  /// Loops a bird through sitting, taking off towards the nearer edge, a
  /// while out of sight, and swooping back to land on its perch.
  ///
  /// Everything is laid out in time, not along the curve, so the rhythm stays
  /// even. The bird jumps off the branch fast and settles into a cruise, then
  /// brakes and flares nose-up to land. In between it flaps steadily, now and
  /// then holding its wings out for a short glide that sinks it a little, which
  /// the next wingbeats make up. Height, wings and pitch share one timeline, so
  /// they stay in step. Each leg's duration comes from its length, so near and
  /// far birds fly at a natural pace.
  private func addFlights(_ node: BirdNode, _ b: BirdPlacement, arriving: Bool) {
    let r = Rng(seed, b.key.unicodeScalars.reduce(17) { $0 &* 31 &+ Int($1.value) }, 41)
    let sit = 45 + r() * 90
    let away = 6 + r() * 14
    let dir: Double = b.x < W / 2 ? -1 : 1
    let edge = dir < 0 ? -140.0 : W + 140
    let perch = CGPoint(x: b.x, y: b.y)
    let span = abs(edge - b.x)

    // Out: rise steeply off the branch, then head for the edge.
    let leave = FlightRoute([
      perch,
      CGPoint(x: b.x + dir * 30, y: b.y - 110 - r() * 40),
      CGPoint(x: b.x + dir * span * 0.55, y: b.y - 200 - r() * 100),
      CGPoint(x: edge, y: b.y - 120 - r() * 180),
    ])
    // Back: a different, higher route, dropping onto the branch from above.
    let entry = CGPoint(x: edge, y: b.y - 220 - r() * 140)
    let come = FlightRoute([
      entry,
      CGPoint(x: b.x + dir * span * 0.45, y: entry.y - 60 - r() * 60),
      CGPoint(x: b.x + dir * 60, y: b.y - 140 - r() * 40),
      perch,
    ])
    // World units a second. Distant birds are drawn smaller, so they also
    // cover less of the screen, as perspective would have it.
    let speed = min(120, max(30, (80 + r() * 30) * b.scale))
    // A wingbeat while flapping steadily.
    let beat = 0.16 + r() * 0.04
    // Glides: how long, how far apart, and how much height each one loses.
    let glide = 0.45 + r() * 0.3
    let recover = 0.8
    func gap() -> Double { 2.5 + r() * 3 }
    let sink = (6 + r() * 4) * b.scale
    // Wings held out, a little raised, while gliding.
    let spread = 0.45

    let launch = SpeedProfile(boost: 1.7, boostSpan: 0.2, brakeSpan: 0)
    let landing = SpeedProfile(boost: 1, boostSpan: 0, brakeSpan: 0.3)
    let out = min(30, max(4, leave.length / (speed * launch.mean)))
    let back = min(30, max(5, come.length / (speed * landing.mean)))
    let period = sit + out + away + back

    var points: [CGPoint] = [perch]
    var times: [Double] = [0]
    var tilts: [Double] = [0]
    var faces: [Double] = [dir]
    var wing: [Double] = [1]
    var wingTimes: [Double] = [0]

    /// Samples one leg starting `start` seconds into the loop.
    func fly(_ route: FlightRoute, _ profile: SpeedProfile, start: Double, duration: Double, lands: Bool) {
      // No glides while climbing off the branch or coming in to land: the
      // bird flaps the whole way there.
      let calmStart: Double = lands ? 0 : 1
      let calmEnd: Double = lands ? 1.8 : 0
      let end = start + duration

      // Wings first, as they decide where the glides fall. Keys are clipped
      // to the leg, and each beat or glide ends with the wings up.
      func key(_ t: Double, _ v: Double) {
        guard t < duration else { return }
        wing.append(v)
        wingTimes.append((start + t) / period)
      }
      var glides: [Double] = []
      var t = 0.0
      var nextGlide = calmStart + r() * 2
      key(0, 1)
      while t < duration {
        if t >= nextGlide && t + glide + recover <= duration - calmEnd {
          key(t + 0.08, spread)
          key(t + glide - 0.06, spread)
          key(t + glide, 1)
          glides.append(t)
          t += glide
          nextGlide = t + gap()
        } else {
          // Quicker beats in the last moments before touchdown.
          let stroke = lands && t > duration - 0.6 ? beat * 0.7 : beat
          key(t + stroke / 2, -0.7)
          key(t + stroke, 1)
          t += stroke
        }
      }

      // Sinks gently through each glide, then climbs back on the wingbeats.
      func height(_ t: Double) -> Double {
        for g in glides where t > g && t < g + glide + recover {
          let x = t - g
          return -sink * (x < glide ? smoothstep(x / glide) : 1 - smoothstep((x - glide) / recover))
        }
        return 0
      }

      let n = max(8, Int(duration * 20))
      for i in 0...n {
        let u = Double(i) / Double(n)
        let t = u * duration
        let (pt, tangent) = route.at(profile.distance(u))
        points.append(CGPoint(x: pt.x, y: pt.y - height(t)))
        times.append((start + t) / period)
        // Nose up when climbing, down when diving, from the route alone so
        // the glides don't rock the body.
        var pitch = max(-0.4, min(0.4, atan2(tangent.y, abs(tangent.x) + 1e-6) * 0.7))
        if lands {
          let f = smoothstep((t - duration + 0.5) / 0.4)
          pitch += (-0.55 - pitch) * f
        }
        tilts.append(pitch)
        faces.append(abs(tangent.x) > 1e-3 ? (tangent.x > 0 ? 1 : -1) : faces.last!)
      }

      wing.append(1)
      wingTimes.append(end / period)
    }
    fly(leave, launch, start: sit, duration: out, lands: false)
    fly(come, landing, start: sit + out + away, duration: back, lands: true)
    // Both end on the landing; pin it to exactly 1 against rounding.
    times[times.count - 1] = 1
    wingTimes[wingTimes.count - 1] = 1

    // It sits facing the way it landed.
    let landed = faces.last ?? b.flip
    faces[0] = landed
    node.facing.transform = CATransform3DMakeScale(landed, 1, 1)

    let path = CAKeyframeAnimation(keyPath: "position")
    path.values = points.map { NSValue(point: $0) }
    path.keyTimes = times.map { NSNumber(value: $0) }
    path.duration = period

    // Discrete facing changes, only where the direction flips.
    var faceValues: [Double] = [landed]
    var faceTimes: [Double] = [0]
    for (k, f) in faces.enumerated() where k > 0 && f != faceValues.last! {
      faceValues.append(f)
      faceTimes.append(times[k])
    }
    let face = CAKeyframeAnimation(keyPath: "transform.scale.x")
    face.values = faceValues
    face.keyTimes = (faceTimes + [1]).map { NSNumber(value: $0) }
    face.calculationMode = .discrete
    face.duration = period

    let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
    tilt.values = tilts
    tilt.keyTimes = times.map { NSNumber(value: $0) }
    tilt.duration = period

    let flap = CAKeyframeAnimation(keyPath: "transform.scale.y")
    flap.values = wing
    flap.keyTimes = wingTimes.map { NSNumber(value: $0) }
    flap.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: wing.count - 1)
    flap.duration = period

    // A crouch before the jump, and a little give in the legs on landing.
    let tSit = sit / period
    let crouch = CAKeyframeAnimation(keyPath: "transform.scale.y")
    crouch.values = [0.86, 1.04, 1, 1, 0.8, 1.1, 0.86]
    crouch.keyTimes = [0, 0.12 / period, 0.3 / period, tSit - 0.35 / period, tSit - 0.06 / period, tSit, 1]
      .map { NSNumber(value: $0) }
    crouch.duration = period

    func pose(_ sitting: Double) -> CAKeyframeAnimation {
      let a = CAKeyframeAnimation(keyPath: "opacity")
      a.values = [sitting, 1 - sitting]
      a.keyTimes = [0, NSNumber(value: tSit), 1]
      a.calculationMode = .discrete
      a.duration = period
      return a
    }

    // Arrivals start just before their landing; everyone else at a random point.
    let begin = node.root.localNow + (arriving ? -(period - back) : -r() * period)
    node.root.loop(path, key: "flight", at: begin)
    node.facing.loop(face, key: "flight", at: begin)
    node.perch.loop(pose(1), key: "pose", at: begin)
    node.image.loop(crouch, key: "crouch", at: begin)
    node.flying.loop(pose(0), key: "pose", at: begin)
    node.flying.loop(tilt, key: "tilt", at: begin)
    // The wing layer is rebuilt when the bird's sprites are, so it picks this up then.
    node.wingFlight = flap
    node.flightBegin = begin
  }

  private func updateFlyers(_ input: SceneInput) {
    let unlocked = BIRDS.filter { $0.unlockAt <= input.focus }.suffix(4)
    let ids = unlocked.map(\.id)
    guard ids != flyerIds else { return }
    flyerIds = ids
    flyers.sublayers?.forEach { $0.removeFromSuperlayer() }
    for (i, sp) in unlocked.enumerated() {
      let s = 1.1 * sp.size
      let y = 180 + Double(i) * 55
      let l = CALayer()
      l.position = CGPoint(x: -140, y: y)
      l.transform = CATransform3DMakeScale(s, s, 1)
      let fly = CAKeyframeAnimation(keyPath: "position")
      fly.values = [CGPoint(x: -140, y: y), CGPoint(x: 1740, y: y - 70), CGPoint(x: 1740, y: y - 70)].map { NSValue(point: $0) }
      fly.keyTimes = [0, 0.65, 1]
      fly.duration = 46 + Double(i) * 13
      l.loop(fly, key: "fly", delay: Double(-i) * 17)

      let glide = CALayer()
      glide.loop(swing("transform.translation.y", from: -4, to: 4, duration: 2.4), key: "glide")
      l.addSublayer(glide)
      let px = density(s)
      let parts = birdParts(sp, flying: true)
      _ = glide.addSprite(render(parts.below, pixelsPerUnit: px))
      let wing = glide.addSprite(render(parts.wing, pixelsPerUnit: px), pivot: CGPoint(x: 0, y: -12))
      wing.loop(flap(duration: 0.42), key: "flap")
      _ = glide.addSprite(render(parts.above, pixelsPerUnit: px))
      flyers.addSublayer(l)
    }
  }
}

// MARK: - Regions

private let BAMBOO: [(x: Double, base: Double, h: Double, lean: Double, w: Double)] = (0..<18).map { i in
  let r = Rng(7, i, 11)
  return (1180 + r() * 340, 700 + r() * 150, 150 + r() * 150, (r() - 0.5) * 16, 5 + r() * 3)
}
private let PADS: [(x: Double, y: Double, s: Double, rot: Double)] = (0..<7).map { i in
  let r = Rng(9, i, 4)
  return (-50 + r() * 100, -8 + r() * 16, 0.7 + r() * 0.6, r() * 40)
}
private let MEADOW: [(x: Double, y: Double, s: Double)] = (0..<28).map { i in
  let r = Rng(3, i, 8)
  return (40 + r() * 340, 760 + r() * 120, 0.7 + r() * 0.7)
}
private let STREAM = "M1002 610 C 860 660, 620 700, 420 735 S 250 755, 210 762"

extension JungleScene {
  func buildRegions() {
    // Region art is added first, so it stays behind every plant in its band.
    // Waterfall, far band.
    waterfall.position = CGPoint(x: 990, y: 420)
    waterfall.addSublayer(waterfallArt)
    for i in 0..<4 {
      let line = CAShapeLayer()
      line.path = svgPath("M\(2 + i * 7) 36 L\(1 + i * 7) 184")
      line.strokeColor = cgColor("#f7fffe")
      line.lineWidth = 1.6
      line.opacity = 0.7
      line.lineDashPattern = [10, 18]
      line.loop(flow(duration: 2.8), key: "flow")
      waterfall.addSublayer(line)
    }
    let splash = CAShapeLayer()
    splash.path = ellipsePath(12, 190, 34, 8)
    splash.fillColor = cgColor("#e7f4f2")
    splash.opacity = 0.55
    waterfall.addSublayer(splash)
    bands[0].addSublayer(waterfall)

    // Stream and bamboo, middle band.
    for (l, dash) in [(streamWater, false), (streamShine, true)] {
      l.path = svgPath(STREAM)
      l.fillColor = nil
      l.lineCap = .round
      if dash {
        l.strokeColor = cgColor("#e7f6f4")
        l.lineWidth = 1.6
        l.lineDashPattern = [10, 24]
        l.loop(flow(duration: 18), key: "flow")
      }
      stream.addSublayer(l)
    }
    bands[1].addSublayer(stream)
    bands[1].addSublayer(bamboo)

    // Meadow and pond, near band.
    pond.position = CGPoint(x: 210, y: 762)
    pond.addSublayer(pondArt)
    frog.position = CGPoint(x: 18, y: -2)
    frog.loop(hop(duration: 11), key: "hop")
    pond.addSublayer(frog)
    pond.addSublayer(dragonflies)
    bands[2].addSublayer(meadow)
    bands[2].addSublayer(pond)
  }

  func recolorRegions(_ pal: Palette) {
    let px = density(1)
    waterfallArt.setSprite(
      render(
        [
          .fill("M-18 20 L-34 190 L-8 190 L-2 28 Z", .solid(shade(pal.hillNear, -0.2))),
          .fill("M36 16 L52 190 L26 190 L20 24 Z", .solid(shade(pal.hillNear, -0.35))),
          .fill("M-2 24 L-6 188 L28 188 L24 24 Z", .vertical([(0, "#ffffff", 0.45), (0.35, "#f7fffe", 0.95), (1, "#c9ebe6", 0.9)])),
        ], pixelsPerUnit: px))
    streamWater.strokeColor = cgColor(mix("#1e5c68", pal.leafMid, 0.35))

    let bambooOps: [Op] = BAMBOO.enumerated().map { (i, s) in
      var g: [Op] = [
        .stroke("M0 0 Q\(f(s.lean * 0.4)) \(f(-s.h * 0.5)) \(f(s.lean)) \(f(-s.h))", Stroke(color: i % 2 == 1 ? "#6f9a4e" : "#8fb86a", width: s.w, cap: .round))
      ]
      for t in [0.3, 0.5, 0.7] {
        g.append(.stroke("M\(f(s.lean * t - 4)) \(f(-s.h * t)) h8", Stroke(color: shade("#6f9a4e", -0.25), width: 1.2)))
      }
      g.append(.fill("M\(f(s.lean)) \(f(-s.h)) q12 -16 22 -6 q-14 2 -22 10Z", .solid("#9ccc72")))
      g.append(.fill("M\(f(s.lean)) \(f(-s.h + 6)) q-14 -12 -24 -2 q14 0 24 8Z", .solid("#7eac58")))
      return .group(g, translate(s.x, s.base))
    }
    bamboo.setSprite(render(bambooOps, pixelsPerUnit: px))

    let pad = shade(pal.leafMid, 0.05)
    let colors = ["#f4b4c8", "#fff6ea", "#f0d15a", "#f29a52"]
    let meadowOps: [Op] = MEADOW.enumerated().map { (i, m) in
      .group(
        [
          .stroke("M0 0 Q1 -8 0 -14", Stroke(color: pad, width: 1)),
          .fill(circlePath(0, -15, 3.1), .solid(colors[i % 4])),
          .fill(circlePath(0, -15, 1), .solid("#f7e7a0")),
        ], translate(m.x, m.y).then(scale(m.s)))
    }
    meadow.setSprite(render(meadowOps, pixelsPerUnit: px))

    frog.sublayers?.forEach { $0.removeFromSuperlayer() }
    _ = frog.addSprite(
      render(
        [
          .fill(ellipsePath(0, 0, 7, 4.5), .solid("#3d8a45")),
          .fill(circlePath(-3.5, -4, 2.1), .solid("#3d8a45")),
          .fill(circlePath(2.2, -4.4, 2.1), .solid("#3d8a45")),
          .fill(circlePath(-3.5, -4.3, 0.7), .solid("#1b1b1b")),
          .fill(circlePath(2.2, -4.7, 0.7), .solid("#1b1b1b")),
        ], pixelsPerUnit: px * 2))

    dragonflies.sublayers?.forEach { $0.removeFromSuperlayer() }
    for (i, (x, y)) in [(-30.0, -18.0), (48, -10)].enumerated() {
      let fly = CALayer()
      fly.position = CGPoint(x: x, y: y)
      let a = CABasicAnimation(keyPath: "transform.translation")
      a.fromValue = NSValue(size: .zero)
      a.toValue = NSValue(size: CGSize(width: 16, height: -12))
      a.duration = 9
      a.autoreverses = true
      a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      fly.loop(a, key: "dfly", delay: Double(-i) * 3)
      _ = fly.addSprite(render([.fill(ellipsePath(0, 0, 7, 1.5), .solid("#2a3330"))], pixelsPerUnit: px * 2))
      let wings = fly.addSprite(
        render(
          [
            .fill(ellipsePath(-1, -3, 6, 2.2), .solid("#b9e4ea"), opacity: 0.75),
            .fill(ellipsePath(-1, 3, 6, 2.2), .solid("#b9e4ea"), opacity: 0.75),
          ], pixelsPerUnit: px * 2))
      wings.loop(flap(duration: 0.18), key: "flap")
      dragonflies.addSublayer(fly)
    }
    pondKey = ""
  }

  func updateRegions(_ input: SceneInput) {
    let r = input.regions
    let pal = input.season.palette
    waterfall.isHidden = r.waterfall <= 0.01
    waterfall.opacity = Float(r.waterfall)
    stream.isHidden = !(r.waterfall > 0.01 && r.wetlands > 0.01)
    streamWater.lineWidth = 4 + r.waterfall * 4
    streamWater.opacity = Float(0.8 * min(r.waterfall, r.wetlands))
    streamShine.opacity = Float(0.65 * min(r.waterfall, r.wetlands))
    bamboo.isHidden = r.bamboo <= 0.01
    bamboo.opacity = Float(r.bamboo)
    meadow.isHidden = r.meadow <= 0.01
    meadow.opacity = Float(r.meadow)

    let size = (r.pond * 50).rounded() / 50
    pond.isHidden = size <= 0.04
    pond.opacity = Float(min(1, r.wetlands))
    frog.isHidden = size <= 0.45
    dragonflies.isHidden = size <= 0.35
    let key = "\(paletteKey)|\(size)"
    if !pond.isHidden && key != pondKey {
      pondKey = key
      let pad = shade(pal.leafMid, 0.05)
      var ops: [Op] = [
        .fill(ellipsePath(8, 10, 160 * size, 36 * size), .solid("#16343a"), opacity: 0.28),
        .fill(
          ellipsePath(0, 0, 150 * size, 32 * size),
          .radial(
            cx: 0.4, cy: 0.35, r: 0.8,
            stops: [
              (0, mix("#d7f1ec", pal.leafLight, 0.25), 1), (0.55, mix("#2f7c86", pal.leafDark, 0.25), 1),
              (1, mix("#163840", pal.leafDark, 0.4), 1),
            ])),
        .fill(ellipsePath(0, -6, 96 * size, 10 * size), .solid("#dff4f1"), opacity: 0.28),
      ]
      for p in PADS {
        ops.append(
          .group(
            [
              .fill(ellipsePath(0, 5, 13, 3.2), .solid("#10282c"), opacity: 0.25),
              .fill(ellipsePath(0, 0, 14, 6.5), .solid(pad)),
              .stroke("M0 -5 L0 5", Stroke(color: shade(pad, -0.25), width: 0.7)),
            ], translate(p.x * size, p.y * size).then(rotate(p.rot)).then(scale(p.s * size))))
      }
      pondArt.setSprite(render(ops, pixelsPerUnit: density(1)))
    }
  }
}

/// A cubic Bézier flight path that can be walked by distance travelled
/// rather than by its curve parameter, which bunches up on the bends.
private struct FlightRoute {
  let p: [CGPoint]
  /// Distance covered at each of `steps` evenly spaced curve parameters.
  private var lengths: [Double] = [0]
  private let steps = 96

  init(_ p: [CGPoint]) {
    self.p = p
    var prev = point(0)
    for k in 1...steps {
      let pt = point(Double(k) / Double(steps))
      lengths.append(lengths[k - 1] + hypot(pt.x - prev.x, pt.y - prev.y))
      prev = pt
    }
  }

  var length: Double { lengths[steps] }

  private func point(_ t: Double) -> CGPoint {
    let u = 1 - t
    let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
    return CGPoint(x: w0 * p[0].x + w1 * p[1].x + w2 * p[2].x + w3 * p[3].x, y: w0 * p[0].y + w1 * p[1].y + w2 * p[2].y + w3 * p[3].y)
  }

  private func tangent(_ t: Double) -> CGPoint {
    let u = 1 - t
    let w0 = 3 * u * u, w1 = 6 * u * t, w2 = 3 * t * t
    return CGPoint(
      x: w0 * (p[1].x - p[0].x) + w1 * (p[2].x - p[1].x) + w2 * (p[3].x - p[2].x),
      y: w0 * (p[1].y - p[0].y) + w1 * (p[2].y - p[1].y) + w2 * (p[3].y - p[2].y))
  }

  /// The point `fraction` of the way along by distance, and the direction of travel there.
  func at(_ fraction: Double) -> (CGPoint, CGPoint) {
    let target = max(0, min(1, fraction)) * length
    var lo = 0, hi = steps
    while hi - lo > 1 {
      let mid = (lo + hi) / 2
      if lengths[mid] < target { lo = mid } else { hi = mid }
    }
    let seg = lengths[hi] - lengths[lo]
    let t = (Double(lo) + (seg > 0 ? (target - lengths[lo]) / seg : 0)) / Double(steps)
    return (point(t), tangent(t))
  }
}

/// How fast a bird covers a leg over time, relative to its cruise: starting at
/// `boost` times cruise and easing back over the first `boostSpan` of the leg,
/// and slowing to a stop over the last `brakeSpan`.
private struct SpeedProfile {
  let boost, boostSpan, brakeSpan: Double

  /// Distance at time `u`, both as fractions of the leg, before normalising.
  private func raw(_ u: Double) -> Double {
    let a = min(u, boostSpan)
    var d = a + (boostSpan > 0 ? (boost - 1) * (a - a * a / (2 * boostSpan)) : 0)
    let cruiseEnd = 1 - brakeSpan
    d += max(0, min(u, cruiseEnd) - boostSpan)
    if u > cruiseEnd && brakeSpan > 0 {
      let s = u - cruiseEnd
      d += s - s * s / (2 * brakeSpan)
    }
    return d
  }

  /// Average speed over the leg as a multiple of cruise.
  var mean: Double { raw(1) }

  /// Fraction of the route covered at fraction `u` of the leg's time.
  func distance(_ u: Double) -> Double { raw(u) / mean }
}

private func smoothstep(_ x: Double) -> Double {
  let t = max(0, min(1, x))
  return t * t * (3 - 2 * t)
}
