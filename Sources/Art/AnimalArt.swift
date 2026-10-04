import CoreGraphics

/// An animal facing right with its feet on y = 0, split into the parts that
/// move on their own. Every part is drawn in the body's coordinates, and
/// rotates about its `pivot`.
struct AnimalArt {
  struct Part {
    var ops: [Op]
    var pivot: CGPoint
  }
  /// Parts drawn behind the body, such as a peacock's fan.
  var behind: [Part] = []
  var body: [Op]
  /// Walking legs, swung in alternating pairs.
  var legs: [Part] = []
  /// Parts drawn over the body, such as a grazing deer's neck and head.
  var front: [Part] = []
}

// MARK: - Hare

func hareArt() -> AnimalArt {
  let fur = "#a88b6c", dark = "#8c7158"
  return AnimalArt(body: [
    .fill(circlePath(-11, -9, 3.6), .solid("#f4efe6")),
    .fill(ellipsePath(-4, -7, 8, 7), .solid("#9c7f62")),
    .fill(ellipsePath(1, -9, 10, 7.5), .solid(fur), rotate(-8, 1, -9)),
    .fill(ellipsePath(3, -6, 6, 3), .solid("#c9b297"), opacity: 0.7),
    .fill(ellipsePath(-5, -1, 5, 1.8), .solid(dark)),
    .fill(ellipsePath(7, -1, 3.5, 1.5), .solid(dark)),
    .group(
      [.fill(ellipsePath(0, -7, 2.2, 7.5), .solid("#b29676")), .fill(ellipsePath(0, -7, 1, 5.5), .solid("#e6bfae"))],
      translate(11, -19.5).then(rotate(10))),
    .fill(circlePath(10, -15, 5.4), .solid(fur)),
    .group(
      [.fill(ellipsePath(0, -7, 2.2, 7.5), .solid(fur)), .fill(ellipsePath(0, -7, 1, 5.5), .solid("#e6bfae"))],
      translate(8, -19).then(rotate(-12))),
    .fill(circlePath(12, -16, 1), .solid("#2a201a")),
    .fill(circlePath(15.2, -14.5, 0.8), .solid("#d79a8f")),
  ])
}

// MARK: - Peafowl

func peacockArt() -> AnimalArt {
  let blue = "#2b6fc4"
  var fan: [Op] = []
  for k in 0..<17 {
    let a = -175 + Double(k) * 10
    fan.append(
      .group(
        [
          .fill("M0 0 Q6 -28 0 -58 Q-6 -28 0 0Z", .solid(k % 2 == 0 ? "#2f7a4c" : "#3a8a57")),
          .fill(circlePath(0, -49, 5.2), .solid("#3f9a5a")),
          .fill(circlePath(0, -49, 3.8), .solid("#c9a23a")),
          .fill(circlePath(0, -49, 2.6), .solid("#1d4f9e")),
          .fill(circlePath(0, -49, 1.2), .solid("#0f2340")),
        ], translate(-4, -14).then(rotate(a + 90))))
  }
  let train: [Op] = [
    .fill("M-6 -14 Q-40 -12 -66 -3 Q-40 -4 -4 -8Z", .solid("#2f7a4c")),
  ] + [(-30.0, -9.0), (-44, -7), (-56, -5)].flatMap { (x, y) -> [Op] in
    [.fill(circlePath(x, y, 2), .solid("#1d4f9e")), .fill(circlePath(x, y, 1), .solid("#f2c94c"))]
  }
  let body: [Op] =
    train + [
      .stroke("M0 -10 L-1 0 M4 -10 L5 0", Stroke(color: "#8a7a62", width: 1.2)),
      .fill(ellipsePath(2, -16, 9, 7), .solid("#1f5fa8"), rotate(-20, 2, -16)),
      .fill(ellipsePath(-1, -16, 7, 4.5), .solid("#9c8a5a"), rotate(-10, -1, -16)),
      .fill("M5 -20 Q9 -30 10 -36 L14 -35 Q13 -27 10 -18Z", .solid(blue)),
      .stroke("M11 -40 L9 -46 M12 -40 L12 -46.5 M13 -40 L15 -46", Stroke(color: blue, width: 0.6)),
      .fill(circlePath(9, -46, 0.9), .solid(blue)),
      .fill(circlePath(12, -46.5, 0.9), .solid(blue)),
      .fill(circlePath(15, -46, 0.9), .solid(blue)),
      .fill(circlePath(12, -37, 3.2), .solid(blue)),
      .fill(ellipsePath(13, -37.5, 1.6, 0.7), .solid("#ffffff")),
      .fill("M15 -37.5 L18.5 -36.5 L15 -36Z", .solid("#c9b28a")),
      .fill(circlePath(13, -37.6, 0.6), .solid("#111111")),
    ]
  return AnimalArt(behind: [AnimalArt.Part(ops: fan, pivot: CGPoint(x: -4, y: -14))], body: body)
}

// MARK: - Spotted deer

/// A chital; `stag` adds antlers.
func deerArt(stag: Bool) -> AnimalArt {
  let coat = "#c07a3c", legColor = "#9c5e2c"
  var body: [Op] = [
    .fill("M10 -26 L9 -2 L11 0 L13 0 L14 -26Z", .solid(legColor)),
    .fill("M-20 -27 L-22 -12 L-20 -2 L-18 0 L-16 0 L-17 -12 L-14 -27Z", .solid(legColor)),
    .fill("M16 -26 L17 -2 L19 0 L21 0 L20 -26Z", .solid(coat)),
    .fill("M-14 -27 L-16 -12 L-14 -2 L-12 0 L-10 0 L-11 -12 L-8 -27Z", .solid(coat)),
    .fill(ellipsePath(-2, -31, 22, 10), .solid(coat)),
    .fill(ellipsePath(-2, -25, 16, 4), .solid("#f1e6d4"), opacity: 0.9),
    .fill("M-23 -36 Q-28 -32 -25 -26 L-21 -30Z", .solid("#f4eee4")),
  ]
  let spots: [(Double, Double)] = [(-16, -34), (-10, -37), (-4, -35), (2, -38), (8, -35), (-12, -30), (-6, -31), (0, -32), (6, -30), (12, -33), (-18, -29), (14, -37)]
  body += spots.map { .fill(circlePath($0.0, $0.1, 1.3), .solid("#f6efe3")) }
  var head: [Op] = [
    .fill("M12 -36 Q20 -44 23 -52 L30 -50 Q26 -40 21 -30Z", .solid(coat)),
    .fill(ellipsePath(26, -58, 4, 1.8), .solid("#b06c33"), rotate(-30, 26, -58)),
    .fill(ellipsePath(30, -54, 6.5, 4.5), .solid(coat), rotate(25, 30, -54)),
    .fill(ellipsePath(35, -50.5, 2.8, 2.3), .solid("#5a3a22")),
    .fill(circlePath(30, -55.5, 0.9), .solid("#111111")),
  ]
  if stag {
    head.append(
      .stroke(
        "M27 -58 Q25 -68 20 -76 M25 -66 Q30 -70 31 -74 M28 -58 Q31 -66 33 -76 M31 -66 Q35 -68 37 -71",
        Stroke(color: "#7a5a3a", width: 1.4, cap: .round)))
  }
  return AnimalArt(body: body, front: [AnimalArt.Part(ops: head, pivot: CGPoint(x: 16, y: -36))])
}

// MARK: - Elephant

func elephantArt() -> AnimalArt {
  let grey = "#8e9196", shadow = "#7f8287"
  func leg(_ x: Double, _ color: String) -> AnimalArt.Part {
    AnimalArt.Part(
      ops: [
        .fill("M\(f(x - 6)) 0 L\(f(x - 7)) -34 L\(f(x + 7)) -34 L\(f(x + 6)) 0Z", .solid(color)),
        .stroke("M\(f(x - 4)) -1 L\(f(x + 4)) -1", Stroke(color: "#d9d4c8", width: 1.2), opacity: 0.6),
      ], pivot: CGPoint(x: x, y: -30))
  }
  let body: [Op] = [
    .stroke("M-53 -55 Q-58 -44 -56 -34", Stroke(color: shadow, width: 2, cap: .round)),
    .fill(ellipsePath(-8, -52, 46, 30), .solid(grey)),
    .fill(ellipsePath(-12, -66, 30, 12), .solid("#9a9da2"), opacity: 0.6),
    .fill(ellipsePath(34, -58, 20, 22), .solid(grey)),
    .fill("M48 -52 Q56 -36 54 -18 Q53 -8 58 -4 L54 -2 Q48 -8 48 -18 Q49 -34 42 -44Z", .solid(grey)),
    .fill("M46 -42 Q54 -38 58 -40 Q53 -36 45 -38Z", .solid("#f3eee2")),
    .fill(circlePath(42, -64, 1.4), .solid("#222222")),
  ]
  let ear = AnimalArt.Part(
    ops: [
      .fill(ellipsePath(24, -58, 15, 19), .solid(shadow)),
      .fill(ellipsePath(24, -56, 10, 13), .solid("#b7a2a0"), opacity: 0.3),
    ], pivot: CGPoint(x: 34, y: -62))
  // Far legs first, a shade darker.
  return AnimalArt(
    body: body, legs: [leg(-24, shadow), leg(30, shadow), leg(-36, grey), leg(18, grey)], front: [ear])
}

// MARK: - Tiger

func tigerArt() -> AnimalArt {
  let orange = "#d9822b", ink = "#2a1a10", cream = "#f3e3c8"
  func leg(_ x: Double, _ color: String) -> AnimalArt.Part {
    AnimalArt.Part(
      ops: [
        .fill("M\(f(x - 4)) 0 L\(f(x - 5)) -27 L\(f(x + 5)) -27 L\(f(x + 4)) 0Z", .solid(color)),
        .fill(ellipsePath(x + 1, -0.5, 5, 2), .solid(color)),
        .stroke("M\(f(x - 4)) -14 L\(f(x + 3)) -15", Stroke(color: ink, width: 1.6, cap: .round)),
      ], pivot: CGPoint(x: x, y: -26))
  }
  var body: [Op] = [
    .stroke("M-34 -38 Q-50 -40 -54 -28 Q-56 -20 -50 -18", Stroke(color: orange, width: 4, cap: .round)),
    .stroke("M-53 -22 Q-54 -19 -50 -18", Stroke(color: ink, width: 4, cap: .round)),
    .fill("M-34 -30 Q-36 -46 -18 -48 L18 -47 Q34 -46 36 -36 Q36 -26 26 -24 L-26 -24 Q-36 -24 -34 -30Z", .solid(orange)),
    .fill("M-20 -25 Q0 -21 22 -25 L22 -28 Q0 -25 -20 -28Z", .solid(cream)),
  ]
  for d in ["M-24 -47 Q-22 -40 -26 -34", "M-14 -48 Q-12 -40 -16 -33", "M-4 -48 Q-2 -40 -6 -32", "M6 -48 Q8 -41 4 -34", "M16 -47 Q18 -41 14 -35", "M26 -45 Q27 -40 24 -36"] {
    body.append(.stroke(d, Stroke(color: ink, width: 2.4, cap: .round)))
  }
  body += [
    .fill(circlePath(34, -52, 3.5), .solid(orange)),
    .fill(circlePath(44, -53, 3.5), .solid(orange)),
    .fill(circlePath(34, -52, 1.6), .solid(ink)),
    .fill(circlePath(44, -53, 1.6), .solid(ink)),
    .fill(circlePath(40, -42, 11), .solid(orange)),
    .fill(ellipsePath(44, -36.5, 7.5, 5), .solid(cream)),
    .stroke("M38 -52 L39 -47 M42 -53 L42 -48 M31 -42 L35 -41", Stroke(color: ink, width: 1.4, cap: .round)),
    .fill(ellipsePath(50, -40, 2.4, 1.6), .solid("#b4574e")),
    .fill(circlePath(45, -45, 1.3), .solid("#3a3410")),
    .fill(circlePath(45.4, -45.4, 0.4), .solid("#ffffff")),
  ]
  return AnimalArt(body: body, legs: [leg(-14, "#c27325"), leg(26, "#c27325"), leg(-24, orange), leg(16, orange)])
}

// MARK: - Sky and air

/// A shooting star pointing down its +y axis: a bright head and a fading tail.
func meteorOps() -> [Op] {
  [
    .fill("M-1.4 140 L-0.2 0 L0.2 0 L1.4 140Z", .vertical([(0, "#ffffff", 0), (1, "#ffffff", 0.95)])),
    .fill(circlePath(0, 140, 2.2), .radial(cx: 0.5, cy: 0.5, r: 0.5, stops: [(0, "#ffffff", 1), (1, "#ffffff", 0)])),
  ]
}

/// One wavy aurora curtain across the sky, `width` wide.
func auroraOps(_ color: String, width: Double, phase: Double, height: Double) -> [Op] {
  let path = CGMutablePath()
  let steps = 40
  func top(_ x: Double) -> Double { -height * 0.5 + 18 * sin(x / 140 + phase) + 10 * sin(x / 53 + phase * 2) }
  path.move(to: CGPoint(x: 0, y: top(0)))
  for i in 1...steps {
    let x = width * Double(i) / Double(steps)
    path.addLine(to: CGPoint(x: x, y: top(x)))
  }
  for i in stride(from: steps, through: 0, by: -1) {
    let x = width * Double(i) / Double(steps)
    path.addLine(to: CGPoint(x: x, y: top(x) + height))
  }
  path.closeSubpath()
  // Bright, because the night wash and winter fog dim everything behind them.
  return [.fill(path, .vertical([(0, color, 0), (0.3, color, 0.95), (0.65, color, 0.5), (1, color, 0)]))]
}

/// A comet with its head at (0, 0) and its tail streaming up and to the right.
func cometOps() -> [Op] {
  [
    .group(
      [.fill("M-9 0 Q0 -120 -3 -280 L3 -280 Q6 -120 9 0Z", .vertical([(0, "#cfe8ff", 0), (0.6, "#e8f4ff", 0.55), (1, "#ffffff", 1)]))],
      rotate(60)),
    .fill(circlePath(0, 0, 22), .radial(cx: 0.5, cy: 0.5, r: 0.5, stops: [(0, "#ffffff", 1), (0.25, "#ffffff", 0.9), (0.5, "#dff0ff", 0.45), (1, "#bfe0ff", 0)])),
  ]
}

/// A small migrating bird in silhouette, wings spread.
func flockBirdOps() -> [Op] {
  [.stroke("M-7 1 Q-3.5 -3 0 0 Q3.5 -3 7 1", Stroke(color: "#2d2a2a", width: 1.5, cap: .round, join: .round))]
}

/// A butterfly's wings, centred on its body, in `color`.
func butterflyOps(_ color: String) -> [Op] {
  [
    .fill(ellipsePath(-4, -2.5, 4, 3.2), .solid(color)),
    .fill(ellipsePath(4, -2.5, 4, 3.2), .solid(color)),
    .fill(ellipsePath(-3, 2, 2.8, 2.2), .solid(shade(color, -0.15))),
    .fill(ellipsePath(3, 2, 2.8, 2.2), .solid(shade(color, -0.15))),
    .fill(ellipsePath(0, 0, 0.8, 3.6), .solid("#2d2620")),
  ]
}
