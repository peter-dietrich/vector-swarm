# Vector Swarm

## Maintainer documentation (2026 audit)

- [Architecture and development](docs/DEVELOPMENT.md) — source and local workflow.
- [Build/QA checklist](docs/QA_CHECKLIST.md) — repeatable checks and CI limits.
- [Release and signing](docs/RELEASE.md) — official assets, Apple notarization and Fun City installation.
- [Licensing and provenance](docs/LICENSING.md) — MIT scope, third-party rights and clearance tasks.
- [Third-party notices](THIRD_PARTY_NOTICES.md) — observed stack, inventory and review status.


**Vector Swarm** is an original, Galaga-style fixed-screen formation shooter for the **Fun City** macOS arcade, with neon vector **Classic** and glowing **Modern** display modes.

## Gameplay
- Ten-column enemy formations, four rows, with oscillating flight patterns and dive attacks
- Three enemy classes, escalating waves, aimed projectiles and collision effects
- Three lives, score and persistent high score
- Ace capture beams and a wingman-rescue bonus that enables dual fire
- Rookie / Pilot / Ace difficulty
- New Game, Pause, Save, Load, sound toggle and display switching

## Controls
| Key | Action |
|---|---|
| Left/Right or A/D | Move ship |
| Space | Fire (hold for repeat) |
| Enter | Start or restart |
| P | Pause/resume |

## Run
Open `VectorSwarm.xcodeproj` in Xcode 16 or later, select the **VectorSwarm** scheme and **My Mac**, and run. Or build:

```sh
xcodebuild -project VectorSwarm.xcodeproj -scheme VectorSwarm -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Requires macOS 13 or later. SwiftUI + SpriteKit, no external dependencies.

Bundle identifier: `io.vectorswarm.game`. In Fun City, use **LOCATE GAME** if macOS cannot find the Xcode-built application automatically.

Save/Load stores a checkpoint (score, lives, wave, rescued wingmen and high score) in local UserDefaults. It restores at the beginning of the saved wave, not the exact projectile positions.

## Development status
A GitHub Actions macOS build on the audited main commit completed successfully (2026-11-09). Manual game-play testing on a Mac is still required. All graphics are drawn programmatically; the game is a tribute to classic formation shooters, not a reproduction of licensed artwork.
