struct BirdSpecies {
  var id: String
  var name: String
  /// Total focused seconds before this species first visits.
  var unlockAt: Double
  var note: String
  var body, wing, belly: String
  var head: String? = nil
  var beak: String
  var beakLen, beakDepth, tail: Double
  var tailColor: String? = nil
  var crest: String? = nil
  var cheek: String? = nil
  var casque: String? = nil
  var size: Double
}

private let MIN: Double = 60
private let HOUR: Double = 60 * MIN

let BIRDS: [BirdSpecies] = [
  BirdSpecies(
    id: "sparrow", name: "House Sparrow", unlockAt: 5 * MIN,
    note: "The first to notice a new patch of green.",
    body: "#8a6a4a", wing: "#5e4632", belly: "#dccdb4", head: "#7a5c40",
    beak: "#3a3030", beakLen: 0.8, beakDepth: 1, tail: 0.8, size: 0.9),
  BirdSpecies(
    id: "bulbul", name: "Red-whiskered Bulbul", unlockAt: 20 * MIN,
    note: "Arrives with a cheerful song once the bushes fill out.",
    body: "#6b5e52", wing: "#574a40", belly: "#f1ece2", head: "#2a2522",
    beak: "#222222", beakLen: 0.8, beakDepth: 0.6, tail: 1.2, crest: "#2a2522", cheek: "#d8322e", size: 0.95),
  BirdSpecies(
    id: "kingfisher", name: "Common Kingfisher", unlockAt: 45 * MIN,
    note: "A flash of blue that waits patiently on a high branch.",
    body: "#1f8fc4", wing: "#17699a", belly: "#e98a3a", head: "#1f8fc4",
    beak: "#222222", beakLen: 1.9, beakDepth: 0.8, tail: 0.5, size: 0.95),
  BirdSpecies(
    id: "sunbird", name: "Purple Sunbird", unlockAt: 90 * MIN,
    note: "Drawn in by the first blossoms of the canopy.",
    body: "#3b2b6b", wing: "#2a2050", belly: "#4a3a80", head: "#3a3a8a",
    beak: "#1a1a1a", beakLen: 2.2, beakDepth: 0.2, tail: 0.9, size: 0.75),
  BirdSpecies(
    id: "parakeet", name: "Rose-ringed Parakeet", unlockAt: 150 * MIN,
    note: "Loud, green, and fond of ripe fruit.",
    body: "#5fbf4a", wing: "#3f9a38", belly: "#8fd46a", head: "#6ccb52",
    beak: "#c8323a", beakLen: 0.9, beakDepth: 1.6, tail: 2.4, tailColor: "#4aa6a0", size: 1.1),
  BirdSpecies(
    id: "hornbill", name: "Great Hornbill", unlockAt: 4 * HOUR,
    note: "Only settles where the trees have grown old and tall.",
    body: "#222222", wing: "#1a1a1a", belly: "#eee6c8", head: "#f1e7c4",
    beak: "#f1c233", beakLen: 2.4, beakDepth: 1.8, tail: 1.6, tailColor: "#f3efe2", casque: "#e8a92a", size: 1.6),
  BirdSpecies(
    id: "toucan", name: "Toco Toucan", unlockAt: 6 * HOUR,
    note: "A rare guest with a sunset for a beak.",
    body: "#151515", wing: "#111111", belly: "#fff4d6", head: "#151515",
    beak: "#f2872b", beakLen: 2.6, beakDepth: 2.2, tail: 1.1, size: 1.3),
  BirdSpecies(
    id: "flycatcher", name: "Paradise Flycatcher", unlockAt: 9 * HOUR,
    note: "Its ribbon tail drifts like mist through the leaves.",
    body: "#f7f4ee", wing: "#e6e1d8", belly: "#ffffff", head: "#1a1a3a",
    beak: "#3a4a7a", beakLen: 0.9, beakDepth: 0.7, tail: 4, tailColor: "#f7f4ee", crest: "#1a1a3a", size: 0.9),
  BirdSpecies(
    id: "macaw", name: "Scarlet Macaw", unlockAt: 12 * HOUR,
    note: "Proof that the jungle has become a true rainforest.",
    body: "#d8262e", wing: "#2a5bb8", belly: "#e0352e", head: "#d8262e",
    beak: "#efe5d2", beakLen: 1.1, beakDepth: 2, tail: 3.2, tailColor: "#c9202a", size: 1.5),
  BirdSpecies(
    id: "quetzal", name: "Resplendent Quetzal", unlockAt: 18 * HOUR,
    note: "The jewel of the cloud forest. Few ever see one.",
    body: "#1f9a6a", wing: "#177a55", belly: "#c8202e", head: "#26a877",
    beak: "#e6c34a", beakLen: 0.7, beakDepth: 0.8, tail: 4.5, tailColor: "#1f9a6a", crest: "#26a877", size: 1.1),
]
