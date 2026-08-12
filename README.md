# AppFactoryWorker — instalačky

Tenhle repozitář slouží **jen k distribuci instalaček** aplikace AppFactoryWorker.
Zdrojový kód je v privátním repu `janindra/appfactoryworker`.

## Stažení

Nejnovější verze je vždy v [Releases](../../releases/latest):

- **macOS (Apple Silicon)** — `AppFactoryWorker-<verze>-arm64.dmg`
- **Windows** — `AppFactoryWorker-Setup-<verze>.exe`

Aplikace si od verze 1.0.2 hlídá nové verze sama a nabídne aktualizaci tlačítkem přímo v okně.

## Jak sem věci přibývají

Automaticky: tag `v*` v privátním repu spustí workflow `build-installers`,
který sem přes electron-builder publikuje release i s instalačkami.
