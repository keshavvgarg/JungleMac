import QuartzCore

/// Season particles, drizzle, lightning and fireflies, in view coordinates (y up).
/// Each kind is a CAEmitterLayer, which the render server simulates without
/// any work from the app.
@MainActor
final class WeatherLayers {
  /// Below the fog and day wash.
  let main = CALayer()
  /// Above the day wash, like the web version.
  let fireflies = CAEmitterLayer()

  /// One emitter per season, indexed like SEASONS: petals, motes, rain, leaves, snow.
  private var seasons: [CAEmitterLayer] = []
  private let drizzle = CAEmitterLayer()
  private let storm = CALayer()
  private var flashes: [(layer: CAGradientLayer, bolt: CAShapeLayer, x: Double)] = []
  private var size = CGSize(width: 1600, height: 900)

  init() {
    seasons = (0..<5).map { _ in CAEmitterLayer() }
    for e in seasons + [drizzle] { main.addSublayer(e) }
    main.addSublayer(storm)
    for e in seasons + [drizzle, fireflies] {
      e.opacity = 0
      e.birthRate = 0
    }
    storm.opacity = 0
    for (x, duration, delay, d) in [
      (0.28, 11.0, -3.0, "M40 0 L30 70 L46 72 L26 160 L42 162 L20 270"),
      (0.71, 17, -11, "M40 0 L48 60 L34 64 L52 150 L38 152 L56 250"),
    ] {
      let flash = CAGradientLayer()
      flash.type = .radial
      flash.colors = [rgba(255, 255, 255, 0.8), rgba(215, 225, 255, 0.3), rgba(215, 225, 255, 0.08)]
      flash.locations = [0, 0.55, 0.85]
      flash.opacity = 0
      let bolt = CAShapeLayer()
      bolt.path = svgPath(d)
      bolt.strokeColor = cgColor("#fbfdff")
      bolt.fillColor = nil
      bolt.lineWidth = 2.4
      bolt.lineJoin = .bevel
      bolt.shadowColor = rgba(200, 215, 255, 1)
      bolt.shadowOpacity = 0.9
      bolt.shadowRadius = 8
      bolt.shadowOffset = .zero
      flash.addSublayer(bolt)
      let a = CAKeyframeAnimation(keyPath: "opacity")
      a.values = [0, 0, 1, 0.15, 0.9, 0, 0]
      a.keyTimes = [0, 0.89, 0.9, 0.91, 0.925, 0.95, 1]
      a.duration = duration
      flash.loop(a, key: "thunder", delay: delay)
      storm.addSublayer(flash)
      flashes.append((flash, bolt, x))
    }
  }

  func layout(size: CGSize) {
    self.size = size
    let w = size.width, h = size.height
    main.frame = CGRect(origin: .zero, size: size)
    storm.frame = main.bounds
    for (i, e) in seasons.enumerated() {
      e.frame = main.bounds
      e.emitterCells = [cell(kind: i)]
      if i == 1 {
        // Motes float up from the lower part of the view.
        e.emitterShape = .rectangle
        e.emitterPosition = CGPoint(x: w / 2, y: h * 0.4)
        e.emitterSize = CGSize(width: w * 1.1, height: h * 0.6)
      } else {
        // A thin rectangle, not `.line`: on macOS a line emitter's particles
        // stay on the line instead of travelling.
        e.emitterShape = .rectangle
        // Rain slants left as it falls, so it starts a little further right.
        e.emitterPosition = CGPoint(x: w / 2 + (i == MONSOON ? w * 0.1 : 0), y: h + 30)
        e.emitterSize = CGSize(width: w * 1.2, height: 1)
      }
    }
    drizzle.frame = main.bounds
    drizzle.emitterShape = .rectangle
    drizzle.emitterPosition = CGPoint(x: w / 2 + w * 0.1, y: h + 30)
    drizzle.emitterSize = CGSize(width: w * 1.2, height: 1)
    drizzle.emitterCells = [rainCell(perSecond: 50, lifetime: 0.95)]
    fireflies.frame = main.bounds
    fireflies.emitterShape = .rectangle
    fireflies.emitterPosition = CGPoint(x: w / 2, y: h * 0.43)
    fireflies.emitterSize = CGSize(width: w, height: h * 0.55)
    fireflies.emitterCells = [fireflyCell()]
    for f in flashes {
      // A radial glow centred near the top, at the bolt's column.
      f.layer.frame = main.bounds
      f.layer.startPoint = CGPoint(x: f.x, y: 0.95)
      f.layer.endPoint = CGPoint(x: f.x + 1.1, y: 0.95 - 1.1)
      // The bolt is drawn y-down in an 80x280 box, hung from the top edge and
      // stretched to 48% of the height (flipping y for this y-up layer).
      f.bolt.bounds = CGRect(x: 0, y: 0, width: 80, height: 280)
      f.bolt.anchorPoint = .zero
      f.bolt.position = CGPoint(x: w * f.x - 40, y: h)
      f.bolt.transform = CATransform3DMakeScale(1, -h * 0.48 / 280, 1)
    }
  }

  func update(weights: [Double], drizzle amount: Double, storm strength: Double, fireflies glow: Double) {
    for (i, e) in seasons.enumerated() {
      setLevel(e, weights[i] < 0.01 ? 0 : weights[i])
    }
    setLevel(drizzle, amount < 0.02 ? 0 : amount)
    setLevel(fireflies, glow < 0.02 ? 0 : glow)
    storm.isHidden = strength < 0.01
    storm.opacity = Float(strength)
  }

  /// Shows an emitter at `level` opacity, and stops it creating particles when hidden.
  private func setLevel(_ e: CAEmitterLayer, _ level: Double) {
    let on = level > 0
    if on && e.birthRate == 0 {
      // Pre-fill the sky, like the web version's negative animation delays.
      e.beginTime = (e.superlayer?.localNow ?? CACurrentMediaTime()) - 30
    }
    e.birthRate = on ? 1 : 0
    e.opacity = Float(level)
  }

  // MARK: - Cells

  private func cell(kind: Int) -> CAEmitterCell {
    switch kind {
    case SPRING: return fallingCell(image: petalImage("#f6c6d3"), perSecond: 22 / 23.0, lifetime: 23, size: 10)
    case SUMMER: return moteCell()
    case MONSOON: return rainCell(perSecond: 120, lifetime: 0.75)
    case AUTUMN: return fallingCell(image: petalImage("#c8702f", flipped: true), perSecond: 16 / 23.0, lifetime: 23, size: 10)
    default: return fallingCell(image: dotImage("#ffffff", 0.9), perSecond: 30 / 19.0, lifetime: 19, size: 5)
    }
  }

  private func fallingCell(image: CGImage?, perSecond: Double, lifetime: Double, size px: Double) -> CAEmitterCell {
    let c = CAEmitterCell()
    c.contents = image
    c.birthRate = Float(perSecond)
    c.lifetime = Float(lifetime)
    c.lifetimeRange = Float(lifetime * 0.2)
    c.velocity = CGFloat(size.height * 1.25 / lifetime)
    c.velocityRange = c.velocity * 0.2
    c.emissionLongitude = -.pi / 2
    c.emissionRange = 0.12
    c.spin = 0.4
    c.spinRange = 0.8
    c.scale = CGFloat(px / 20)
    c.scaleRange = c.scale * 0.3
    return c
  }

  private func moteCell() -> CAEmitterCell {
    let c = CAEmitterCell()
    c.contents = glowImage(rgba(255, 251, 224, 1))
    c.birthRate = 16 / 11
    c.lifetime = 11
    c.lifetimeRange = 5
    c.velocity = 7
    c.velocityRange = 4
    c.emissionLongitude = .pi / 2
    c.emissionRange = .pi / 3
    c.scale = 0.5
    c.scaleRange = 0.2
    c.alphaRange = 0.4
    c.alphaSpeed = -0.07
    return c
  }

  private func rainCell(perSecond: Double, lifetime: Double) -> CAEmitterCell {
    let c = CAEmitterCell()
    c.contents = rainImage()
    c.birthRate = Float(perSecond)
    c.lifetime = Float(lifetime)
    c.lifetimeRange = Float(lifetime * 0.3)
    c.velocity = CGFloat(size.height * 1.3 / lifetime)
    c.velocityRange = c.velocity * 0.15
    // Slanted, drifting left as it falls, like the web version.
    c.emissionLongitude = -.pi / 2 - 0.175
    c.scale = 0.5
    c.scaleRange = 0.15
    return c
  }

  private func fireflyCell() -> CAEmitterCell {
    let c = CAEmitterCell()
    c.contents = glowImage(rgba(230, 243, 164, 1), core: true)
    c.birthRate = 18 / 14
    c.lifetime = 14
    c.lifetimeRange = 5
    c.velocity = 5
    c.velocityRange = 4
    c.emissionRange = 2 * .pi
    c.scale = 0.45
    c.alphaRange = 0.5
    c.alphaSpeed = -0.06
    return c
  }
}

// MARK: - Particle images

private func image(_ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
  guard
    let ctx = CGContext(
      data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return nil }
  draw(ctx)
  return ctx.makeImage()
}

/// A petal or leaf: two opposite rounded corners, like `border-radius: 80% 0 80% 0`.
private func petalImage(_ hex: String, flipped: Bool = false) -> CGImage? {
  image(CGSize(width: 20, height: 14)) { ctx in
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 14))
    p.addQuadCurve(to: CGPoint(x: 20, y: 0), control: CGPoint(x: 0, y: 0))
    p.addQuadCurve(to: CGPoint(x: 0, y: 14), control: CGPoint(x: 20, y: 14))
    if flipped {
      ctx.translateBy(x: 20, y: 0)
      ctx.scaleBy(x: -1, y: 1)
    }
    ctx.addPath(p)
    ctx.setFillColor(cgColor(hex, 0.85))
    ctx.fillPath()
  }
}

private func dotImage(_ hex: String, _ alpha: Double) -> CGImage? {
  image(CGSize(width: 20, height: 20)) { ctx in
    ctx.setFillColor(cgColor(hex, alpha))
    ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 20, height: 20))
  }
}

private func glowImage(_ color: CGColor, core: Bool = false) -> CGImage? {
  image(CGSize(width: 28, height: 28)) { ctx in
    let g = CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      colors: [color, color.copy(alpha: core ? 0.6 : 0.5)!, color.copy(alpha: 0)!] as CFArray, locations: [0, core ? 0.15 : 0.3, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: 14, y: 14), startRadius: 0, endCenter: CGPoint(x: 14, y: 14), endRadius: 14, options: [])
  }
}

/// A slanted streak, faint at the top and brighter at the bottom.
private func rainImage() -> CGImage? {
  image(CGSize(width: 12, height: 56)) { ctx in
    ctx.translateBy(x: 6, y: 28)
    ctx.rotate(by: 0.175)
    let g = CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      colors: [rgba(225, 235, 245, 0.75), rgba(225, 235, 245, 0)] as CFArray, locations: [0, 1])!
    ctx.addRect(CGRect(x: -1.5, y: -26, width: 3, height: 52))
    ctx.clip()
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: -26), end: CGPoint(x: 0, y: 26), options: [])
  }
}
