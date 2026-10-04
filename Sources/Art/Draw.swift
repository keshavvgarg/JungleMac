import CoreGraphics

/// A gradient stop: offset, hex color, opacity.
typealias Stop = (Double, String, Double)

enum Paint {
  case solid(String, Double = 1)
  /// Radial gradient in the shape's bounding box, like SVG's default
  /// `gradientUnits="objectBoundingBox"`.
  case radial(cx: Double, cy: Double, r: Double, stops: [Stop])
  /// Vertical linear gradient in the shape's bounding box, top to bottom.
  case vertical([Stop])
}

struct Stroke {
  var color: String
  var width: Double
  var alpha: Double = 1
  var cap: CGLineCap = .butt
  var join: CGLineJoin = .miter
  var dash: [CGFloat]? = nil
}

/// One shape, or a group drawn into its own transparency layer (SVG `<g opacity>`).
indirect enum Op {
  case shape(CGPath, fill: Paint?, stroke: Stroke?, opacity: Double, transform: CGAffineTransform)
  case group([Op], opacity: Double, transform: CGAffineTransform)

  static func fill(_ path: CGPath, _ paint: Paint, opacity: Double = 1, _ t: CGAffineTransform = .identity) -> Op {
    .shape(path, fill: paint, stroke: nil, opacity: opacity, transform: t)
  }
  static func fill(_ d: String, _ paint: Paint, opacity: Double = 1, _ t: CGAffineTransform = .identity) -> Op {
    .shape(svgPath(d), fill: paint, stroke: nil, opacity: opacity, transform: t)
  }
  static func stroke(_ d: String, _ s: Stroke, opacity: Double = 1, _ t: CGAffineTransform = .identity) -> Op {
    .shape(svgPath(d), fill: nil, stroke: s, opacity: opacity, transform: t)
  }
  static func group(_ ops: [Op], _ t: CGAffineTransform = .identity, opacity: Double = 1) -> Op {
    .group(ops, opacity: opacity, transform: t)
  }
}

/// Bounds of the drawn ops in their own coordinates.
func bounds(of ops: [Op], _ t: CGAffineTransform = .identity) -> CGRect {
  var r = CGRect.null
  for op in ops {
    switch op {
    case let .shape(path, _, stroke, _, tt):
      var b = path.boundingBoxOfPath
      if let stroke { b = b.insetBy(dx: -stroke.width, dy: -stroke.width) }
      r = r.union(b.applying(tt.concatenating(t)))
    case let .group(children, _, tt):
      r = r.union(bounds(of: children, tt.concatenating(t)))
    }
  }
  return r
}

private let space = CGColorSpace(name: CGColorSpace.sRGB)!

private func gradient(_ stops: [Stop]) -> CGGradient {
  CGGradient(
    colorsSpace: space, colors: stops.map { cgColor($0.1, $0.2) } as CFArray,
    locations: stops.map { CGFloat($0.0) })!
}

func draw(_ ops: [Op], in ctx: CGContext) {
  for op in ops {
    switch op {
    case let .shape(path, fill, stroke, opacity, t):
      ctx.saveGState()
      ctx.concatenate(t)
      if opacity < 1 { ctx.setAlpha(opacity) }
      if let fill {
        switch fill {
        case let .solid(hex, a):
          ctx.addPath(path)
          ctx.setFillColor(cgColor(hex, a))
          ctx.fillPath()
        case let .radial(cx, cy, r, stops):
          let bb = path.boundingBoxOfPath
          ctx.saveGState()
          ctx.addPath(path)
          ctx.clip()
          ctx.concatenate(CGAffineTransform(a: bb.width, b: 0, c: 0, d: bb.height, tx: bb.minX, ty: bb.minY))
          let c = CGPoint(x: cx, y: cy)
          ctx.drawRadialGradient(
            gradient(stops), startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
          ctx.restoreGState()
        case let .vertical(stops):
          let bb = path.boundingBoxOfPath
          ctx.saveGState()
          ctx.addPath(path)
          ctx.clip()
          ctx.drawLinearGradient(
            gradient(stops), start: CGPoint(x: bb.midX, y: bb.minY), end: CGPoint(x: bb.midX, y: bb.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
          ctx.restoreGState()
        }
      }
      if let stroke {
        ctx.addPath(path)
        ctx.setStrokeColor(cgColor(stroke.color, stroke.alpha))
        ctx.setLineWidth(stroke.width)
        ctx.setLineCap(stroke.cap)
        ctx.setLineJoin(stroke.join)
        if let dash = stroke.dash { ctx.setLineDash(phase: 0, lengths: dash) }
        ctx.strokePath()
      }
      ctx.restoreGState()
    case let .group(children, opacity, t):
      ctx.saveGState()
      ctx.concatenate(t)
      if opacity < 1 {
        ctx.setAlpha(opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(children, in: ctx)
        ctx.endTransparencyLayer()
      } else {
        draw(children, in: ctx)
      }
      ctx.restoreGState()
    }
  }
}

/// A rendered drawing and where its local origin sits inside it.
struct Sprite {
  var image: CGImage
  /// The drawing's bounds in its own units, including padding.
  var rect: CGRect
  /// The local origin (0,0) as a unit-space anchor point for a CALayer.
  var anchor: CGPoint { CGPoint(x: -rect.minX / rect.width, y: -rect.minY / rect.height) }
}

/// Renders ops at `pixelsPerUnit`. By default the bitmap is stored upside down,
/// because the scene's world layer flips y to match SVG's y-down coordinates.
/// Pass `upright: true` for images shown outside the world (the field guide).
func render(_ ops: [Op], pixelsPerUnit: Double, upright: Bool = false) -> Sprite? {
  let b = bounds(of: ops)
  if b.isNull || b.isEmpty { return nil }
  let pad = 2 / pixelsPerUnit
  let rect = b.insetBy(dx: -pad, dy: -pad)
  let w = max(1, Int((rect.width * pixelsPerUnit).rounded(.up)))
  let h = max(1, Int((rect.height * pixelsPerUnit).rounded(.up)))
  guard w * h < 40_000_000,
    let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return nil }
  if upright {
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
  }
  ctx.scaleBy(x: pixelsPerUnit, y: pixelsPerUnit)
  ctx.translateBy(x: -rect.minX, y: -rect.minY)
  draw(ops, in: ctx)
  guard let image = ctx.makeImage() else { return nil }
  return Sprite(image: image, rect: CGRect(x: rect.minX, y: rect.minY, width: Double(w) / pixelsPerUnit, height: Double(h) / pixelsPerUnit))
}
