import AppKit
import SwiftUI

private let ink = Color(red: 0x26 / 255, green: 0x34 / 255, blue: 0x2c / 255)
private let forest = Color(red: 0x2f / 255, green: 0x5b / 255, blue: 0x3c / 255)
private let cream = Color(red: 0xf6 / 255, green: 0xf1 / 255, blue: 0xe4 / 255)
private let serif = "Iowan Old Style"

private func fmtClock(_ sec: Double) -> String {
  let s = Int(sec)
  let h = s / 3600, m = (s % 3600) / 60, ss = s % 60
  return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%02d:%02d", m, ss)
}

private func fmtDuration(_ sec: Double) -> String {
  let s = max(0, Int(sec.rounded(.up)))
  if s < 60 { return "\(s)s" }
  let m = s / 60
  if m < 60 { return "\(m)m" }
  let rest = m % 60
  return rest > 0 ? "\(m / 60)h \(rest)m" : "\(m / 60)h"
}

private struct Toast: Identifiable, Equatable {
  let id: Int
  let text: String
}

/// Owns the scene and the sound engine for the lifetime of the window.
@MainActor
final class Stage: ObservableObject {
  let scene = JungleScene()
  let ambience = Ambience()
}

struct ContentView: View {
  @StateObject private var clock = FocusClock()
  @StateObject private var stage = Stage()
  @State private var now = Date()
  @State private var guideOpen = false
  @State private var confirmReset = false
  @AppStorage("jungle.locked") private var locked = false
  @State private var toasts: [Toast] = []
  @State private var toastId = 0
  @State private var prevFocus: Double?
  @State private var soundOpen = false
  @State private var mix = loadMix()
  @State private var keyMonitor: Any?
  @State private var lastEvents: WorldEvents?
  @State private var sightings = loadSightings()

  private let dayTimer = Timer.publish(every: 20, tolerance: 2, on: .main, in: .common).autoconnect()

  var body: some View {
    let focus = clock.focus
    let season = seasonAt(focus)
    let day = dayAt(now, forcedHour: Preview.hour)
    let weather = weatherAt(now, season.weights, day)
    let count = plantCount(focus)
    let found = BIRDS.filter { $0.unlockAt <= focus }.count
    let nextBird = BIRDS.first { $0.unlockAt > focus }
    let skyName = season.weights[MONSOON] > 0.55 ? "Rain" : weather.name
    let state =
      clock.running ? "Growing while you focus" : focus == 0 ? "Press start to plant your jungle" : "Paused. The jungle is waiting for you"

    ZStack {
      SceneView(scene: stage.scene).ignoresSafeArea()

      VStack(spacing: 0) {
        header
        Spacer()
        panel(season: season, count: count, focus: focus, found: found, nextBird: nextBird, hint: "\(state) · \(day.name) · \(skyName)")
      }
      .opacity(locked ? 0 : 1)
      .allowsHitTesting(!locked)

      VStack(spacing: 8) {
        ForEach(toasts) { t in
          Text(t.text)
            .font(.system(size: 14))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glass(Capsule())
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        Spacer()
      }
      .padding(.top, 24)
      .opacity(locked ? 0 : 1)
      .allowsHitTesting(false)

      VStack {
        Spacer()
        HStack(alignment: .bottom, spacing: 8) {
          Spacer()
          soundDock
          RoundButton(symbol: locked ? "lock" : "lock.open", dim: locked, help: locked ? "Show controls (L)" : "Hide everything but the jungle (L)") {
            withAnimation(.easeInOut(duration: 0.6)) { locked.toggle() }
          }
        }
      }
      .padding(22)

      if guideOpen { guide(focus: focus) }
    }
    .foregroundStyle(ink)
    .animation(.easeInOut(duration: 0.6), value: locked)
    .frame(minWidth: 640, minHeight: 440)
    .onAppear {
      pushScene()
      installKeys()
      if UserDefaults.standard.bool(forKey: "autostart") { start() }
    }
    .onDisappear { keyMonitor.map(NSEvent.removeMonitor) }
    .onReceive(dayTimer) { now = $0 }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
      // Count the running session before the app goes away.
      clock.stop()
    }
    .onChange(of: clock.saved) { pushScene() }
    .onChange(of: clock.running) { pushScene() }
    .onChange(of: now) { pushScene() }
    .onChange(of: focus) { old, new in announce(from: old, to: new) }
    .onChange(of: mix) {
      saveMix(mix)
      stage.ambience.setMix(mix)
    }
    .onChange(of: locked) { if locked { guideOpen = false; soundOpen = false } }
    .alert("Clear this jungle and start a new one from a single seed?", isPresented: $confirmReset) {
      Button("New jungle", role: .destructive) { clock.reset() }
      Button("Cancel", role: .cancel) {}
    }
  }

  // MARK: - Scene and sound

  private func pushScene() {
    let season = seasonAt(clock.focus)
    let day = dayAt(now, forcedHour: Preview.hour)
    let weather = weatherAt(now, season.weights, day)
    let events = eventsAt(now, seed: clock.seed, focus: clock.focus, weights: season.weights, day: day)
    stage.scene.update(
      SceneInput(
        seed: clock.seed, focus: clock.focus, season: season, day: day, weather: weather,
        regions: regionsAt(clock.focus), events: events, running: clock.running))
    noteEvents(events)
    stage.ambience.setLevels(
      AmbienceLevels(
        wind: min(1, 0.2 + weather.sway * 0.4),
        birds: day.day * 0.85 + day.dawn * 0.4 + day.dusk * 0.3,
        rain: season.weights[MONSOON] * 0.95 + weather.drizzle * 0.5,
        thunder: max(0, season.weights[MONSOON] - 0.2)))
  }

  private func start() {
    stage.ambience.setMix(mix)
    stage.ambience.resume()
    clock.start()
  }

  private func toggleRunning() { clock.running ? clock.stop() : start() }

  private func installKeys() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
      if !e.modifierFlags.intersection([.command, .control, .option]).isEmpty { return e }
      switch e.charactersIgnoringModifiers?.lowercased() {
      case " ":
        if guideOpen { return e }
        toggleRunning()
        return nil
      case "l":
        withAnimation(.easeInOut(duration: 0.6)) { locked.toggle() }
        return nil
      case "m":
        stage.ambience.resume()
        mix.muted.toggle()
        return nil
      default:
        return e
      }
    }
  }

  private func announce(from a: Double, to b: Double) {
    guard b > a else { return }
    var msgs: [String] = []
    for sp in BIRDS where sp.unlockAt > a && sp.unlockAt <= b { msgs.append("A \(sp.name) has found your jungle") }
    for sp in ANIMALS where sp.unlockAt > a && sp.unlockAt <= b { msgs.append("\(article(sp.name)) \(sp.name) has found your jungle") }
    for r in REGION_MILESTONES where r.at > a && r.at <= b { msgs.append(r.text) }
    if Int(a / SEASON_SECONDS) != Int(b / SEASON_SECONDS) { msgs.append("\(seasonAt(b).name) has arrived") }
    if a < FIRST_FRUIT_AT && b >= FIRST_FRUIT_AT { msgs.append("Your first fruit has ripened") }
    toast(msgs)
  }

  /// Toasts rare events as they begin, and remembers first sightings for the field guide.
  private func noteEvents(_ e: WorldEvents) {
    let was = lastEvents ?? WorldEvents()
    lastEvents = e
    var msgs: [String] = []
    if e.aurora && !was.aurora { msgs.append("The aurora is dancing over the hills") }
    if e.comet && !was.comet { msgs.append("A comet is crossing the sky tonight") }
    if e.tiger && !was.tiger { msgs.append("A tiger is prowling through your jungle") }
    for id in e.sightingIds where sightings[id] == nil {
      sightings[id] = now.timeIntervalSince1970
      if id == "shootingStar" { msgs.append("Your first shooting stars are falling") }
    }
    if msgs.isEmpty { return }
    saveSightings(sightings)
    toast(msgs)
  }

  private func toast(_ msgs: [String]) {
    guard !msgs.isEmpty else { return }
    let added = msgs.map { text -> Toast in
      toastId += 1
      return Toast(id: toastId, text: text)
    }
    withAnimation(.easeOut(duration: 0.6)) { toasts += added }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
      withAnimation(.easeOut(duration: 0.6)) { toasts.removeAll { added.contains($0) } }
    }
  }

  // MARK: - Header and panel

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Jungle").font(.custom(serif, size: 34).italic()).foregroundStyle(Color(red: 0x2b / 255, green: 0x3b / 255, blue: 0x31 / 255))
        Text("grows only while you focus").font(.system(size: 13)).opacity(0.7)
      }
      Spacer()
      HStack(spacing: 8) {
        if clock.speed > 1 {
          Text("Preview ×\(Int(clock.speed))").font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6).glass(Capsule())
        }
        GhostButton(title: "Field guide") { guideOpen = true }
        GhostButton(title: "New jungle") { confirmReset = true }
      }
    }
    .padding(.horizontal, 28)
    .padding(.top, 34)
  }

  private func panel(season: SeasonState, count: Int, focus: Double, found: Int, nextBird: BirdSpecies?, hint: String) -> some View {
    let fruiting = fruitingCount(seed: clock.seed, count: count, focus: focus, weights: season.weights)
    return VStack(spacing: 0) {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(fmtClock(clock.session)).font(.custom(serif, size: 50).monospacedDigit()).foregroundStyle(Color(red: 0x22 / 255, green: 0x31 / 255, blue: 0x2a / 255))
          Text(hint).font(.system(size: 12.5)).opacity(0.72).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        Button(action: toggleRunning) {
          Text(clock.running ? "STOP" : "START")
            .font(.system(size: 16, weight: .semibold))
            .tracking(1.5)
            .frame(minWidth: 92)
            .padding(.horizontal, 34)
            .padding(.vertical, 12)
            .foregroundStyle(clock.running ? forest : cream)
            .background(Capsule().fill(clock.running ? Color(white: 1, opacity: 0.7) : forest))
            .overlay(Capsule().strokeBorder(forest, lineWidth: clock.running ? 1.5 : 0))
            .shadow(color: forest.opacity(clock.running ? 0 : 0.35), radius: 9, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
      Divider().overlay(ink.opacity(0.12)).padding(.top, 12)
      HStack(alignment: .top, spacing: 12) {
        stat("Season", "\(season.name) · Year \(season.year)") {
          GeometryReader { g in
            ZStack(alignment: .leading) {
              Capsule().fill(ink.opacity(0.12))
              Capsule().fill(forest).frame(width: g.size.width * season.progress)
            }
          }
          .frame(height: 3)
          .padding(.top, 6)
        }
        stat("Total focus", fmtDuration(focus)) { EmptyView() }
        stat("Jungle", "\(count) plants · \(fruiting) fruiting") { EmptyView() }
        Button { guideOpen = true } label: {
          stat("Birds", "\(found)/\(BIRDS.count)", muted: nextBird.map { " · next in \(fmtDuration($0.unlockAt - focus))" }) { EmptyView() }
        }
        .buttonStyle(.plain)
      }
      .padding(.top, 10)
    }
    .padding(.horizontal, 22)
    .padding(.top, 16)
    .padding(.bottom, 14)
    .frame(maxWidth: 540)
    .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), fill: 0.32)
    .padding(.horizontal, 16)
    .padding(.bottom, 20)
  }

  private func stat<Extra: View>(_ k: String, _ v: String, muted: String? = nil, @ViewBuilder extra: () -> Extra) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(k.uppercased()).font(.system(size: 10.5)).tracking(1).opacity(0.6)
      (Text(v).font(.system(size: 13, weight: .medium)) + Text(muted ?? "").font(.system(size: 13)).foregroundColor(ink.opacity(0.6)))
        .lineLimit(2)
      extra()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Sound

  private var soundDock: some View {
    RoundButton(symbol: mix.muted ? "speaker.slash" : "speaker.wave.2", dim: mix.muted, help: locked ? "Mute (M)" : "Sound") {
      stage.ambience.resume()
      if locked { mix.muted.toggle() } else { soundOpen.toggle() }
    }
    .popover(isPresented: $soundOpen, arrowEdge: .top) {
      VStack(alignment: .leading, spacing: 8) {
        Button(mix.muted ? "Unmute" : "Mute") { mix.muted.toggle() }
          .buttonStyle(.plain).font(.system(size: 12)).opacity(0.75)
        slider("Master", \.master)
        slider("Wind", \.wind)
        slider("Birds", \.birds)
        slider("Rain", \.rain)
        slider("Thunder", \.thunder)
      }
      .padding(14)
      .frame(width: 220)
      .tint(forest)
    }
  }

  private func slider(_ label: String, _ key: WritableKeyPath<Mix, Double>) -> some View {
    HStack(spacing: 8) {
      Text(label).font(.system(size: 12)).frame(width: 64, alignment: .leading)
      Slider(value: Binding(get: { mix[keyPath: key] }, set: { mix[keyPath: key] = $0 }), in: 0...1)
        .controlSize(.small)
    }
  }

  // MARK: - Field guide

  private func guide(focus: Double) -> some View {
    ZStack {
      Color(red: 38 / 255, green: 52 / 255, blue: 44 / 255).opacity(0.25).ignoresSafeArea()
        .onTapGesture { guideOpen = false }
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Field guide").font(.custom(serif, size: 24).italic())
          Spacer()
          GhostButton(title: "Close") { guideOpen = false }
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Birds")
            ForEach(BIRDS, id: \.id) { b in
              let seen = b.unlockAt <= focus
              HStack(spacing: 12) {
                BirdThumb(species: b, seen: seen).frame(width: 76, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                  Text(seen ? b.name : "Unknown visitor").font(.system(size: 14, weight: .semibold)).opacity(seen ? 1 : 0.55)
                  Text(seen ? b.note : "Arrives after \(fmtDuration(b.unlockAt)) of total focus").font(.system(size: 12.5)).opacity(0.72)
                }
                Spacer(minLength: 0)
              }
              .padding(8)
              .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(seen ? 0.5 : 0)))
            }
            sectionTitle("Animals")
            ForEach(ANIMALS, id: \.id) { a in
              let seen = a.unlockAt <= focus
              guideRow(seen: seen, title: seen ? a.name : "Unknown animal", detail: seen ? a.note : "Arrives after \(fmtDuration(a.unlockAt)) of total focus") {
                AnimalThumb(id: a.id, seen: seen)
              }
            }
            sectionTitle("Sightings")
            ForEach(SIGHTINGS, id: \.id) { s in
              let first = sightings[s.id]
              guideRow(
                seen: first != nil, title: first != nil ? s.name : "Not yet seen",
                detail: first.map { "\(s.note) First seen \(Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted))." } ?? s.hint
              ) {
                Image(systemName: s.symbol).font(.system(size: 20)).opacity(first != nil ? 0.8 : 0.25)
              }
            }
          }
        }
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 20)
      .frame(maxWidth: 520)
      .frame(maxHeight: 600)
      .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), fill: 0.82)
      .padding(16)
    }
    .transition(.opacity)
    .onExitCommand { guideOpen = false }
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased()).font(.system(size: 10.5)).tracking(1).opacity(0.6).padding(.top, 8).padding(.leading, 8)
  }

  private func guideRow<Thumb: View>(seen: Bool, title: String, detail: String, @ViewBuilder thumb: () -> Thumb) -> some View {
    HStack(spacing: 12) {
      thumb().frame(width: 76, height: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 14, weight: .semibold)).opacity(seen ? 1 : 0.55)
        Text(detail).font(.system(size: 12.5)).opacity(0.72)
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(seen ? 0.5 : 0)))
  }
}

/// "An Indian Hare", "A Bengal Tiger".
private func article(_ name: String) -> String {
  "AEIOU".contains(name.prefix(1)) ? "An" : "A"
}

private let SIGHTINGS_KEY = "jungle.sightings"

/// First-seen times of rare sightings, by id.
private func loadSightings() -> [String: Double] {
  UserDefaults.standard.dictionary(forKey: SIGHTINGS_KEY) as? [String: Double] ?? [:]
}

private func saveSightings(_ s: [String: Double]) {
  UserDefaults.standard.set(s, forKey: SIGHTINGS_KEY)
}

/// Plant specs for the fruiting count, cached per seed so each tick only checks state.
@MainActor private var plantCache: (seed: Int, plants: [PlantSpec]) = (-1, [])

@MainActor private func fruitingCount(seed: Int, count: Int, focus: Double, weights: [Double]) -> Int {
  if plantCache.seed != seed { plantCache = (seed, []) }
  while plantCache.plants.count < count {
    plantCache.plants.append(makePlant(seed, plantCache.plants.count, after: plantCache.plants))
  }
  return plantCache.plants.prefix(count).filter { isFruiting($0, focus, weights) }.count
}

private struct AnimalThumb: View {
  let id: String
  let seen: Bool

  var body: some View {
    let art: AnimalArt =
      switch id {
      case "rabbit": hareArt()
      case "peacock": peacockArt()
      case "deer": deerArt(stag: true)
      case "elephant": elephantArt()
      default: tigerArt()
      }
    let ops = art.legs.flatMap(\.ops) + art.body + art.front.flatMap(\.ops)
    if let sprite = render(seen ? ops : silhouette(ops, "#3a4a4155"), pixelsPerUnit: 3, upright: true) {
      Image(decorative: sprite.image, scale: 3).resizable().scaledToFit()
    }
  }
}

/// Every shape in one flat color, for undiscovered entries.
private func silhouette(_ ops: [Op], _ color: String) -> [Op] {
  ops.map { op in
    switch op {
    case let .shape(path, fill, stroke, _, t):
      var s = stroke
      s?.color = color
      s?.alpha = 1
      return .shape(path, fill: fill == nil ? nil : .solid(color), stroke: s, opacity: 1, transform: t)
    case let .group(children, _, t):
      return .group(silhouette(children, color), opacity: 1, transform: t)
    }
  }
}

private struct BirdThumb: View {
  let species: BirdSpecies
  let seen: Bool

  var body: some View {
    if let sprite = render(birdParts(species, mono: seen ? nil : "#3a4a4155").all, pixelsPerUnit: 4, upright: true) {
      Image(decorative: sprite.image, scale: 4).resizable().scaledToFit()
    }
  }
}

// MARK: - Controls

private struct GhostButton: View {
  let title: String
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(red: 1, green: 252 / 255, blue: 244 / 255).opacity(hover ? 0.6 : 0.35)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.5)))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
  }
}

private struct RoundButton: View {
  let symbol: String
  let dim: Bool
  let help: String
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .medium))
        .frame(width: 42, height: 42)
        .glass(Circle(), fill: hover ? 0.7 : 0.42)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .opacity(dim && !hover ? 0.4 : 1)
    .onHover { hover = $0 }
    .help(help)
  }
}

extension View {
  /// The frosted panel look from the web version.
  func glass<S: InsettableShape>(_ shape: S, fill: Double = 0.42) -> some View {
    background(shape.fill(Color(red: 1, green: 252 / 255, blue: 244 / 255).opacity(fill)))
      .background(
        shape.fill(.ultraThinMaterial)
          .shadow(color: Color(red: 38 / 255, green: 52 / 255, blue: 44 / 255).opacity(0.12), radius: 20, y: 10))
      .overlay(shape.strokeBorder(Color.white.opacity(0.55)))
  }
}
