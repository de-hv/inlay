# Notice

Inlay is copyright © 2026 David Higuita and is distributed under the MIT license (see [LICENSE](./LICENSE)).

## Inlay derives from

**AeroSpace** — <https://github.com/nikitabobko/AeroSpace>, copyright © 2023 Nikita Bobko, MIT license.
Inlay is a fork of AeroSpace at commit `74a1bf1`. The window manager, the config format, the commands and the
CLI come from it. The original copyright notice is kept in [LICENSE](./LICENSE), as the MIT license requires.
`docs/upstream-aerospace/` is an unmodified copy of the AeroSpace documentation at that commit.

**Aeromenu** — copyright © 2026 David Higuita. The build without Xcode (`swift build`, a hand-made bundle and
`codesign`) and the install scripts follow the ones of Aeromenu, by the same author.

Inlay is not affiliated with, nor endorsed by, the AeroSpace project. Please don't report Inlay bugs there.

## Not derived from

**JankyBorders** (GPL-3.0). Inlay contains no code from JankyBorders.

## Bundled dependencies

| Dependency | Use | License |
|---|---|---|
| [HotKey](https://github.com/soffes/HotKey) | Global keyboard shortcuts | [MIT](./legal/third-party-license/LICENSE-HotKey.txt) |
| [TOMLDecoder](https://github.com/dduan/TOMLDecoder) | TOML parsing | [MIT](./legal/third-party-license/LICENSE-TOMLDecoder.txt) |
| [swift-collections](https://github.com/apple/swift-collections) | Collections | [Apache 2.0](./legal/third-party-license/LICENSE-swift-collections.txt) |
| [ISSoundAdditions](https://github.com/InerziaSoft/ISSoundAdditions) | System volume (`volume` command) | [MIT](./legal/third-party-license/LICENSE-ISSoundAdditions.txt) |

`legal/third-party-license/LICENSE-tomlplusplus.txt` is kept as is from AeroSpace, which ships it among its
third-party licenses.
