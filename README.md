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

- Add more card effects and meaningful deck-building choices
- Expand enemy behavior and encounter variety
- Balance health, damage, rewards, and encounter pacing
- Continue refining screen transitions and moment-to-moment feedback
