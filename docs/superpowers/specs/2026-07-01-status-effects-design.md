# Status Effects - Design

Date: 2026-07-01
Milestone: 1 of the roguelike roadmap (see `2026-07-01-roguelike-roadmap.md`).

## Goal

Add a combat status-effect system with four statuses (Vulnerable, Weak,
Strength, Poison), shown as text badges, applied by a starter batch of cards and
enemy moves. This is the depth foundation later milestones (elites, boss, more
cards) build on. Statuses are combat-scoped and do not change the save format.

## 1. The four statuses

| Status | Type | Effect | Timing |
|--------|------|--------|--------|
| Vulnerable | duration | afflicted takes x1.25 attack damage (floored) | ticks -1 at end of afflicted's turn |
| Weak | duration | afflicted deals x0.75 attack damage (floored) | ticks -1 at end of afflicted's turn |
| Strength | persistent | +N flat damage per attack | never decays within a combat |
| Poison | decrementing | lose N HP (ignores block) at start of owner's turn, then N-1 | self-decrements as it fires |

Only attacks (base damage > 0) are affected by Strength/Weak/Vulnerable. Pure
skill/block cards are unaffected.

## 2. Damage math (order matters)

For an attack of base `B`, attacker -> defender:

```
dmg = floor( floor( (B + attacker.strength) * weak_mult ) * vuln_mult )
   weak_mult = 0.75 if attacker Weak else 1.0
   vuln_mult = 1.25 if defender Vulnerable else 1.0
   dmg = max(0, dmg)
```

Then the existing block logic absorbs `dmg` (block first, remainder to health).
Poison is separate and ignores block.

Worked example: base 6, +2 Strength, attacker Weak, defender Vulnerable ->
`floor(floor(8 * 0.75) * 1.25)` = `floor(6 * 1.25)` = `floor(7.5)` = 7.

## 3. StatusSet (the unit)

`class_name StatusSet extends RefCounted` in `systems/status_set.gd`.

- `enum Type { VULNERABLE, WEAK, STRENGTH, POISON }`
- `var stacks: Dictionary = {}` (Type -> int)
- `add(type: Type, amount: int) -> void` - `stacks[type] = max(0, current + amount)`; erase key when 0.
- `amount(type: Type) -> int`
- `attack_bonus() -> int` - returns Strength amount
- `outgoing_multiplier() -> float` - 0.75 if Weak else 1.0
- `incoming_multiplier() -> float` - 1.25 if Vulnerable else 1.0
- `tick_turn_start() -> int` - returns current Poison, then decrements Poison by 1 (CombatState applies the HP loss)
- `tick_turn_end() -> void` - decrements Vulnerable and Weak by 1 each (min 0)
- `describe() -> Array` - ordered badge data `[{ "label": String, "amount": int, "kind": String }]` for the UI

All status behavior lives here; `CombatState` calls these instead of inline
conditionals (mirrors how `Deck` factors piles out of `CombatState`).

## 4. CombatState integration and turn timing

`CombatState` gains `player_status := StatusSet.new()` and
`enemy_status := StatusSet.new()`, both reset in `begin()`.

Shared helper:
`_attack_damage(base: int, attacker: StatusSet, defender: StatusSet) -> int`
implements the section 2 formula (returns pre-block damage; 0 when base is 0).

Timing hooks mapped to the asymmetric loop (`end_player_turn` runs the whole
enemy action):

- Player regains control (not at combat start): apply player Poison via
  `player_status.tick_turn_start()`, subtract from `player_health` ignoring
  block; if 0 -> `Phase.LOST`.
- `end_player_turn` start: `player_status.tick_turn_end()` (player's Vulnerable/
  Weak count down).
- Enemy turn (inside `end_player_turn`):
  1. Enemy Poison via `enemy_status.tick_turn_start()`, subtract from
     `enemy_health`; if 0 -> `Phase.WON`, skip the rest of the enemy action.
  2. Enemy attack: `damage = _attack_damage(enemy_move.damage, enemy_status,
     player_status)`, then existing block logic vs `player_block`.
  3. Enemy applies move statuses to player (`player_status.add(WEAK,
     move.weak_applied)` etc.) and self-buffs (`enemy_status.add(STRENGTH,
     move.strength_gained)`).
  4. `enemy_status.tick_turn_end()`.
- Return to player turn: apply player Poison (the "player regains control" hook
  above), then draw.

`play_card` (player attacks enemy):
- `damage_dealt` uses `_attack_damage(card.damage, player_status, enemy_status)`
  when `card.damage > 0`; block logic unchanged.
- Apply card statuses: `enemy_status.add(VULNERABLE, card.vulnerable_applied)`,
  `add(WEAK, card.weak_applied)`, `add(POISON, card.poison_applied)`;
  `player_status.add(STRENGTH, card.strength_gained)`.

## 5. New data fields

CardData (new `int` fields, default 0):
- `vulnerable_applied`, `weak_applied`, `poison_applied` - applied to the enemy
- `strength_gained` - applied to the player (self)

EnemyMoveData (new `int` fields, default 0):
- `weak_applied`, `vulnerable_applied`, `poison_applied` - applied to the player
- `strength_gained` - applied to the enemy (self)

## 6. Result dict and display

`play_card` and `end_player_turn` result dicts gain status info: statuses applied
(target + label + amount) and poison damage dealt.

`combat_screen.gd`:
- Floating text for status applications ("VULN 2", "POISON 3") and poison ticks,
  reusing `_spawn_floating_value`.
- Badges: two new HBox containers `%PlayerStatuses` and `%EnemyStatuses` added to
  `combat_screen.tscn`; `_refresh_combat_view` rebuilds them from the status sets
  via `describe()`. Badge text `Vuln 2` / `Poison 5` / `Str 2`, color-coded
  (debuff red, poison green, buff gold).

## 7. Starter content

Four new cards (art via `tools/gen_asset.py` at 1254x1254, registered in
`RunState.CARD_CATALOG`, added to the reward pool):
- Expose - 1 energy, apply 2 Vulnerable
- Sap - 1 energy, apply 2 Weak
- Flex - 1 energy, gain 2 Strength
- Venom Cut - 1 energy, deal 4, apply 3 Poison

Two new enemy moves (`.tres`, slotted into existing patterns):
- Road Raider -> Hobbling Slash (deal 6, apply 1 Weak)
- Iron Guardian -> Dread Roar (apply 2 Vulnerable)

## 8. Save integration

Statuses are combat-scoped: created fresh each `begin()`, never serialized. The
`RunState` save format is unchanged; existing saves and tests are unaffected.

## 9. Testing

New cases in `tests/combat_state_test.gd`:
- Vulnerable increases attack damage taken (floored).
- Weak reduces attack damage dealt (floored).
- Strength adds flat damage per attack.
- Poison deals damage at turn start, ignores block, and decrements.
- Duration statuses (Vulnerable/Weak) decrement and expire.
- Combined Strength + Weak + Vulnerable matches the section 2 formula (expect 7).
- An enemy move applies a status to the player.

## 10. Success criteria

- All four statuses work in live combat, shown as badges, applied by the starter
  cards and enemy moves.
- Damage math is deterministic and covered by tests.
- Save format is untouched; existing tests remain green.
- Playable: inflict Vulnerable then hit hard; poison an enemy to death; buff
  Strength; get Weakened by an enemy move.

## Out of scope

Dexterity, Frail, and other statuses; relic-granted permanent buffs; status
icons (text badges only); enemy AI changes beyond adding the two moves above.
