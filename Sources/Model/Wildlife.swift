import Foundation

/// Ground animals, unlocked by total focus like the birds.
struct AnimalSpecies {
  var id: String
  var name: String
  var unlockAt: Double
  var note: String
}

private let HOUR: Double = 3600

let ANIMALS: [AnimalSpecies] = [
  AnimalSpecies(id: "rabbit", name: "Indian Hare", unlockAt: 0.5 * HOUR, note: "Sits by the meadow and hops off when it feels watched."),
  AnimalSpecies(id: "peacock", name: "Indian Peafowl", unlockAt: 2 * HOUR, note: "Every so often it opens its train in a shimmering fan."),
  AnimalSpecies(id: "deer", name: "Spotted Deer", unlockAt: 4 * HOUR, note: "A stag and a doe, grazing where the grass is longest."),
  AnimalSpecies(id: "elephant", name: "Asian Elephant", unlockAt: 8 * HOUR, note: "A mother and calf walking slowly along the far hills."),
  AnimalSpecies(id: "tiger", name: "Bengal Tiger", unlockAt: 15 * HOUR, note: "Even after it arrives, it only passes through some hours."),
]

/// Rare sights in the sky, listed in the field guide once seen.
struct Sighting {
  var id: String
  var name: String
  var note: String
  var hint: String
  var symbol: String
}

let SIGHTINGS: [Sighting] = [
  Sighting(id: "shootingStar", name: "Shooting stars", note: "Brief streaks across a clear night sky.", hint: "Look up on a clear night", symbol: "sparkles"),
  Sighting(id: "aurora", name: "Aurora", note: "Green and violet curtains over the winter hills.", hint: "Some winter nights", symbol: "water.waves"),
  Sighting(id: "comet", name: "Comet", note: "A long pale tail that lingers for a whole night.", hint: "A rare clear night, after 2 hours of focus", symbol: "moon.stars.fill"),
  Sighting(id: "tiger", name: "Tiger sighting", note: "It was here, if only for a while.", hint: "Unlock the tiger, then keep watching", symbol: "pawprint.fill"),
]

/// What is happening in the jungle right now, beyond the steady weather.
struct WorldEvents: Equatable {
  var shootingStars = false
  var aurora = false
  var comet = false
  var flock = false
  var butterflies = false
  var tiger = false

  /// Sightings currently visible, by `Sighting.id`.
  var sightingIds: [String] {
    [shootingStars ? "shootingStar" : nil, aurora ? "aurora" : nil, comet ? "comet" : nil, tiger ? "tiger" : nil].compactMap { $0 }
  }
}

/// Rare events follow the real clock, so a comet stays all night and a tiger
/// all hour, and each jungle's seed gives it its own lucky nights.
func eventsAt(_ date: Date, seed: Int, focus: Double, weights: [Double], day: DayState) -> WorldEvents {
  let local = date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: date))
  // A night belongs to the evening it starts on.
  let night = Int(((local - 12 * 3600) / 86400).rounded(.down))
  let hour = Int((local / 3600).rounded(.down))
  func roll(_ index: Int, _ salt: Int) -> Double { Rng(seed, index, 700 + salt)() }
  let dark = day.night > 0.5
  let clear = weights[MONSOON] < 0.5
  let daylight = day.day > 0.4
  var e = WorldEvents()
  e.shootingStars = dark && clear
  e.aurora = dark && weights[WINTER] > 0.5 && roll(night, 1) < 0.35
  e.comet = dark && clear && focus >= 2 * HOUR && roll(night, 2) < 0.08
  e.flock = daylight && weights[AUTUMN] > 0.5
  e.butterflies = daylight && weights[SPRING] + weights[SUMMER] > 0.5 && focus >= 5 * 60
  e.tiger = focus >= ANIMALS[4].unlockAt && roll(hour, 3) < 0.3
  return e
}
