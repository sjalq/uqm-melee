# UQM Super Melee

A browser-based Super Melee recreation in Elm and Lamdera.

Play at https://uqmbattle.lamdera.app/melee.

Includes 25 ship types, classic and HD artwork, local two-player controls, backend-resolved online battles, spectators, reusable room links, and ranked matchmaking.

## Run locally

Install Lamdera, Node.js, and elm-test-rs, then:

```sh
git clone --recurse-submodules https://github.com/sjalq/uqm-melee.git
cd uqm-melee
lamdera live
```

Open http://localhost:8000/melee. Run `./compile.sh` to generate function documentation, run the tests, and compile the app. No API keys or service credentials are required to play or run it locally. Browser sessions identify players; names are optional.

## Controls

Menus support mouse, arrow keys, Enter, and Escape. In local two-player combat, player one uses the arrow keys, Enter to fire, and Shift for the special ability. Player two uses A/D to turn, W for thrust, J to fire, and K for the special ability. Online players each use the player-one keys on their own computer. Ship-specific abilities are described in the catalog.

## Rooms and simulation

The backend resolves online combat. Controls are sent when they change; combat deltas are capped at ten updates per second and lobby previews at two. The front page renders the actual exhibition through the same Elm cockpit view as spectating, with sound muted until enabled. Empty custom rooms retain only their fleet setup, outside the simulation loop. Eight-character room codes are reusable and collision-checked, but rooms remain publicly discoverable.

Elm owns menu navigation, countdown timing, audio selection, and presentation state. Browser API adapters live in `elm-pkg-js/` and are registered by `elm-pkg-js-includes.js`. Styling uses compiled CSS; run `npm run build:css` after changing Tailwind utility classes.

## Artwork and source credits

Original Star Control II / The Ur-Quan Masters art, music, and sounds belong to Toys for Bob and their respective creators. The included content terms and original code licensing are in [public/UQM-COPYING.txt](public/UQM-COPYING.txt). HD artwork credits are in [public/HD-CREDITS.txt](public/HD-CREDITS.txt). These assets are not covered by a blanket MIT license. This project is an unofficial recreation.
