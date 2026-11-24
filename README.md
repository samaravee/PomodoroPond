# Pomodoro Pond

A koi pond Pomodoro timer. Home (work) and Play pages each embed a Rive file; About is plain text.
Live at https://samaravee.github.io/PomodoroPond/

## Pages
| File | What it is |
|---|---|
| `index.html` | Home, plays `home-final02.riv` (work). Has the pop-out timer button and background timer. |
| `play.html` | Play, plays `play-v5.riv` |
| `about.html` | About |
| `debug.html` | Performance test page. Open `debug.html?file=home-final02.riv` (add `&gpu=0` to turn the shader off) and tap Run test. |
| `goo-ripples.html` | Standalone goo ripples WebGL demo (not linked in the navbar) |
| `home-final02.riv`, `play-v5.riv` | The Rive files. Keep them in the same folder as the pages. |

Rive runtime: `@rive-app/webgl2@2.49.4` loaded from jsDelivr (newer files need 2.49 or later).
Each page has a `RIVE_CONFIG` block near the top (file, state machine, aspect ratio, fit).

## Rive source (`rive-source/`)
Copies of the scripts inside the Rive files, so they are versioned. Editing them here does nothing
until you paste them back into the Rive editor and re-export the `.riv` files.
- `GooRipples.wgsl`: paste into the shader asset named exactly `GooRipplesShader`
- `GooRipples.luau`: the node script (`GooRipples`)
The two share constants (`STMAX`, `MAXT`, `MAXC`) and must be updated together.

Tuning knobs are labelled blocks at the top of the shader: COLOUR CONTROLS, PRESS DEPTH, TRAIL RIPPLES,
and `WAKE_LIFE`. The node script has inputs `renderScale`, `hoverStrength` and `dragStrength`.

## Layout and sizing
Home and Play default to `sizing: "layout"` in `RIVE_CONFIG`: the artboard resizes to fill the space under the
navbar, the way it was designed in Rive. Your artboard min/max (1400x1200 to 2000x1400) is set in `minW`, `minH`, `maxW`, `maxH`
(artboard units, 0 = not set). The page never draws the pond bigger than the max, and zooms out instead of
cropping when the screen is smaller than the min.
The page measures how artboard units map to screen pixels and adjusts the zoom itself. The console logs a
line starting with `[pond] canvas ...` showing the canvas and artboard sizes.
If layout mode misbehaves, set `sizing: "contain"` (the earlier behaviour, whole artboard scaled as one piece).

## Volume
`bindVolume()` finds the number property named `volume` (also inside nested view models such as `PondVM`),
applies it to Rive's audio volume, to any `<audio>`/`<video>` on the page, and fires a `pond:volume` event
(value 0 to 1) for the Spotify player later. Set `volumePath` (e.g. `"PondVM/volume"`) if it isn't found,
`volumeMax` (1 or 100) if the range is guessed wrong, and `volumeToRive` stays false (see Sound).

## Zoom, pop-out and colour
- **Zoom:** the pond zooms in to fill the area under the navbar, but never crops into the central 1550 x 800 of the
  artboard (`--safe-w` / `--safe-h` at the top of the CSS). Set them to 2000 and 1400 to never crop.
- **Pop-out button:** large, accent-coloured, with an icon. The pop-out window shows the artboard cropped in by 225 units
  on the left and right and 300 on the top and bottom (`popout` in `RIVE_CONFIG`, in artboard units; `width` is the
  window width in px and the height follows). Resizing the window crops a little more or less instead of leaving gaps.
- **Accent colour:** #6AA496 on every page (`--accent` in each file's CSS).

## Timer in the background
Browsers stop animation frames in hidden tabs, and Rive 2.49.4 also adds its own "tab hidden" handler that stops its loop
and resets its clock. The page removes Rive's handler right after creating the Rive instance and keeps the loop ticking from
a background worker while the tab is hidden (on a tiny canvas). Not saved: the timer if you leave the page or close the tab.

## Sound
- **Master volume:** Rive's looping music does not follow Rive's own volume setting once it is playing (only new sounds do).
  So a small script before the Rive runtime puts one gain control in front of the speakers, and the `volume` slider drives it.
  It covers the music and the sound effects. `volumeToRive` stays `false` so the slider isn't applied twice.
- **First click:** browsers keep sound off until the visitor clicks once, so the loop starts on that first click. Set
  `soundGate: true` in `RIVE_CONFIG` to show an "Enter the pond" button first so it starts with the pond instead.

## Remembered settings
With `remember: true` the page saves volume, `workMinutes`, `shortBreakMinutes`, `BreakMinutes`, `longBreakMinutes` and
`muted`/`mute`/`isMuted` (if your file has them) in the browser's localStorage and restores them next visit. Home and Play
share them. The running timer itself (time left, paused/running) is not saved. Edit `rememberNumbers` / `rememberBooleans`
in `RIVE_CONFIG` to change the list.

## Checked so far
Chromium, with a stand-in for Rive's engine: layout sizing at 1440x900, 2560x1300, 390x844, 844x390 (device\npixel ratio 1 and 2) and volume binding. The stand-in is not the real runtime. NOT yet checked: real Rive
rendering, Firefox and Safari.

## Still to do
- Replace the `href="#"` placeholders (Discord, Instagram, LinkedIn, Portfolio)
- Spotify (PKCE) login
- Test in Firefox and Safari

## Deploying
GitHub Pages: Settings > Pages > deploy from branch `main`, folder `/ (root)`. Or drag this folder onto https://app.netlify.com/drop.

## v13: in-page sizing
- The pond now shows the artboard at full height (top and bottom edges just in view, never cropped) and stretches sideways to fill the width, between `minW` and `maxW` (RIVE_CONFIG, in artboard units, assumed 1400 to 2000). Wider than `maxW`: side bars. Set `maxW: 0` to let it stretch without limit.
- Pop-out crop is unchanged (225 left/right, 300 top/bottom).
- `sizing: "contain"` is the one-word fallback (whole artboard, never cropped).
- Console prints `[pond] canvas ...`; it warns if the artboard height drifts from `artH`.

## v14
- New Rive file `home-final02.riv` (your final01_2).
- Audio: every audio context Rive creates is now resumed on the first click/key/touch. Console prints `[pond] audio: N context(s), states: ...` (should say "running" after a click).
- Test sizing without editing: add `?sizing=contain` or `?sizing=layout` to the page address.

## v15
- Music fix: Rive starts the looping music in its first frame, before any click, and at that moment gives the artboard volume 0. A playing sound keeps its starting volume, so the music stayed silent even after clicks. The page now sets the artboard to full volume just before that first frame; the music is heard on the first click. Console: `[pond] music: artboard volume was 0 before the first frame, set to 1`.
- About 1.5 s and 6 s after the first click the console prints `[pond] sound level: peak ...` and says whether sound is actually coming out.
- No more red "Cannot resume a closed AudioContext" errors (closed test contexts are skipped).
- In-page sizing: the zoom is worked out before Rive draws, so the artboard is ~2000 x 1400 units from the first frame and right after every resize (v14 drew one wrong-size frame first, then corrected).
- Uses `stateMachine` (Rive's deprecation warning is gone). play.html has the same changes.

## v16
- Home: the pond hides the top 300 artboard units (`cropTop: 300` in RIVE_CONFIG; 0 shows it all), so it is drawn larger. The pop-out is unchanged. Play has `cropTop: 0`.
- The pop-out button replaced "Join Our Discord!" in the header on Home and Play; the old button above the pond is gone. About keeps the Discord button.
- About: Portfolio is the first link, filled with the green accent; Instagram and LinkedIn stay outlined.

## v17
- Undid the v16 top crop (`cropTop: 0`): the whole artboard shows again.
- The pond now sits directly under the header (top-aligned) instead of centred with empty space above it.

## v18
- Removed the outline, rounded corners and grey fill the page drew around the pond (`.rive-frame` in the CSS), on Home and Play.
