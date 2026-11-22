# Pomodoro Pond

A koi pond Pomodoro timer. Home (work) and Play pages each embed a Rive file; About is plain text.
Live at https://samaravee.github.io/PomodoroPond/

## Pages
| File | What it is |
|---|---|
| `index.html` | Home, plays `home.riv` (work). Has the pop-out timer button and background timer. |
| `play.html` | Play, plays `play.riv` |
| `about.html` | About |
| `debug.html` | Performance test page. Open `debug.html?file=home.riv` (add `&gpu=0` to turn the shader off) and tap Run test. |
| `goo-ripples.html` | Standalone goo ripples WebGL demo (not linked in the navbar) |
| `home.riv`, `play.riv` | The Rive files. Keep them in the same folder as the pages. |

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

## Still to do
- Replace the `href="#"` placeholders (Discord, Instagram, LinkedIn, Portfolio)
- Spotify (PKCE) login
- Check on 3 screen sizes and 3 browsers

## Deploying
GitHub Pages: Settings > Pages > deploy from branch `main`, folder `/ (root)`. Or drag this folder onto https://app.netlify.com/drop.
