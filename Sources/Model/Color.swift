import CoreGraphics

/// Colors stay as hex strings, like the web version, so palettes and blends port verbatim.
private func parse(_ hex: String) -> (Double, Double, Double, Double) {
  var s = Substring(hex)
  if s.hasPrefix("#") { s = s.dropFirst() }
  let n = UInt64(s, radix: 16) ?? 0
  if s.count == 8 {
    return (Double((n >> 24) & 255), Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255) / 255)
  }
  return (Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255), 1)
}

private func hex2(_ v: Double) -> String {
  let s = String(Int(v.rounded()), radix: 16)
  return s.count == 1 ? "0" + s : s
}

/// Mirrors `mix` in seasons.ts, including its rounding, so blended palettes match.
func mix(_ a: String, _ b: String, _ t: Double) -> String {
  let A = parse(a)
  let B = parse(b)
  return "#" + hex2(A.0 + (B.0 - A.0) * t) + hex2(A.1 + (B.1 - A.1) * t) + hex2(A.2 + (B.2 - A.2) * t)
}

/// Positive amounts lighten towards white, negative darken towards black.
func shade(_ color: String, _ amount: Double) -> String {
  amount >= 0 ? mix(color, "#ffffff", amount) : mix(color, "#000000", -amount)
}

func cgColor(_ hex: String, _ alpha: Double = 1) -> CGColor {
  let c = parse(hex)
  return CGColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3 * alpha)
}

func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> CGColor {
  CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
