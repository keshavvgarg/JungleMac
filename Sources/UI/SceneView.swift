import AppKit
import SwiftUI

/// Hosts the Core Animation scene in a plain layer-hosting view.
final class SceneNSView: NSView {
  let scene: JungleScene

  init(scene: JungleScene) {
    self.scene = scene
    super.init(frame: .zero)
    layer = CALayer()
    wantsLayer = true
    layer?.addSublayer(scene.root)
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override func layout() {
    super.layout()
    relayout()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    relayout()
  }

  private func relayout() {
    let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    scene.layout(size: bounds.size, backingScale: backing)
  }
}

struct SceneView: NSViewRepresentable {
  let scene: JungleScene

  func makeNSView(context: Context) -> SceneNSView { SceneNSView(scene: scene) }
  func updateNSView(_ view: SceneNSView, context: Context) {}
}
