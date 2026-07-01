# First Game

A small 2D deck-building game built with Godot 4.7 and typed GDScript.

## Running the game

Open `project.godot` in Godot 4.7 and press **F6/F5**. Start a run, defeat all
three encounters, and add one card to your deck after each non-final victory.

The **Main Menu** button safely leaves combat or a reward screen. **Continue
Run** resumes the most recent stable checkpoint when a save exists.

## Project layout

- `cards/` - card definitions, runtime card state, and card UI
- `combat/` - combat rules, turn state, and the combat screen
- `enemies/` - enemy definitions and move patterns
- `screens/` - title, rewards, and run-complete screens
- `systems/` - persistent run state, decks, and saving
- `assets/` - art, audio, and fonts

Card and enemy definitions are custom `Resource` files. Temporary state for a
run or combat stays in runtime classes rather than changing those definitions.

## Completed milestone: playable run

- Three encounters with distinct enemy move patterns
- Turn-based card combat with energy, block, draw, and discard piles
- Persistent health and deck growth between encounters
- Card rewards after victories
- Victory, defeat, restart, and run-complete states

## Completed milestone: combat feedback and animation

- Animate card hover and card play
- Animate health changes
- Add enemy and player hit reactions
- Show floating damage and block values
- Pace enemy turns so their actions are readable
- Lock input while actions are resolving

## Completed milestone: deck visibility and navigation

- View the complete run deck during combat, rewards, and the final summary
- Reuse one modal deck-viewer scene throughout the game
- Fade smoothly between top-level screens

## Completed milestone: save and continue

- Autosave health, encounter progress, and card IDs
- Offer Continue Run from the title screen
- Return to the Main Menu from combat and reward screens
- Resume pending rewards or restart the current encounter safely
- Clear completed or defeated run saves
- Handle missing or outdated save data safely

Saves are versioned JSON files stored under Godot's `user://` directory. Card
IDs are serialized instead of live Resource objects, then resolved through the
known card catalog when loading.

## Completed milestone: audio and visual identity

- Original illustrated artwork for all six cards and three enemies
- Illustrated title and combat backgrounds
- Shared dark-fantasy theme for panels, buttons, progress bars, and text
- Themed title, combat, and card-reward screens
- Distinct selected and de-emphasized reward-card states
- Illustrated End Turn control with a two-pulse zero-energy prompt
- Sound effects for cards, damage, block, and UI actions
- Looping ambient music with saved music and effects volume controls

Audio is routed through separate Music and SFX buses managed by the
`AudioManager` autoload. Third-party CC0 audio provenance is recorded in
`assets/audio/SOURCES.md`.

## Next milestone: gameplay depth and polish

- Add more card effects and meaningful deck-building choices (in progress: card draw,
  energy gain, one-turn block retention, healing, lifesteal, and energy overflow)
- Expand enemy behavior and encounter variety
- Balance health, damage, rewards, and encounter pacing
- Continue refining screen transitions and moment-to-moment feedback

The reward pool now includes tempo-oriented Guarded Strike, energy-restoring Power
Blow, free Quick Guard, and Fortify, which carries unspent block into the next turn.
It also holds Second Wind (energy over the cap), Devour (heavy lifesteal), Mend
(flat healing), Bulwark (a retained wall of block), and Rally (attack, draw, and
refund). Each reward now offers three cards drawn at random from that pool.

## Roadmap: roguelike depth and replayability

Candidate milestones, roughly ordered by how much later work depends on them.
Impact is depth/dynamism added; effort is build size against the current
data-driven combat. The near-term goal is a **branching map** to drive content
and replayability, sequenced after the combat foundations it relies on.

Foundations (unlock most later design):

- **Status effects** - stacking buffs/debuffs (Vulnerable, Weak, Poison,
  Strength, Dexterity). Biggest depth multiplier. Impact: high. Effort: medium.
  DONE: Vulnerable, Weak, Strength, and Poison, with the Expose/Sap/Flex/Venom
  Cut cards and the Road Raider/Iron Guardian debuff moves.
- **Enemy AI variety and intents** - conditional/weighted move selection and
  clearer intent display. Impact: high. Effort: medium.

Run loop (the branching-map goal):

- **Branching map** - node graph (combat / elite / rest / shop / event / boss)
  replacing the fixed three encounters. Impact: high. Effort: large.
- **Gold and shop** - currency earned in combat, spent on cards, relics, and
  card removal; a shop map node. Impact: medium. Effort: medium.
- **Relics** - persistent run-modifying artifacts with combat/run hooks.
  Impact: high. Effort: medium.

Deck sculpting:

- **Card upgrades and removal** - rest sites that heal or upgrade a card, plus
  removal to thin the deck. Impact: high. Effort: medium.
- **Card keywords** - Exhaust, Retain, Innate, X-cost. Impact: medium.
  Effort: medium.

Content and replay:

- **Potions / consumables** - one-shot combat items. Impact: low. Effort: small.
- **Elites and a boss** - unique tougher encounters (needs status effects and
  enemy AI). Impact: medium. Effort: medium.
- **Ascension / difficulty tiers** - post-victory replay hook. Impact: low.
  Effort: small.

Recommended sequence: status effects, then relics, then the branching map (with
gold and shop as node types), then upgrades and removal, then more content.
