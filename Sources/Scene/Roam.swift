import QuartzCore

/// How an animal's legs move as it walks. Each foot stays planted while the
/// body passes over it, then swings forward quickly. The body covers `stride`
/// per cycle, so legs and ground speed always agree and nothing skates.
struct Gait {
  /// Where each leg starts in the cycle, as a fraction of it.
  var offsets: [Double]
  /// Share of the cycle each foot spends on the ground.
  var duty: Double
  /// How far a leg swings either side of straight down, in radians.
  var swing: Double
  /// Hip to foot, in the art's units.
  var length: Double

  /// Ground covered per cycle, in the art's units.
  var stride: Double { 2 * length * sin(swing) / duty }

  /// Leg `i`'s angle `phase` cycles into walking. Negative is forward.
  func angle(_ i: Int, _ phase: Double) -> Double {
    let p = (phase + offsets[i]).truncatingRemainder(dividingBy: 1)
    if p < duty { return -swing + 2 * swing * p / duty }
    let s = (p - duty) / (1 - duty)
    return swing - 2 * swing * s * s * (3 - 2 * s)
  }

  /// A four-legged walk, legs in the art's order: far hind, far front, near
  /// hind, near front. Each side steps hind then front, as cats, deer and
  /// elephants do at a walk.
  static func fourLegged(duty: Double, swing: Double, length: Double) -> Gait {
    Gait(offsets: [0.5, 0.25, 0, 0.75], duty: duty, swing: swing, length: length)
  }

  /// Two legs stepping in turn, far leg first.
  static func twoLegged(duty: Double, swing: Double, length: Double) -> Gait {
    Gait(offsets: [0.5, 0], duty: duty, swing: swing, length: length)
  }
}

/// An animal's wanderings as one looping timeline, built a step at a time:
/// standing about, walking, hopping and turning, plus named tracks (a head
/// lowering, an ear twitching) keyed along the way. Positions are in world
/// units. Walks are whole strides, so the legs end the loop where they began.
struct Roam {
  private(set) var t = 0.0
  private(set) var x: Double
  private(set) var facing: Double
  /// Where the loop starts and ends.
  let start: Double
  /// Ground covered per stride, in world units.
  let stride: Double
  /// Keyframes a second while moving.
  let rate: Double

  private var times: [Double] = []
  private var xs: [Double] = []
  private var lifts: [Double] = []
  private var walked: [Double] = []
  private var distance = 0.0
  private var tracks: [String: [(t: Double, v: Double)]] = [:]

  init(x: Double, facing: Double, stride: Double = 1, rate: Double = 20) {
    self.x = x
    self.start = x
    self.facing = facing
    self.stride = stride
    self.rate = rate
    key()
    set("face", facing)
  }

  var period: Double { t }

  private mutating func key(lift: Double = 0) {
    times.append(t)
    xs.append(x)
    lifts.append(lift)
    walked.append(distance)
  }

  /// Stands where it is for `d` seconds.
  mutating func wait(_ d: Double) {
    guard d > 0 else { return }
    t += d
    key()
  }

  /// Walks `strides` strides the way it faces at `speed` world units a
  /// second, easing in and out over `ease` seconds. The body rises and falls
  /// `bob` world units twice a stride.
  mutating func walk(_ strides: Int, speed: Double, ease: Double = 0.6, bob: Double = 0) {
    guard strides > 0 else { return }
    let d = Double(strides) * stride
    let r = min(ease, d / speed)
    let total = d / speed + r
    let x0 = x, d0 = distance, t0 = t
    func progress(_ tau: Double) -> (s: Double, v: Double) {
      func rampDistance(_ u: Double) -> Double { speed * r * (u * u * u - u * u * u * u / 2) }
      func rampSpeed(_ u: Double) -> Double { speed * u * u * (3 - 2 * u) }
      if tau < r { return (rampDistance(tau / r), rampSpeed(tau / r)) }
      if tau < total - r { return (speed * r / 2 + speed * (tau - r), speed) }
      let w = (total - tau) / r
      return (d - rampDistance(w), rampSpeed(w))
    }
    let n = max(2, Int((total * rate).rounded(.up)))
    for i in 1...n {
      let tau = total * Double(i) / Double(n)
      let (s, v) = progress(tau)
      t = t0 + tau
      x = x0 + facing * s
      distance = d0 + s
      key(lift: -bob * (v / speed) * (0.5 - 0.5 * cos(4 * .pi * s / stride)))
    }
    x = x0 + facing * d
    distance = d0 + d
  }

  /// Whole strides from here to `target`, at least one.
  func strides(to target: Double) -> Int { max(1, Int((abs(target - x) / stride).rounded())) }

  /// One hop `length` world units ahead and `height` high, over `d` seconds.
  mutating func hop(_ length: Double, height: Double, duration d: Double) {
    let x0 = x, t0 = t
    let n = max(8, Int((d * rate).rounded(.up)))
    for i in 1...n {
      let u = Double(i) / Double(n)
      t = t0 + u * d
      x = x0 + facing * length * u
      key(lift: -4 * height * u * (1 - u))
    }
  }

  /// Turns round on the spot over `d` seconds.
  mutating func turn(_ d: Double = 0.3) {
    set("face", facing)
    t += d
    facing = -facing
    set("face", facing)
    key()
  }

  /// Moves straight to `x`, for coming back on at one edge after leaving by the other.
  mutating func jump(to target: Double) {
    t += 0.001
    x = target
    key()
  }

  /// Keys `name` to `value`, `delay` seconds from now.
  mutating func set(_ name: String, _ value: Double, after delay: Double = 0) {
    var keys = tracks[name] ?? []
    let time = max(t + delay, (keys.last?.t ?? -1) + 0.001)
    keys.append((time, value))
    tracks[name] = keys
  }

  /// Moves `name` from where it was last keyed to `value` over `d` seconds,
  /// starting `delay` seconds from now.
  mutating func ease(_ name: String, to value: Double, over d: Double, after delay: Double = 0) {
    set(name, current(name), after: delay)
    set(name, value, after: delay + d)
  }

  func current(_ name: String) -> Double { tracks[name]?.last?.v ?? 0 }

  // MARK: - Animations

  private func normalized(_ ts: [Double]) -> [NSNumber] { ts.map { NSNumber(value: min(1, $0 / t)) } }

  /// The path, with its feet on `y`.
  func position(y: Double) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: "position")
    a.values = zip(xs, lifts).map { NSValue(point: CGPoint(x: $0, y: y + $1)) }
    a.keyTimes = normalized(times)
    a.duration = t
    return a
  }

  /// Leg angles for `gait` on a rig drawn at `scale`.
  func legs(_ gait: Gait, scale: Double) -> [CAKeyframeAnimation] {
    let stride = gait.stride * scale
    let keyTimes = normalized(times)
    return gait.offsets.indices.map { i in
      let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
      a.values = walked.map { gait.angle(i, $0 / stride) }
      a.keyTimes = keyTimes
      a.duration = t
      return a
    }
  }

  /// Track `name` driving `keyPath`, its values multiplied by `scale`.
  /// Eased between keys unless `eased` is false.
  func track(_ name: String, _ keyPath: String, scale: Double = 1, eased: Bool = true) -> CAKeyframeAnimation? {
    guard var keys = tracks[name]?.filter({ $0.t <= t }), let last = keys.last else { return nil }
    if keys[0].t > 0 { keys.insert((0, last.v), at: 0) }
    if last.t < t { keys.append((t, last.v)) }
    let a = CAKeyframeAnimation(keyPath: keyPath)
    a.values = keys.map { $0.v * scale }
    a.keyTimes = normalized(keys.map(\.t))
    if eased {
      a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: keys.count - 1)
    }
    a.duration = t
    return a
  }
}
