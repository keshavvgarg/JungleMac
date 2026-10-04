import CoreGraphics

/// A bird facing right with its feet at (0, 0), split around the wing so a
/// flying bird's wing can flap on its own layer, between body and head.
struct BirdParts {
  var below: [Op]
  var wing: [Op]
  var above: [Op]
  var all: [Op] { below + wing + above }
}

/// `mono` draws every part in one color, for undiscovered species in the field guide.
func birdParts(_ sp: BirdSpecies, flying: Bool = false, mono: String? = nil) -> BirdParts {
  func c(_ color: String) -> String { mono ?? color }
  let t = sp.tail
  let bl = sp.beakLen
  let bd = sp.beakDepth
  var below: [Op] = [
    .fill(
      "M-8 -11 L\(f(-8 - 10 * t)) \(f(-6 + 4 * t)) L\(f(-5 - 10 * t)) \(f(-3 + 4 * t)) L-5 -7Z",
      .solid(c(sp.tailColor ?? sp.wing)))
  ]
  if !flying { below.append(.stroke("M-2 -4 L-2 0 M3 -4 L3 0", Stroke(color: c("#3a302a"), width: 1.1))) }
  below.append(.fill(ellipsePath(0, -10, 11, 7.5), .solid(c(sp.body)), rotate(-15, 0, -10)))
  below.append(.fill(ellipsePath(2, -7, 7, 4.5), .solid(c(sp.belly))))

  let wing: [Op] =
    flying
    ? [.fill("M-7 -12 L4 -12 L-5 -29Z", .solid(c(sp.wing)))]
    : [.fill(ellipsePath(-3, -11, 8, 4.5), .solid(c(sp.wing)), rotate(-10, -3, -11))]

  var above: [Op] = []
  if let crest = sp.crest { above.append(.fill("M5 -19 L2 -27 L9 -21Z", .solid(c(crest)))) }
  above.append(.fill(circlePath(9, -16, 5.5), .solid(c(sp.head ?? sp.body))))
  if let casque = sp.casque { above.append(.fill(ellipsePath(16, -21, 5, 2), .solid(c(casque)))) }
  above.append(
    .fill(
      "M13.5 \(f(-17.5 - bd)) L\(f(13.5 + 6 * bl)) -15.5 L13.5 \(f(-14.5 + bd * 0.6))Z", .solid(c(sp.beak))))
  if mono == nil {
    if let cheek = sp.cheek { above.append(.fill(circlePath(10.5, -13.5, 1.7), .solid(cheek))) }
    above.append(.fill(circlePath(10.5, -17, 1.1), .solid("#111111")))
    above.append(.fill(circlePath(10.9, -17.4, 0.35), .solid("#ffffff")))
  }
  return BirdParts(below: below, wing: wing, above: above)
}
