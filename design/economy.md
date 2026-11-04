# Economy and packs (draft)

## Currencies

| Currency | How you get it | Can buy with Robux? |
|---|---|---|
| **Coins** | Win 400 / tie 250 / loss 150 (2x with VIP), daily login 200-500 (streak, 2x with VIP), quick-selling cards | **Yes**: Coin bundles |
| **Robux** | Real money, spent on premium packs, Coin bundles and VIP | n/a |

### Coin bundles (Developer Products)

| Bundle | Price | Coins per R$ |
|---|---|---|
| 3,000 Coins | 39 R$ | 77 |
| 8,000 Coins (POPULAR) | 99 R$ | 81 |
| 20,000 Coins (+30% BONUS) | 199 R$ | 101 |
| 55,000 Coins (BEST VALUE) | 499 R$ | 110 |

### VIP (Game Pass, 199 R$)

2x Coins from every game, 2x daily login reward, gold VIP tag.

### Daily login

200 Coins on day 1, +50 per consecutive day, up to 500 on day 7+ (doubled for VIP). Missing a day resets the streak.

### Paid random items policy

Because Coins can be bought with Robux, the Coin-priced Starter Pack counts as a paid random item, the same as the Robux packs. Every pack shows exact odds before purchase. Players whose PolicyService says `ArePaidRandomItemsRestricted` can't buy Robux packs **or** Coin bundles, so any Coins they have were earned in-game and their Coin packs stay allowed.

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

## Difficulty (vs AI)

| Difficulty | CPU team | Win / Tie / Loss coins |
|---|---|---|
| Rookie | your team OVR - 7 | 300 / 190 / 115 |
| Pro (default) | even | 400 / 250 / 150 |
| All-Pro | +5 | 600 / 375 / 225 |
| Legend | +10 | 900 / 565 / 340 |

VIP doubles all of these. Every win counts toward jerseys and the leaderboards.

## Challenges

- 3 daily challenges (reset 00:00 UTC) worth 150-300 Coins each; claim all 3 for a free Starter Pack.
- 3 weekly challenges (reset Monday 00:00 UTC) worth 1,500-2,500 Coins or a Pro Pack; claim all 3 for a free Elite Pack.
- Everyone gets the same set each day/week (picked from pools in `ChallengeConfig.lua`).
- Match stats only count when a game is finished (quitting forfeits that game's progress).
- Reward packs are not paid random items (nothing is bought), so they're fine under the paid-pack policy.

## Team chemistry

3+ starters from the same team get +1 to OVR and every rating, 5+ get +2, 7+ get +3 (max 99).
It shows on the lineup screen and in the team rating, and applies in games. It gives players a reason to chase specific teams' cards.

## Leaderboards

Most wins this week (resets Monday 00:00 UTC) and all time, top 10, refreshed every 2 minutes.
Shown on the lobby board and in the RANKS panel.
