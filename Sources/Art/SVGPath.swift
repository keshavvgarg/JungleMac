import CoreGraphics

/// Parses SVG path data (M L H V Q T C S Z, absolute and relative) so the web
/// version's shapes can be reused verbatim.
func svgPath(_ d: String) -> CGPath {
  let path = CGMutablePath()
  var tokens: [Substring] = []
  var nums: [Double] = []
  do {
    // Split into command letters and numbers ("10-5" is two numbers, ".5.5" too).
    var i = d.startIndex
    while i < d.endIndex {
      let c = d[i]
      if c.isLetter && c != "e" && c != "E" {
        tokens.append(Substring(String(c)))
        i = d.index(after: i)
      } else if c == "-" || c == "+" || c == "." || c.isNumber {
        var j = d.index(after: i)
        var seenDot = c == "."
        while j < d.endIndex {
          let n = d[j]
          if n.isNumber {
            j = d.index(after: j)
          } else if n == "." && !seenDot {
            seenDot = true
            j = d.index(after: j)
          } else if n == "e" || n == "E" {
            j = d.index(after: j)
            if j < d.endIndex && (d[j] == "-" || d[j] == "+") { j = d.index(after: j) }
          } else {
            break
          }
        }
        tokens.append(d[i..<j])
        i = j
      } else {
        i = d.index(after: i)
      }
    }
  }

  var cmd: Character = "M"
  var cur = CGPoint.zero
  var start = CGPoint.zero
  var lastCtrl: CGPoint?
  var lastCmd: Character = "M"
  var k = 0

  func flushNumbers() {
    nums.removeAll(keepingCapacity: true)
  }

  while k < tokens.count {
    let tok = tokens[k]
    if let ch = tok.first, tok.count == 1, ch.isLetter {
      cmd = ch
      k += 1
      if cmd == "Z" || cmd == "z" {
        path.closeSubpath()
        cur = start
        lastCmd = cmd
        lastCtrl = nil
      }
      continue
    }
    let arity: Int
    switch cmd {
    case "M", "m", "L", "l", "T", "t": arity = 2
    case "H", "h", "V", "v": arity = 1
    case "Q", "q", "S", "s": arity = 4
    case "C", "c": arity = 6
    default: arity = 1
    }
    flushNumbers()
    while nums.count < arity && k < tokens.count, let v = Double(tokens[k]) {
      nums.append(v)
      k += 1
    }
    if nums.count < arity { break }
    let rel = cmd.isLowercase
    let ox = rel ? cur.x : 0, oy = rel ? cur.y : 0
    func p(_ i: Int) -> CGPoint { CGPoint(x: ox + nums[i], y: oy + nums[i + 1]) }
    switch cmd {
    case "M", "m":
      cur = p(0)
      start = cur
      path.move(to: cur)
      // Further pairs after a move are implicit line-tos.
      cmd = rel ? "l" : "L"
      lastCtrl = nil
    case "L", "l":
      cur = p(0)
      path.addLine(to: cur)
      lastCtrl = nil
    case "H", "h":
      cur = CGPoint(x: (rel ? cur.x : 0) + nums[0], y: cur.y)
      path.addLine(to: cur)
      lastCtrl = nil
    case "V", "v":
      cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + nums[0])
      path.addLine(to: cur)
      lastCtrl = nil
    case "Q", "q":
      let c1 = p(0)
      cur = p(2)
      path.addQuadCurve(to: cur, control: c1)
      lastCtrl = c1
    case "T", "t":
      let c1 =
        "QqTt".contains(lastCmd) && lastCtrl != nil
        ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
      cur = p(0)
      path.addQuadCurve(to: cur, control: c1)
      lastCtrl = c1
    case "C", "c":
      let c1 = p(0), c2 = p(2)
      cur = p(4)
      path.addCurve(to: cur, control1: c1, control2: c2)
      lastCtrl = c2
    case "S", "s":
      let c1 =
        "CcSs".contains(lastCmd) && lastCtrl != nil
        ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
      let c2 = p(0)
      cur = p(2)
      path.addCurve(to: cur, control1: c1, control2: c2)
      lastCtrl = c2
    default:
      break
    }
    lastCmd = cmd
  }
  return path
}

func circlePath(_ cx: Double, _ cy: Double, _ r: Double) -> CGPath {
  CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}

func ellipsePath(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> CGPath {
  CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}

/// SVG-style transforms, composed left to right like a `transform` attribute.
func translate(_ x: Double, _ y: Double) -> CGAffineTransform { CGAffineTransform(translationX: x, y: y) }
func rotate(_ deg: Double) -> CGAffineTransform { CGAffineTransform(rotationAngle: deg * .pi / 180) }
func scale(_ x: Double, _ y: Double? = nil) -> CGAffineTransform { CGAffineTransform(scaleX: x, y: y ?? x) }
/// `rotate(deg cx cy)`.
func rotate(_ deg: Double, _ cx: Double, _ cy: Double) -> CGAffineTransform {
  translate(cx, cy).then(rotate(deg)).then(translate(-cx, -cy))
}

extension CGAffineTransform {
  /// Applies `inner` inside this transform, like `transform="A B"` in SVG.
  func then(_ inner: CGAffineTransform) -> CGAffineTransform { inner.concatenating(self) }
}

/// `toFixed`-style formatting for building path strings.
func f(_ v: Double) -> String {
  let r = (v * 1000).rounded() / 1000
  return r == r.rounded() ? String(Int(r)) : String(r)
}
