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

## Next milestone: audio and visual identity

- Added original illustrated artwork for all six cards and three enemies
- Connected artwork through the existing card and enemy Resource definitions
- Added a shared dark-fantasy theme for panels, buttons, progress bars, and text
- Added sound effects for cards, damage, block, and UI actions
- Added a looping ambient track with separate music and effects volume controls
