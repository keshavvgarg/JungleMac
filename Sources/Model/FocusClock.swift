import Foundation
import QuartzCore

private let STORAGE_KEY = "jungle.v1"

struct Saved: Codable, Equatable {
  var seed: Int
  var focus: Double
  var sessions: Int
}

private func newSeed() -> Int { Int.random(in: 0..<(1 << 31)) }

private func load() -> Saved {
  if let json = UserDefaults.standard.string(forKey: STORAGE_KEY),
    let s = try? JSONDecoder().decode(Saved.self, from: Data(json.utf8))
  {
    return s
  }
  return Saved(seed: newSeed(), focus: 0, sessions: 0)
}

/// Launch arguments for previews, like the web version's URL parameters:
/// `-speed 60` grows at 60x, `-hour 18.5` fixes the time of day.
enum Preview {
  static let speed: Double = max(1, UserDefaults.standard.double(forKey: "speed"))
  static let hour: Double? =
    UserDefaults.standard.object(forKey: "hour") != nil ? UserDefaults.standard.double(forKey: "hour") : nil
}

/// Accumulates focused time from a monotonic clock, so a slow timer never loses
/// time. Time while the Mac sleeps is not counted.
@MainActor
final class FocusClock: ObservableObject {
  @Published private(set) var saved: Saved {
    didSet { persist() }
  }
  @Published private(set) var running = false
  @Published private(set) var session: Double = 0

  private var run: (startedAt: Double, base: Double)?
  private var timer: Timer?
  let speed = Preview.speed

  var focus: Double { saved.focus }
  var seed: Int { saved.seed }

  init() {
    saved = load()
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(saved) {
      UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: STORAGE_KEY)
    }
  }

  private func elapsed() -> Double {
    guard let run else { return 0 }
    return (CACurrentMediaTime() - run.startedAt) * speed
  }

  private func tick() {
    guard let run else { return }
    let e = elapsed()
    session = e
    saved.focus = run.base + e
  }

  func start() {
    if run != nil { return }
    run = (CACurrentMediaTime(), saved.focus)
    session = 0
    running = true
    let t = Timer(timeInterval: speed > 1 ? 0.25 : 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    t.tolerance = 0.1
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  func stop() {
    guard let run else { return }
    let e = elapsed()
    self.run = nil
    timer?.invalidate()
    timer = nil
    session = e
    saved = Saved(seed: saved.seed, focus: run.base + e, sessions: saved.sessions + (e >= 60 ? 1 : 0))
    running = false
  }

  func toggle() { running ? stop() : start() }

  func reset() {
    run = nil
    timer?.invalidate()
    timer = nil
    running = false
    session = 0
    saved = Saved(seed: newSeed(), focus: 0, sessions: 0)
  }
}
