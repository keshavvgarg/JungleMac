import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct JungleApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    WindowGroup("Jungle") {
      ContentView()
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1280, height: 760)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}

@main
enum Entry {
  static func main() {
    let args = UserDefaults.standard
    if let path = args.string(forKey: "snapshot") {
      MainActor.assumeIsolated { snapshot(to: path) }
      return
    }
    if let path = args.string(forKey: "icon") {
      MainActor.assumeIsolated { icon(to: path) }
      return
    }
    JungleApp.main()
  }
}

private func writePNG(_ image: CGImage, _ path: String) {
  let url = URL(fileURLWithPath: path) as CFURL
  guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return }
  CGImageDestinationAddImage(dest, image, nil)
  CGImageDestinationFinalize(dest)
}

/// Renders the scene without a window, for checking the artwork:
/// `Jungle -snapshot out.png -focus 72000 -hour 12 -seed 12345 -width 1600 -height 900`.
/// Particles and live animations do not appear in a snapshot.
@MainActor
private func snapshot(to path: String) {
  let d = UserDefaults.standard
  let width = d.double(forKey: "width") > 0 ? d.double(forKey: "width") : 1600
  let height = d.double(forKey: "height") > 0 ? d.double(forKey: "height") : 900
  let focus = d.double(forKey: "focus")
  let seed = d.object(forKey: "seed") != nil ? d.integer(forKey: "seed") : 12345
  let scene = JungleScene()
  scene.layout(size: CGSize(width: width, height: height), backingScale: 1)
  let season = seasonAt(focus)
  let now = Date()
  let day = dayAt(now, forcedHour: Preview.hour ?? 12)
  scene.update(
    SceneInput(
      seed: seed, focus: focus, season: season, day: day, weather: weatherAt(now, season.weights, day),
      regions: regionsAt(focus), running: true))
  guard
    let ctx = CGContext(
      data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return }
  scene.root.render(in: ctx)
  if let image = ctx.makeImage() { writePNG(image, path) }
}

/// Draws the app icon: a fruiting round tree on a dawn-coloured tile.
@MainActor
private func icon(to path: String) {
  let size = 1024
  guard
    let ctx = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return }
  let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
  ctx.addPath(tile)
  ctx.clip()
  let sky = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [cgColor("#f6e3c4"), cgColor("#e8dcc8"), cgColor("#b9c9d6")] as CFArray, locations: [0, 0.45, 1])!
  ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
  ctx.setFillColor(cgColor("#6f9281"))
  ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 250))
  ctx.setFillColor(cgColor("#4f7a4f"))
  ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 170))
  // Draw the tree y-down, standing on the ground band.
  var tree = makePlant(1, 0)
  tree.form = 0
  tree.fruitKind = 0
  let state = PlantState(growth: 1, opacity: 1, bloom: 0, fruitSize: 1, ripeness: 1, vine: 0, sakura: 0, foliage: 1)
  let pal = seasonAt(1800).palette
  ctx.translateBy(x: 512, y: 250)
  ctx.scaleBy(x: 2.45, y: -2.45)
  draw(shadowOps(.roundTree) + plantOps(tree, state, pal), in: ctx)
  if let image = ctx.makeImage() { writePNG(image, path) }
}
