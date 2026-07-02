# Gold, Shop & Deck Sculpting — Milestone 5 Design

Status: approved (2026-07-02). Builds on the M4 branching map
(`2026-07-02-branching-map-design.md`) — activates the deferred SHOP node hook and
adds the run economy + deck-sculpting.

## Goal

Give the run an economy and let the player shape their deck. Combat pays **gold**; a new
**SHOP** map node spends it (buy cards, buy relics, pay to remove a card); **Rest** nodes
gain an **upgrade** option (heal *or* improve a card). This is the "deck sculpting" the
roadmap slots after the map assembles its content.

## Scope

**In:** gold currency; SHOP node type + shop screen; card upgrades (one-level, at rest);
card removal (at shop, for gold); relics for sale; a guaranteed shop per act.

**Out (deferred, YAGNI):** potions; escalating removal price; multi-level upgrades (`++`);
boss gold (run ends now); events. Combat rules are untouched.

## Core decisions

- **Upgrades are separate card definitions, not per-instance flags.** Each upgradable card
  gets a `+` `.tres` (better stats, reuse base art) registered in `CARD_CATALOG`. Upgrading a
  deck slot swaps its `CardData` to the `+` one. Because the deck already serializes by id,
  **upgrades need no save-schema change** — an upgraded card is just another cataloged card.
  One-level only (no `++`).
- **Gold is the only new run field.** Save bumps **v4 → v5** (= v4 + `gold: int`).
- **Non-combat nodes commit on entry.** Combat commits on win (M4 model); REST/SHOP have no
  fail state, so they commit the moment the player enters them. Quitting mid-shop/rest means
  the node is spent (self-inflicted; prevents a re-roll exploit).

## Data model

### `CardData` (`cards/card_data.gd`)
Add one field:
```
@export var upgrade_id: StringName    # the card's + version; &"" = not upgradable
```

### Upgraded card definitions
For each upgradable card, author `cards/definitions/<id>_plus.tres`: same id-suffix
convention, improved stats (e.g. Strike 5→8 damage), `upgrade_id = &""` (no `++`),
reusing the base card's `artwork`. Register each in `RunState.CARD_CATALOG`. Author `+`
versions for all current cards so any deck card is upgradable (mechanical content work).
The base card's `upgrade_id` points to its `_plus` id.

### `MapNode.Type` (`systems/map_node.gd`)
Append `SHOP` **after** `BOSS` so existing serialized int values (COMBAT=0…BOSS=3) stay
stable; `SHOP = 4`. SHOP nodes carry empty `enemy_id` (like REST).

### `RunState` (`systems/run_state.gd`)
- `var gold: int = 0`
- `SAVE_VERSION := 5`
- `SHOP_PRICES` constants (see Economy).
- New methods: `add_gold(amount)`, `spend_gold(amount) -> bool` (false if insufficient, no
  deduction), `buy_card(def)`, `buy_relic(def)`, `remove_card(card)`, `upgrade_card(deck_index)`,
  `heal_rest()`, `commit_pending_node()`.

## Node commit model

`begin_node(id)` still just sets the transient `_pending_node_id`. New
`commit_pending_node()` does the guarded `map.enter(_pending_node_id)` + `save_run()` (the
M4 null/`-1`/`enter()==false` guard moves here). Routing:

- COMBAT/ELITE/BOSS → `begin_node`, go to combat; `complete_combat` commits on win (unchanged,
  still calls `map.enter` with its guard).
- REST → `begin_node`, `commit_pending_node()`, go to `rest_screen`.
- SHOP → `begin_node`, `commit_pending_node()`, go to `shop_screen`.

`apply_rest()` (M4) splits: the commit is now `commit_pending_node()` (done on entry); the
heal becomes `heal_rest()` (heal 30% + save, no commit).

## Map generation (`systems/game_map.gd`)

`_roll_type` gains SHOP on mid rows only. Rows 1–4 weighted roll becomes approximately:
`REST 0.15`, `SHOP 0.12`, `ELITE 0.25` (rows ≥ 2 only), else `COMBAT`. Row 0 (all combat)
and row 5 (all rest) unchanged.

**Guaranteed shop per act:** after type assignment, if the map contains zero SHOP nodes,
convert one randomly chosen eligible node (a non-boss node on rows 1–4, picked via the
generation `rng` for determinism) to SHOP and clear its `enemy_id`. So every act has ≥ 1 shop.

`from_dict`'s node-type range check widens to `type_value > int(MapNode.Type.SHOP)`.

## Gold economy

Awarded in `complete_combat` at commit, by node type:

| Node | Gold |
|------|------|
| Normal combat | `randi_range(9, 15)` |
| Elite | `randi_range(25, 30)` (plus the relic) |
| Boss | none |

(Global `randi_range` — gold need not be seed-reproducible.) Displayed on the map screen,
shop screen, and combat HUD.

Shop prices (`RunState.SHOP_PRICES` or shop-screen consts):

| Buy | Cost |
|-----|------|
| Card | 50 |
| Remove a card | 75 (flat) |
| Relic | 140 |

## Screens

### Rest — `screens/rest_screen.tscn` + `.gd`
Replaces the M4 instant heal. Two buttons:
- **Rest** → `RunState.heal_rest()` → back to map.
- **Upgrade** → open the card picker filtered to upgradable cards (`upgrade_id != &""`) →
  `RunState.upgrade_card(index)` swaps that deck slot to its `+` card → back to map.

One choice per rest. Both routes return to `map_screen`.

### Shop — `screens/shop_screen.tscn` + `.gd`
On entry, roll inventory (via `Array.shuffle()`, like `card_reward`/`relic_reward`): 3 cards
from the reward pool, 1–2 relics from `RELIC_POOL`, and a fixed "Remove a card" service.
Each item shows its price; buying calls the matching `RunState` method, which spends gold and
mutates the run (saved immediately). Items disable when bought or unaffordable; "Remove a
card" opens the picker (any card, disabled when `deck.size() <= 1`). A **Leave** button
returns to `map_screen`. Because the node committed on entry, shop inventory need not persist
across a quit.

### Card picker — extend `screens/deck_viewer.gd`/`.tscn`
Add a selectable mode: shows the deck grid, each card a button, emits a `card_selected(index)`
(or the `CardData`) signal; a filter predicate disables ineligible cards (non-upgradable for
upgrade; the last card for removal). The existing read-only preview mode stays the default so
current callers (map/combat/reward "View Deck") are unaffected.

## Save format — `SAVE_VERSION = 5`

v4 shape plus `"gold": int`. Same aggressive fail-safe (`clear_saved_run()` on any mismatch).
Old v4 saves are cleared on load (expected — new required field). Upgraded cards serialize
through the existing deck-id array (their `_plus` ids must be in `CARD_CATALOG`, or the
existing unknown-id fail-safe clears the save).

## Testing

Pure/logic where possible (RunState methods and `GameMap` are testable headless; screens get
smoke tests via the M4 pattern).

- **Gold:** `complete_combat` awards gold in the right range per node type; boss awards none.
- **Upgrade:** `upgrade_card` swaps the deck slot to the `+` id; deck round-trips by id
  through save/load; non-upgradable cards are rejected/skipped.
- **Removal:** `remove_card` removes the card, refuses when `deck.size() <= 1`, persists.
- **Buying:** `buy_card`/`buy_relic` deduct gold and add to deck/relics; `spend_gold` returns
  false and deducts nothing when short.
- **Generation:** every map has ≥ 1 SHOP; SHOP appears only on rows 1–4; `from_dict` accepts
  SHOP-typed nodes; determinism (same seed → same map, including the guaranteed-shop pass).
- **Save v5:** round-trips `gold`; a v4 save (no gold / wrong version) is cleared.
- **Screens:** rest choice routes correctly; shop builds priced items and disables on
  buy/insufficient funds; card picker emits selection and disables ineligible cards.

## Content to author

- `+` `.tres` for each upgradable card (stats + `upgrade_id=&""`, reuse art) + `CARD_CATALOG`
  entries + base cards' `upgrade_id` set.
- No new enemy/relic content (reuse existing pools).

## Adding content later

- New upgradable card: author base + `_plus`, set `upgrade_id`, register both ids.
- Escalating removal / potions / events / boss gold: future (Polish milestone).
