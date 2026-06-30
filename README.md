# First Game

A small 2D deck-building game built with Godot 4.7 and typed GDScript.

## Project layout

- `cards/` — card definitions, runtime card state, and card UI
- `combat/` — combat rules, turn state, and the combat screen
- `enemies/` — enemy definitions and presentation
- `screens/` — top-level screens such as the main menu and run map
- `systems/` — reusable systems such as decks and saving
- `assets/` — art, audio, and fonts

Card and enemy definitions are custom `Resource` files. Temporary state for a
run or combat stays in runtime classes rather than changing those definitions.

## First milestone

Build one combat containing one enemy and five cards, with draw, discard,
energy, and win/lose conditions.
