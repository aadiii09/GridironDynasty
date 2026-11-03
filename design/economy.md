# Economy and packs (draft)

## Currencies

| Currency | How you get it | Can buy with Robux? |
|---|---|---|
| **Coins** | Win vs AI: 400, loss: 150, daily login: 200, quick-selling cards | **No** (on purpose) |
| **Robux** | Real money, spent directly on premium packs (Developer Products) | n/a |

Coins are never sold for Robux. That keeps Coin packs from counting as paid random items, so they don't need the PolicyService block. Only Robux packs do.

## Card tiers (by OVR)

| Tier | OVR | Quick-sell (Coins) |
|---|---|---|
| Common | 58-69 | 25 |
| Rare | 70-79 | 75 |
| Epic | 80-86 | 250 |
| Elite | 87-91 | 1,000 |
| Icon | 92-99 | 3,000 |

## Card programs (fixed ratings)

Every card's rating is locked when the card is released. Real performance shows up as **new** cards, not as changes to old ones:

- **Base**: every rostered player, rated from 2026 season stats at launch.
- **Week Standout**: released each Tuesday for the week's top 8 offensive and top 6 defensive performers (+2 to +5 OVR over Base, up to 99).
- **Breakout / All-Pro** (later): mid-season and end-of-season programs.

## Packs

| Pack | Price | Cards | Guarantee | Common | Rare | Epic | Elite | Icon |
|---|---|---|---|---|---|---|---|---|
| Daily Free | Free, every 22h | 3 | none | 80% | 17% | 2.7% | 0.3% | 0% |
| Starter | 2,500 Coins | 5 | none | 70% | 24% | 5% | 0.9% | 0.1% |
| Pro | 49 R$ | 5 | 1 Rare+ | 60% | 30% | 8% | 1.7% | 0.3% |
| Elite | 149 R$ | 8 | 1 Epic+ | 45% | 37% | 14% | 3.5% | 0.5% |
| Dynasty | 399 R$ | 10 | 1 Elite+ | 30% | 40% | 22% | 6.5% | 1.5% |

Odds shown are per card slot, and each row sums to 100%. The last card of Pro/Elite/Dynasty packs uses the guaranteed-slot table instead:

| Pack | Rare | Epic | Elite | Icon |
|---|---|---|---|---|
| Pro (slot 5) | 85% | 12% | 2.5% | 0.5% |
| Elite (slot 8) | - | 80% | 17% | 3% |
| Dynasty (slot 10) | - | - | 85% | 15% |

The pack screen's VIEW ODDS shows both tables plus every card's exact % (tier % divided by the number of cards in that tier), as Roblox requires before any Robux purchase. Source of truth for these numbers: `roblox/ReplicatedStorage/Shared/PackConfig.lua`.

## Robux packs setup

Each Robux pack needs a Developer Product (Creator Hub > your experience > Monetization > Developer Products) with the matching price. Put its ID in `productId` in PackConfig.lua. Until then the pack shows "Coming soon".
