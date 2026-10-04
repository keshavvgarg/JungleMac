# Jungle for macOS

A native macOS version of [Jungle](https://github.com/keshavvgarg/Jungle), the focus timer whose jungle grows only while the timer runs. It grows the same jungle from the same seed as the web version, and uses a small fraction of the CPU.

## Build and run

Needs only the Xcode Command Line Tools (Swift 6), not Xcode.

```bash
./build.sh              # release build into build/Jungle.app
open build/Jungle.app
./build.sh debug        # faster, unoptimized build
```

Drag `build/Jungle.app` into `/Applications` to keep it. Space starts and stops, L hides everything but the jungle, M mutes.

`build.sh` calls `swiftc` directly because SwiftPM is broken in some Command Line Tools releases. It also works around a duplicate `SwiftBridging` module map in those releases. The app icon is drawn by the app itself on the first build.

## Wildlife and rare events

Ground animals arrive with total focus, like the birds: an Indian hare (30 minutes), a peacock that fans its train (2 hours), a pair of spotted deer (4 hours), an elephant and calf walking the far hills (8 hours) and a Bengal tiger (15 hours) that only prowls through in some hours.

Rare events follow the real clock and the jungle's seed: shooting stars on clear nights, an aurora on about one winter night in three, a comet on about one clear night in twelve, migrating flocks on autumn days and butterflies in spring and summer. The field guide lists animals and first sightings.

## Why it is light

- Each plant is drawn once into an image and redrawn only when it visibly changes (fruit, blossom, season colors). Growth just scales the layer.
- All looping motion (sway, clouds, birds, water) is a Core Animation animation capped at 24 fps. The system's render server plays it, so the app process does almost nothing between clock ticks.
- Rain, petals, snow, motes and fireflies are `CAEmitterLayer` particles, also simulated by the render server.
- Stop pauses every animation in place, and muting stops the audio engine entirely.

With the same 20-hour jungle and the timer running in a 1280×760 window on an M2, the web version used about 155% CPU in Chrome and this app about 5%.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/Model` | Line-for-line ports of `world.ts`, `seasons.ts`, `atmosphere.ts`, `birds.ts` and the focus clock |
| `Sources/Art` | SVG path parser, renderer, and the plant and bird drawings from `Plant.tsx` and `Bird.tsx` |
| `Sources/Scene` | The Core Animation layer tree (`JungleScene`) and weather emitters |
| `Sources/UI` | SwiftUI window, panel, field guide and sound mixer |
| `Sources/Audio` | AVAudioEngine port of the ambience: wind, rain, birdsong, thunder |

Progress is saved in the app's user defaults under the same `jungle.v1` format as the web version's `localStorage`.

## Launch arguments

Pass them after `--args`, for example `open build/Jungle.app --args -speed 60`.

| Argument | Effect |
| --- | --- |
| `-speed 60` | Grows at 60× speed. Preview time is saved like real focus time |
| `-hour 18.5` | Fixes the time of day |
| `-autostart YES` | Starts the timer on launch |

Running the binary with `-snapshot out.png -focus 72000 -seed 12345` renders the scene to a PNG without opening a window. That is handy for checking artwork; particles and animations do not appear in it.
