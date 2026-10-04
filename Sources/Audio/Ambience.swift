import AVFoundation

struct Mix: Codable, Equatable {
  var muted = false
  var master = 0.65
  var wind = 0.55
  var birds = 0.45
  var rain = 0.7
  var thunder = 0.4
}

struct AmbienceLevels: Equatable {
  var wind = 0.3
  var birds = 0.0
  var rain = 0.0
  var thunder = 0.0
}

private let AUDIO_KEY = "jungle.audio"

func loadMix() -> Mix {
  guard let json = UserDefaults.standard.string(forKey: AUDIO_KEY),
    let mix = try? JSONDecoder().decode(Mix.self, from: Data(json.utf8))
  else { return Mix() }
  return mix
}

func saveMix(_ mix: Mix) {
  if let data = try? JSONEncoder().encode(mix) {
    UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: AUDIO_KEY)
  }
}

/// Soft looping wind and rain, occasional birds and distant thunder, all
/// synthesized. The engine only runs while sound is on, so muting costs nothing.
@MainActor
final class Ambience {
  private let engine = AVAudioEngine()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
  private let master = AVAudioMixerNode()
  private let wind = AVAudioMixerNode()
  private let rain = AVAudioMixerNode()
  private let birds = AVAudioMixerNode()
  private let thunder = AVAudioMixerNode()
  private let windPlayer = AVAudioPlayerNode()
  private let rainPlayer = AVAudioPlayerNode()
  private let birdsPlayer = AVAudioPlayerNode()
  private let thunderPlayer = AVAudioPlayerNode()
  private var built = false
  private var armed = false
  private var mix = Mix()
  private var levels = AmbienceLevels()
  private var tickTimer: Timer?
  private var rampTimer: Timer?

  /// Starts sound after a user action, like the web version.
  func resume() {
    armed = true
    apply()
  }

  func setMix(_ mix: Mix) {
    self.mix = mix
    apply()
  }

  func setLevels(_ levels: AmbienceLevels) {
    self.levels = levels
    apply()
  }

  private func build() {
    built = true
    for n in [master, wind, rain, birds, thunder, windPlayer, rainPlayer, birdsPlayer, thunderPlayer] { engine.attach(n) }
    let windFilter = filter(.lowPass, 420)
    let rainFilter = filter(.highPass, 1400)
    engine.connect(windPlayer, to: windFilter, format: format)
    engine.connect(windFilter, to: wind, format: format)
    engine.connect(rainPlayer, to: rainFilter, format: format)
    engine.connect(rainFilter, to: rain, format: format)
    engine.connect(birdsPlayer, to: birds, format: format)
    engine.connect(thunderPlayer, to: thunder, format: format)
    for n in [wind, rain, birds, thunder] {
      n.outputVolume = 0
      engine.connect(n, to: master, format: format)
    }
    master.outputVolume = 0
    engine.connect(master, to: engine.mainMixerNode, format: format)
    windPlayer.scheduleBuffer(noise(seconds: 3, brown: true), at: nil, options: .loops)
    rainPlayer.scheduleBuffer(noise(seconds: 2, brown: false), at: nil, options: .loops)
  }

  private func filter(_ type: AVAudioUnitEQFilterType, _ hz: Float) -> AVAudioUnitEQ {
    let eq = AVAudioUnitEQ(numberOfBands: 1)
    eq.bands[0].filterType = type
    eq.bands[0].frequency = hz
    eq.bands[0].bypass = false
    engine.attach(eq)
    return eq
  }

  private func apply() {
    guard armed else { return }
    if mix.muted {
      ramp { [weak self] in
        guard let self else { return }
        self.engine.pause()
        self.tickTimer?.invalidate()
        self.tickTimer = nil
      }
      return
    }
    if !built { build() }
    if !engine.isRunning {
      do { try engine.start() } catch { return }
      for p in [windPlayer, rainPlayer, birdsPlayer, thunderPlayer] { p.play() }
    }
    if tickTimer == nil {
      let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
      t.tolerance = 1
      RunLoop.main.add(t, forMode: .common)
      tickTimer = t
    }
    ramp(nil)
  }

  /// Fades each channel to its target over 0.6s, then runs `done`.
  private func ramp(_ done: (() -> Void)?) {
    rampTimer?.invalidate()
    let on = !mix.muted
    let targets: [(AVAudioMixerNode, Float)] = [
      (master, on ? Float(mix.master) : 0),
      (wind, Float(levels.wind * mix.wind * 0.28)),
      (rain, Float(levels.rain * mix.rain * 0.22)),
      (birds, Float(levels.birds * mix.birds)),
      (thunder, Float(levels.thunder * mix.thunder)),
    ]
    let starts = targets.map { $0.0.outputVolume }
    var step = 0
    let steps = 12
    let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
      MainActor.assumeIsolated {
        step += 1
        let k = Float(step) / Float(steps)
        for (i, (node, target)) in targets.enumerated() { node.outputVolume = starts[i] + (target - starts[i]) * k }
        if step >= steps {
          timer.invalidate()
          self?.rampTimer = nil
          done?()
        }
      }
    }
    RunLoop.main.add(t, forMode: .common)
    rampTimer = t
  }

  private func tick() {
    guard engine.isRunning, !mix.muted else { return }
    let b = levels.birds * mix.birds
    if b > 0.08 && Double.random(in: 0..<1) < 0.55 * min(1, b) { birdsPlayer.scheduleBuffer(chirp(), at: nil) }
    let th = levels.thunder * mix.thunder
    if th > 0.25 && Double.random(in: 0..<1) < 0.08 * th { thunderPlayer.scheduleBuffer(rumble(), at: nil) }
  }

  // MARK: - Synthesis

  private func buffer(seconds: Double, _ fill: (UnsafeMutablePointer<Float>, Int, Double) -> Void) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(format.sampleRate * seconds)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buf.frameLength = frames
    fill(buf.floatChannelData![0], Int(frames), format.sampleRate)
    return buf
  }

  private func noise(seconds: Double, brown: Bool) -> AVAudioPCMBuffer {
    buffer(seconds: seconds) { data, n, _ in
      var last: Float = 0
      for i in 0..<n {
        let white = Float.random(in: -1...1)
        if brown {
          last = (last + 0.02 * white) / 1.02
          data[i] = last * 3.2
        } else {
          data[i] = white * 0.6
        }
      }
    }
  }

  /// One or two quick falling whistles.
  private func chirp() -> AVAudioPCMBuffer {
    let notes = Double.random(in: 0..<1) < 0.45 ? 2 : 1
    let specs = (0..<notes).map { i in
      (start: Double(i) * 0.16, f0: 900 + Double.random(in: 0..<1400), f1: 500 + Double.random(in: 0..<400), peak: 0.05 + Double.random(in: 0..<0.03))
    }
    return buffer(seconds: 0.4) { data, n, rate in
      for i in 0..<n { data[i] = 0 }
      for s in specs {
        var phase = 0.0
        let begin = Int(s.start * rate)
        for j in 0..<Int(0.2 * rate) where begin + j < n {
          let t = Double(j) / rate
          let f = s.f0 * pow(s.f1 / s.f0, min(1, t / 0.14))
          phase += 2 * .pi * f / rate
          let env = t < 0.02 ? 0.0001 * pow(s.peak / 0.0001, t / 0.02) : s.peak * pow(0.0001 / s.peak, min(1, (t - 0.02) / 0.16))
          data[begin + j] += Float(sin(phase) * env)
        }
      }
    }
  }

  /// A distant low roll of thunder.
  private func rumble() -> AVAudioPCMBuffer {
    let f0 = 48 + Double.random(in: 0..<24)
    return buffer(seconds: 3) { data, n, rate in
      var phase = 0.0
      for i in 0..<n {
        let t = Double(i) / rate
        let f = f0 * pow(28 / f0, min(1, t / 2.6))
        phase += 2 * .pi * f / rate
        let env = t < 0.12 ? 0.0001 * pow(0.22 / 0.0001, t / 0.12) : 0.22 * pow(0.0001 / 0.22, min(1, (t - 0.12) / 2.68))
        data[i] = Float(sin(phase) * env)
      }
    }
  }
}
