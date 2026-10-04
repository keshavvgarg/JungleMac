import QuartzCore

/// Looping scene motion is slow, so 24 fps looks the same as the display rate
/// and lets the render server draw far fewer frames.
let SCENE_FPS = CAFrameRateRange(minimum: 8, maximum: 30, __preferred: 24)

extension CALayer {
  /// A child layer showing `sprite`, with the drawing's local `pivot` placed at
  /// `pivot` in this layer's coordinates (and used as its anchor).
  func addSprite(_ sprite: Sprite?, pivot: CGPoint = .zero) -> CALayer {
    let l = CALayer()
    l.setSprite(sprite, pivot: pivot)
    addSublayer(l)
    return l
  }

  func setSprite(_ sprite: Sprite?, pivot: CGPoint = .zero) {
    guard let sprite else {
      contents = nil
      return
    }
    let r = sprite.rect
    bounds = CGRect(x: 0, y: 0, width: r.width, height: r.height)
    anchorPoint = CGPoint(x: (pivot.x - r.minX) / r.width, y: (pivot.y - r.minY) / r.height)
    position = pivot
    contents = sprite.image
  }

  /// Inserts `layer` among the sublayers in order of `sortY`, back to front,
  /// like the web version's per-band sort. Sublayers without one stay behind.
  func insert(_ layer: CALayer, sortY: Double) {
    layer.setValue(sortY, forKey: "sortY")
    let subs = sublayers ?? []
    var lo = 0, hi = subs.count
    while lo < hi {
      let mid = (lo + hi) / 2
      let y = subs[mid].value(forKey: "sortY") as? Double ?? -.infinity
      if y <= sortY { lo = mid + 1 } else { hi = mid }
    }
    insertSublayer(layer, at: UInt32(lo))
  }

  /// The current time in this layer's (possibly paused) time space.
  var localNow: CFTimeInterval { convertTime(CACurrentMediaTime(), from: nil) }

  /// Adds a looping animation whose phase is `delay` seconds into its cycle,
  /// like a negative CSS `animation-delay`.
  func loop(_ anim: CAAnimation, key: String, delay: Double = 0) {
    anim.beginTime = localNow + delay
    anim.repeatCount = .infinity
    anim.isRemovedOnCompletion = false
    anim.preferredFrameRateRange = SCENE_FPS
    add(anim, forKey: key)
  }

  /// Freezes every animation below this layer in place.
  func pause() {
    guard speed != 0 else { return }
    let t = convertTime(CACurrentMediaTime(), from: nil)
    speed = 0
    timeOffset = t
  }

  /// Resumes from exactly where `pause` left off.
  func resume() {
    guard speed == 0 else { return }
    let paused = timeOffset
    speed = 1
    timeOffset = 0
    beginTime = 0
    beginTime = convertTime(CACurrentMediaTime(), from: nil) - paused
  }
}

/// `from` to `to` and back, eased, like `animation: ... ease-in-out infinite alternate`.
func swing(_ keyPath: String, from: Any, to: Any, duration: Double) -> CABasicAnimation {
  let a = CABasicAnimation(keyPath: keyPath)
  a.fromValue = from
  a.toValue = to
  a.duration = duration
  a.autoreverses = true
  a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
  return a
}

/// The CSS `hop` keyframes: still, then a small 3px hop near the end of each cycle.
func hop(duration: Double) -> CAKeyframeAnimation {
  let a = CAKeyframeAnimation(keyPath: "transform.translation.y")
  a.values = [0, 0, -3, 0, 0]
  a.keyTimes = [0, 0.88, 0.92, 0.96, 1]
  a.duration = duration
  a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
  return a
}

/// The CSS `flap` keyframes: a wing folding over and back.
func flap(duration: Double) -> CABasicAnimation {
  swing("transform.scale.y", from: 1, to: -0.7, duration: duration)
}

/// Marching dashes, like animating `stroke-dashoffset` to -140.
func flow(duration: Double) -> CABasicAnimation {
  let a = CABasicAnimation(keyPath: "lineDashPhase")
  a.fromValue = 0
  a.toValue = -140
  a.duration = duration
  return a
}

func gradientLayer(_ stops: [Stop], frame: CGRect) -> CAGradientLayer {
  let g = CAGradientLayer()
  g.frame = frame
  g.setStops(stops)
  g.startPoint = CGPoint(x: 0.5, y: 0)
  g.endPoint = CGPoint(x: 0.5, y: 1)
  return g
}

extension CAGradientLayer {
  func setStops(_ stops: [Stop]) {
    colors = stops.map { cgColor($0.1, $0.2) }
    locations = stops.map { NSNumber(value: $0.0) }
  }
}

/// Runs `body` without implicit animations, or with them over `duration`.
func transaction(_ duration: Double? = nil, _ body: () -> Void) {
  CATransaction.begin()
  if let duration {
    CATransaction.setAnimationDuration(duration)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
  } else {
    CATransaction.setDisableActions(true)
  }
  body()
  CATransaction.commit()
}
