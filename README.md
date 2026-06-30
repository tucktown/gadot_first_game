# First Game

A small 2D deck-building game built with Godot 4.7 and typed GDScript.

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

## Next milestone: combat feedback and animation

- Animate card hover and card play
- Animate health changes
- Add enemy and player hit reactions
- Show floating damage and block values
- Pace enemy turns so their actions are readable
- Lock input while actions are resolving

After this milestone, the next priorities are sound, scene transitions, a deck
viewer, and save/continue support.
