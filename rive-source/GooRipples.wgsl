// Goo Ripples: WGSL fragment shader for Rive.
// Script type in the Rive editor: "Shader" (WGSL Shader), not Blank.
// Name the asset exactly:  GooRipplesShader   (the Node script is called GooRipples)
//
// One big triangle covers the canvas. Everything is computed per pixel from a single
// uniform buffer that the Luau script (GooRipples.luau) fills every frame.

const MAXC: i32 = 24;       // click ring slots
const MAXT: i32 = 128;      // trail points
const STMAX: f32 = 4.0;     // highest wake strength a trail point can carry (must match the script)
const LIFE: f32 = 1.1;      // goo tail lifetime (seconds)
const WLIFE: f32 = 1.7;     // (old wake lifetime, still used by the unused trailPt function)
// The thin individual wake circles behind the cursor. They were the "tail chasing you" and they
// show up strongly when pressing. Lower = they vanish sooner and stay closer. 0.4 to 0.9 works well.
const WAKE_LIFE: f32 = 0.70;
const PI: f32 = 3.14159265;

// How strong the boat's drag is compared with the click ripples (1.0 = full strength).
// These only change opacity and displacement, never the width or length of the drag.
const DRAG_DARK: f32 = 0.06;    // its shadow
const DRAG_LIGHT: f32 = 0.11;   // its highlights
const DRAG_DISP: f32 = 0.50;    // how much it bends the backdrop

// ================= COLOUR CONTROLS: click rings and drag trail =================
// Each group has the same four settings. Defaults for HUE and SAT leave the colours as they were.
//   HUE    rotates the colour around the colour wheel, in degrees (-180 to 180). 0 = unchanged.
//   SAT    saturation. 1 = unchanged, 0 = grey, above 1 = more vivid.
//   *_DARK_OPACITY   how strong the shadow side of the effect is (0 = none, 1 = full).
//   *_LIGHT_OPACITY  how strong the highlight side is (0 = none, 1 = full).
// The rings were much darker than the trail because their shadow ran at 0.92 while the trail's
// ran at 0.92 x 0.06. If the rings still feel too dark, lower RING_DARK_OPACITY first.

// Click rings
const RING_HUE: f32 = 0.0;
const RING_SAT: f32 = 1.0;
const RING_DARK_OPACITY: f32 = 0.60;    // was 0.92
const RING_LIGHT_OPACITY: f32 = 0.65;   // was 0.65

// Drag trail (the goo and wake behind the cursor). The final opacity is the number below times
// the base 0.92 (dark) or 0.65 (light), so 0.06 means about 5.5% shadow. DRAG_DARK and
// DRAG_LIGHT are the trail's opacity controls.
const TRAIL_HUE: f32 = 0.0;
const TRAIL_SAT: f32 = 1.0;
// Trail opacity: see DRAG_DARK (shadow) and DRAG_LIGHT (highlight) above
// ================================================================================

// ================= PRESS DEPTH: how a click-drag differs from a hover =================
// The node script sends a stronger wake while the button is held (dragStrength) than while just
// hovering (hoverStrength). These settings turn that extra strength into a "deeper" look. The
// effect fades in as the strength rises from 1 to 2, and stays at full from 2 upward. The depth is
// remembered per trail point, so a pressed stroke stays deep as it fades, then eases back.
const PRESS_DEPTH_SLOPE: f32 = 2.2;     // steeper sides = a deeper dent (1 = off)
const PRESS_DEPTH_OPACITY: f32 = 3.0;   // shadow and highlight strength of the dent (1 = off)
const FOAM_PRESS_GAIN: f32 = 0.15;      // how much of the extra strength goes into white water (0 = none, 1 = all)
// ================================================================================

// ================= TRAIL RIPPLES: rings that radiate out from the wake =================
// Every trail point sends out a ring, like a click does. The rings are NOT added together. They
// are merged into one outline (the union of all the circles, a "smooth minimum" of their
// distances), and the ripples follow that single outline. So neighbouring circles fuse into one
// shape and there are no overlapping middles. The ripples use the click-ring colours and opacity
// (RING_HUE, RING_SAT, RING_DARK_OPACITY, RING_LIGHT_OPACITY).
const TRAIL_RIPPLE_OPACITY: f32 = 0.60; // overall strength (0 = off, 1 = as strong as click rings)
const TRAIL_RIPPLE_SPEED: f32 = 100.0;  // how fast the rings spread outward, px per second
const TRAIL_RIPPLE_LIFE: f32 = 0.80;    // how long each ripple lasts, in seconds. Lower = the tail of the trail disappears sooner
                                        // (the farthest a ripple can ever get is START + SPEED x LIFE pixels from where it began)
const TRAIL_RIPPLE_START: f32 = 16.0;   // ring radius when a trail point is born, px
const TRAIL_RIPPLE_FREQ: f32 = 0.18;    // ring spacing: higher = tighter, more rings (0.18 = click rings)
const TRAIL_RIPPLE_OUT: f32 = 45.0;     // how far the ripples reach outward from the outline, px (more = more rings)
const TRAIL_RIPPLE_IN: f32 = 10.0;      // how far they reach inward (small keeps the middle clear)
const TRAIL_RIPPLE_BLEND: f32 = 0.15;   // how smoothly neighbouring circles merge (lower = softer, more merged; higher = sharper creases)
// ================================================================================

// How tall the drag's two parts are. Lower BLOB for a flatter, less "raised" bump under and
// behind the cursor. WAKE is the thin fold lines that look like ripples. 1.0 = as before.
const DRAG_BLOB: f32 = 1.00;     // the goo blob and trail (the raised look)
const DRAG_WAKE: f32 = 1.00;     // the wake fold lines

// White water: frothy foam that follows the wake. It forms two arms that open behind the boat
// (clear water between them) plus a short churn right behind it.
const FOAM_AMOUNT: f32 = 0.35;  // overall strength (0 = off)
const FOAM_SPREAD: f32 = 0.22;  // how wide the V of foam opens (bigger = wider angle)
const FOAM_LIFE: f32 = 0.64;    // how long the foam lasts, in seconds (keep at or under WLIFE)
const FOAM_SCALE: f32 = 0.50;   // froth size: higher = finer, lower = chunkier
const FOAM_ARM_WIDTH: f32 = 0.71; // width multiplier of the foam arms

// White water look. Stylized is the default; for a graphic, cel-shaded look use
// GRAIN 0.00, SOFT 0.07, CEL 1.00, LUMP 0.55. For natural froth use 1.00, 0.195, 0.00, 1.00.
const FOAM_GRAIN: f32 = 0.05;   // fine speckle and grit (0 = smooth)
const FOAM_SOFT: f32 = 0.23;    // edge softness (small = crisp, graphic edges)
const FOAM_CEL: f32 = 0.00;     // 0 = smooth shading, 1 = flat cel-shaded tones
const FOAM_LUMP: f32 = 0.29;    // how lumpy the froth is

// Thickness of the trail line (goo trail and wake lines) from the boat to the tail end.
const TRAIL_THICK_START: f32 = 0.40;   // width multiplier at the boat
const TRAIL_THICK_END: f32 = 1.00;     // width multiplier at the tail end

// Only fast movement makes white water. Foam fades in around this boat speed (pixels per second).
// 0 = foam at any speed; a quick mouse sweep is roughly 800-2000.
const FOAM_MIN_SPEED: f32 = 1090.0;

// If the effect shows up upside-down relative to the pointer, flip this.
const FLIP_Y: bool = true;

struct Uniforms {
    res: vec2<f32>,                  // canvas size in px
    time: f32,                       // seconds
    showBg: f32,                     // 1 = draw backdrop, 0 = transparent overlay only
    slosh: vec4<f32>,                // whole-surface slosh: x-axis modes 1,2 / y-axis modes 1,2
    head: vec4<f32>,                 // the boat: x, y, blob strength, (unused)
    clicks: array<vec4<f32>, 24>,    // x, y, start time, strength
    pt: array<vec4<f32>, 128>,       // trail points, newest first: x, y, spawn time, arc+strength
}

@group(0) @binding(0)
var<uniform> u: Uniforms;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
    // One oversized triangle: clipping leaves the whole canvas covered.
    var pos = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0),
    );
    let p = pos[vertexIndex];
    var out: VertexOutput;
    out.position = vec4<f32>(p, 0.0, 1.0);
    out.uv = p * 0.5 + vec2<f32>(0.5, 0.5);
    return out;
}

// Smooth noise along a stroke: three sine layers. arc is the distance travelled along the
// stroke in px, wrapping every 4096px (the frequencies are whole multiples of 2*PI/4096, so
// it wraps seamlessly). Wavelengths run from about 60px to 180px. Returns roughly -1..1.
fn trailNoise(arc: f32, seed: f32) -> f32 {
    let q = arc * (6.28318530718 / 4096.0);
    return 0.55 * sin(q * 23.0 + seed)
         + 0.30 * sin(q * 41.0 + seed * 1.7 + 2.1)
         + 0.15 * sin(q * 67.0 + seed * 0.6 + 4.0);
}

// One trail point: a soft blob of goo plus a ring of wake that spreads out from it.
// Returns (goo, wake). Every point is a smooth round source (no segments, so no seams where
// pieces meet), and the V behind the boat comes from all the rings adding up. Weighted by
// the spacing to the next older point so the look doesn't change with mouse speed.
// Each point also carries its distance along the stroke (packed into a.w next to its
// strength), which drives the variation: the line wiggles sideways, and swells and thins.
fn trailPt(p: vec2<f32>, a: vec4<f32>, b: vec4<f32>) -> vec2<f32> {
    let zero2 = vec2<f32>(0.0, 0.0);
    if (a.z < -100.0) { return zero2; }                   // unused slot
    let t = u.time - a.z;
    let uw = t / WLIFE;
    if (uw < 0.0 || uw >= 1.0) { return zero2; }

    // Unpack a.w: whole part = distance along the stroke (in 2px steps), fraction = speed (6 bits)
    // and strength (7 bits) packed together.
    let arcF = floor(a.w);
    let code = floor((a.w - arcF) * 8192.0 + 0.5);
    let spdQ = floor(code / 128.0);
    let st = (code - spdQ * 128.0) / 127.0 * STMAX;      // strength (0 to STMAX)
    let arc = arcF * 2.0;                                // distance along the stroke, px

    // Waviness: slide the point sideways along a slow wave. It starts at nothing at the
    // boat and grows as the trail ages, so the tail ripples like a snake.
    let dir = a.xy - b.xy;
    let dl = length(dir);
    var c = a.xy;
    if (dl > 0.5 && dl < 40.0) {
        let perp = vec2<f32>(-dir.y, dir.x) / dl;
        c = c + perp * (18.0 * smoothstep(0.0, 0.5, t)) * trailNoise(arc, t);
    }

    // Thickness and strength variation along the stroke
    let th = 1.0 + 0.40 * trailNoise(arc, 3.1);
    let sw = 1.0 + 0.30 * trailNoise(arc, 5.3);

    // Line thickness from the boat (start) to the tail end of the trail
    let tw = mix(TRAIL_THICK_START, TRAIL_THICK_END, smoothstep(0.0, 1.0, uw));

    let d = p - c;
    let d2 = dot(d, d);
    if (d2 > 52000.0) { return zero2; }                   // too far to matter: skip the maths

    var L = dl;
    if (b.z < -100.0) { L = 14.0; }
    let wgt = min(1.0, L / 14.0);

    var goo = 0.0;
    // Goo: older = softer and much fainter, so it melts away instead of becoming a ridge
    let lu = t / LIFE;
    if (lu < 1.0) {
        let s = (14.0 + 30.0 * pow(1.0 - lu, 0.9)) * th * tw;
        goo = 0.42 * st * sw * wgt * pow(1.0 - lu, 2.0) * exp(-d2 / (2.0 * s * s));
    }

    // Wake: a soft ring spreading from this point. Soft |d| so the middle has no crease.
    let r = (14.0 + 70.0 * t) * (1.0 + 0.15 * trailNoise(arc, 8.7));
    let x = sqrt(d2 + 100.0) - r;
    let ww = (12.0 + 9.0 * t) * th * tw;
    let wake = 0.18 * st * sw * wgt * pow(1.0 - uw, 1.5) * exp(-x * x / (2.0 * ww * ww));

    return vec2<f32>(goo, wake);
}

// Soft "goo" height field from the boat's drag, evaluated at three points at once:
// p, p + (e,0) and p + (0,e). The old code ran the whole 127-point trail loop three times,
// repeating the same per-point maths each time. Here that shared work is done once per point.
// The result is the same numbers as before, just cheaper.
//
// Trail points are stored newest first, so spawn times only get older down the list. The first
// point that is unused or past its lifetime means every later one is too, so the loop stops there.
// u.pt is the same for every pixel, so all pixels stop at the same place. With nothing moving
// the loop ends on its first step.
fn dragHeight3(p: vec2<f32>, e: f32) -> vec4<f32> {
    let p1 = p + vec2<f32>(e, 0.0);
    let p2 = p + vec2<f32>(0.0, e);
    var f0 = 0.0; var f1 = 0.0; var f2 = 0.0;
    var w0 = 0.0; var w1 = 0.0; var w2 = 0.0;
    var gs = 0.0;   // total goo and wake nearby (the weights for the press average)
    var gp = 0.0;   // the same, weighted by how hard each point was pressed

    for (var i: i32 = 0; i < MAXT - 1; i = i + 1) {
        let a = u.pt[i];
        let t = u.time - a.z;
        if (a.z < -100.0 || t >= max(LIFE, WAKE_LIFE)) { break; }   // this and every older point is dead
        if (t < 0.0) { continue; }

        // Quick reject before any maths. The wave offset moves a point at most 18px, so a
        // distance above (228+18)^2 can never pass the per-sample test below.
        let q0 = p - a.xy;
        let q1 = p1 - a.xy;
        let q2 = p2 - a.xy;
        let near = min(dot(q0, q0), min(dot(q1, q1), dot(q2, q2)));
        if (near > 61000.0) { continue; }

        let b = u.pt[i + 1];
        let uw = t / WAKE_LIFE;

        let arcF = floor(a.w);
        let code = floor((a.w - arcF) * 8192.0 + 0.5);
        let spdQ = floor(code / 128.0);
        let st = (code - spdQ * 128.0) / 127.0 * STMAX;
        let arc = arcF * 2.0;

        let dir = a.xy - b.xy;
        let dl = length(dir);
        var c = a.xy;
        if (dl > 0.5 && dl < 40.0) {
            let perp = vec2<f32>(-dir.y, dir.x) / dl;
            c = c + perp * (18.0 * smoothstep(0.0, 0.5, t)) * trailNoise(arc, t);
        }

        let th = 1.0 + 0.40 * trailNoise(arc, 3.1);
        let sw = 1.0 + 0.30 * trailNoise(arc, 5.3);
        let tw = mix(TRAIL_THICK_START, TRAIL_THICK_END, smoothstep(0.0, 1.0, t / WLIFE));   // thickness still ages over the old 1.7 s

        var L = dl;
        if (b.z < -100.0) { L = 14.0; }
        let wgt = min(1.0, L / 14.0);

        // Goo: strength and falloff, shared by the three samples
        var gooK = 0.0;
        var gooInv = 0.0;
        let lu = t / LIFE;
        if (lu < 1.0) {
            let s = (14.0 + 30.0 * pow(1.0 - lu, 0.9)) * th * tw;
            gooK = 0.42 * st * sw * wgt * pow(1.0 - lu, 2.0);
            gooInv = 1.0 / (2.0 * s * s);
        }
        // Wake ring: radius, width and strength, shared by the three samples
        let r = (14.0 + 70.0 * t) * (1.0 + 0.15 * trailNoise(arc, 8.7));
        let ww = (12.0 + 9.0 * t) * th * tw;
        var wakeK = 0.0;
        if (uw < 1.0) { wakeK = 0.18 * st * sw * wgt * pow(1.0 - uw, 1.5); }
        let wakeInv = 1.0 / (2.0 * ww * ww);

        let d0 = p - c;   let s0 = dot(d0, d0);
        let d1 = p1 - c;  let s1 = dot(d1, d1);
        let d2 = p2 - c;  let s2 = dot(d2, d2);
        if (s0 <= 52000.0) {
            let x = sqrt(s0 + 100.0) - r;
            let g0 = gooK * exp(-s0 * gooInv);
            let k0 = wakeK * exp(-x * x * wakeInv);
            f0 = f0 + g0;
            w0 = w0 + k0;
            gs = gs + g0 + k0;
            gp = gp + (g0 + k0) * clamp(st - 1.0, 0.0, 1.0);
        }
        if (s1 <= 52000.0) {
            let x = sqrt(s1 + 100.0) - r;
            f1 = f1 + gooK * exp(-s1 * gooInv);
            w1 = w1 + wakeK * exp(-x * x * wakeInv);
        }
        if (s2 <= 52000.0) {
            let x = sqrt(s2 + 100.0) - r;
            f2 = f2 + gooK * exp(-s2 * gooInv);
            w2 = w2 + wakeK * exp(-x * x * wakeInv);
        }
    }

    // Blob right at the boat, then saturate so overlaps fuse into one gooey mass
    let b0 = p - u.head.xy;
    let b1 = p1 - u.head.xy;
    let b2 = p2 - u.head.xy;
    let bl0 = 0.9 * u.head.z * exp(-dot(b0, b0) / (2.0 * 36.0 * 36.0));
    f0 = f0 + bl0;
    gs = gs + bl0;
    gp = gp + bl0 * clamp(u.head.z - 1.0, 0.0, 1.0);
    f1 = f1 + 0.9 * u.head.z * exp(-dot(b1, b1) / (2.0 * 36.0 * 36.0));
    f2 = f2 + 0.9 * u.head.z * exp(-dot(b2, b2) / (2.0 * 36.0 * 36.0));
    return vec4<f32>(
        DRAG_BLOB * (1.0 - exp(-1.5 * f0)) + DRAG_WAKE * w0,
        DRAG_BLOB * (1.0 - exp(-1.5 * f1)) + DRAG_WAKE * w1,
        DRAG_BLOB * (1.0 - exp(-1.5 * f2)) + DRAG_WAKE * w2,
        gp / max(gs, 0.0001));      // 0 = hover-like, 1 = fully pressed
}

// The click rings, kept separate from the drag so each can be balanced on its own
fn clickHeight(p: vec2<f32>) -> f32 {
    var h = 0.0;
    for (var i: i32 = 0; i < MAXC; i = i + 1) {
        let c = u.clicks[i];
        let t = u.time - c.z;
        if (t < 0.0 || t > 6.0) { continue; }
        let cd = p - c.xy;
        let d = sqrt(dot(cd, cd) + 36.0);                // soft radius: no sharp point at the centre
        let x = d - t * 220.0;
        let sg = 20.0 + 2.0 * t;                         // ring width: thin, softens as it spreads
        var env = exp(-x * x / (2.0 * sg * sg));
        env = env * exp(-t * 0.6) / sqrt(1.0 + d * 0.01);
        h = h + 0.28 * c.w * sin(x * 0.18) * env;
    }
    return h;
}

// Fine vertical stripes over a teal -> blue wash (only drawn when showBg = 1)
fn backdrop(p: vec2<f32>) -> vec3<f32> {
    let uv = p / u.res;
    let x = p.x + 6.0 * sin(p.y * 0.012 + u.time * 0.4);
    var stripe = 0.5 + 0.5 * sin(x * 0.42 + u.time * 0.3);
    stripe = stripe + 0.25 * (0.5 + 0.5 * sin(x * 0.17 - u.time * 0.2));
    let teal = vec3<f32>(0.27, 0.55, 0.56);
    let blue = vec3<f32>(0.16, 0.27, 0.52);
    var col = mix(teal, blue, smoothstep(0.22, 0.78, uv.x));
    col = col * (0.78 + 0.32 * stripe);
    col = col * (0.97 + 0.03 * sin(p.y * 2.0));
    return col;
}

// White-water density behind the boat. Every trail point throws two foam "particles" sideways
// (left and right of the path) that drift outward as they age, so together they draw a V of
// foam with clear water between the arms. A short-lived churn sits right behind the boat.
// The sideways drift is tied to the boat's speed, which is stored with every trail point, so
// the V opens at about the angle a real wake does.
fn foamField(p: vec2<f32>) -> f32 {
    var F = 0.0;
    for (var i: i32 = 0; i < MAXT - 1; i = i + 1) {
        let a = u.pt[i];
        if (a.z < -100.0) { break; }                         // newest first: the rest are unused too
        let t = u.time - a.z;
        let uf = t / FOAM_LIFE;
        if (uf >= 1.0) { break; }                            // and every older point has expired
        if (uf < 0.0) { continue; }
        let b = u.pt[i + 1];
        let dir = a.xy - b.xy;
        let dl = length(dir);
        if (b.z < -100.0 || dl < 0.5 || dl > 40.0) { continue; }

        // Unpack the point (see trailPt). The boat's speed when this point was laid down decides
        // whether it makes white water: only fast movement does.
        let arcF = floor(a.w);
        let code = floor((a.w - arcF) * 8192.0 + 0.5);
        let spdQ = floor(code / 128.0);
        let st = (code - spdQ * 128.0) / 127.0 * STMAX;
        let arc = arcF * 2.0;
        var stF = min(st, 1.0);                               // foam mostly ignores the press boost
        if (st > 1.0) { stF = stF + FOAM_PRESS_GAIN * (st - 1.0); }
        let boatSpeed = spdQ * 30.0;
        let fast = smoothstep(FOAM_MIN_SPEED * 0.75, FOAM_MIN_SPEED * 1.25 + 1.0, boatSpeed);
        if (fast <= 0.001) { continue; }

        let spd = clamp(boatSpeed, 300.0, 700.0);            // sets how wide the V opens
        let off = 8.0 + FOAM_SPREAD * spd * t;
        let d0 = p - a.xy;
        let reach = off + 170.0 * FOAM_ARM_WIDTH;
        if (dot(d0, d0) > reach * reach) { continue; }       // too far to matter

        let th = 1.0 + 0.40 * trailNoise(arc, 3.1);
        let wgt = min(1.0, dl / 14.0);
        let perp = vec2<f32>(-dir.y, dir.x) / dl;
        let wf = (11.0 + 20.0 * t) * th * FOAM_ARM_WIDTH;    // arms widen and soften with age
        let amp = 1.05 * fast * stF * wgt * pow(1.0 - uf, 1.2);
        let dL = p - (a.xy + perp * off);
        let dR = p - (a.xy - perp * off);
        F = F + amp * (exp(-dot(dL, dL) / (2.0 * wf * wf)) + exp(-dot(dR, dR) / (2.0 * wf * wf)));

        let lu = t / LIFE;                                    // churn right behind the boat
        if (lu < 1.0) {
            let s = (14.0 + 30.0 * pow(1.0 - lu, 0.9)) * th * 0.5;
            F = F + 0.6 * fast * stF * wgt * pow(1.0 - lu, 3.0) * exp(-dot(d0, d0) / (2.0 * s * s));
        }
    }
    return F;
}

// Ripples radiating from the trail. Each live trail point is a circle that grows with age. The
// distance to the nearest circle edge, x = |p - point| - radius, is the distance to the union of
// all circles, so overlapping circles act as one shape. The ripple is a ring packet that sits on
// that merged outline, sin(x * FREQ) under a bell curve that is wide on the outside and narrow on
// the inside. Returns the slope of the ripple height (already scaled like the click rings' slope).
// The strength is blended between nearby circles so it does not jump where two of them meet.
fn trailRipple(p: vec2<f32>) -> vec2<f32> {
    var m = 1.0e6;      // smallest distance to a circle edge so far
    var S = 0.0;        // blend weights, relative to m
    var A = 0.0;        // blended strength
    var Gx = 0.0;       // blended direction away from the nearest circle centres
    var Gy = 0.0;
    let reachExtra = 3.0 * TRAIL_RIPPLE_OUT;

    for (var i: i32 = 0; i < MAXT; i = i + 1) {
        let a = u.pt[i];
        let t = u.time - a.z;
        if (a.z < -100.0 || t >= TRAIL_RIPPLE_LIFE) { break; }   // newest first: the rest are dead too
        if (t < 0.0) { continue; }

        let R = TRAIL_RIPPLE_START + TRAIL_RIPPLE_SPEED * t;
        let dv = p - a.xy;
        let d2 = dot(dv, dv);
        let reach = R + reachExtra;
        if (d2 > reach * reach) { continue; }                // too far from this ring to matter

        let d = sqrt(d2 + 36.0);                             // soft distance: no sharp point at the centre
        let x = d - R;

        let arcF = floor(a.w);
        let code = floor((a.w - arcF) * 8192.0 + 0.5);
        let spdQ = floor(code / 128.0);
        let st = (code - spdQ * 128.0) / 127.0 * STMAX;
        // Pressed strokes make bigger ripples. Strength fades with age and eases in so the rings
        // start a little behind the boat, not right under it.
        let amp = min(st, 2.5) * pow(1.0 - t / TRAIL_RIPPLE_LIFE, 1.5) * smoothstep(0.0, 0.25, t);

        if (x < m) {
            let sc = exp(-TRAIL_RIPPLE_BLEND * (m - x));
            S = S * sc; A = A * sc; Gx = Gx * sc; Gy = Gy * sc;
            m = x;
        }
        let w = exp(-TRAIL_RIPPLE_BLEND * (x - m));
        S = S + w;
        A = A + w * amp;
        Gx = Gx + w * dv.x / d;
        Gy = Gy + w * dv.y / d;
    }
    if (S <= 0.0) { return vec2<f32>(0.0, 0.0); }

    // True smooth minimum: where two circles overlap their edges are blended into one smooth
    // curve instead of meeting at a sharp crease, so single circles stop showing through.
    let X = m - log(S) / TRAIL_RIPPLE_BLEND;
    let amp = A / S;
    let g = vec2<f32>(Gx, Gy) / S;
    var sg = TRAIL_RIPPLE_OUT;
    if (X < 0.0) { sg = TRAIL_RIPPLE_IN; }
    let env = exp(-X * X / (2.0 * sg * sg));
    let ph = X * TRAIL_RIPPLE_FREQ;
    // height = 0.28 * amp * sin(ph) * env, so its slope along the outward direction is:
    let dh = 0.28 * amp * env * (TRAIL_RIPPLE_FREQ * cos(ph) - sin(ph) * X / (sg * sg));
    return g * (dh * 24.0);
}

// Cheap value noise for the foam
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33, 33.33, 33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Smooth, round-lumped noise built from warped sines: no grid cells, so no blocky pixels.
fn onoise(p: vec2<f32>, seed: f32) -> f32 {
    let a = sin(p.x * 1.00 + 1.3 * sin(p.y * 0.83 + seed));
    let b = sin(p.y * 1.17 + 1.1 * sin(p.x * 0.71 + seed * 1.7 + 2.0));
    let c = sin((p.x + p.y) * 0.62 + 1.2 * sin((p.x - p.y) * 0.55 + seed * 0.6 + 4.0));
    return 0.5 + 0.17 * (a + b + c);
}

// Layer a colour over a premultiplied overlay with coverage k
fn blendOver(ov: vec4<f32>, c: vec3<f32>, k: f32) -> vec4<f32> {
    return vec4<f32>(c * k + ov.rgb * (1.0 - k), k + ov.a * (1.0 - k));
}

// Rotate a colour's hue (degrees) and scale its saturation
fn tint(c: vec3<f32>, hueDeg: f32, sat: f32) -> vec3<f32> {
    let ang = hueDeg * PI / 180.0;
    let ca = cos(ang);
    let sa = sin(ang);
    let ax = vec3<f32>(0.57735027, 0.57735027, 0.57735027);   // the grey axis
    let rot = c * ca + cross(ax, c) * sa + ax * dot(ax, c) * (1.0 - ca);
    let luma = dot(rot, vec3<f32>(0.299, 0.587, 0.114));
    return clamp(mix(vec3<f32>(luma, luma, luma), rot, sat), vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // Pixel position, origin top-left, in canvas pixels
    var py = in.uv.y;
    if (FLIP_Y) { py = 1.0 - in.uv.y; }
    let p = vec2<f32>(in.uv.x, py) * u.res;
    let uv = p / u.res;

    // Idle early-out: with no live trail, no boat blob, no click rings and the slosh settled,
    // every effect below works out to exactly zero (foam included, at the current FOAM_ settings),
    // so skip the heavy maths. The conditions are the same for every pixel.
    if (u.showBg < 0.5) {
        var busy = u.head.z > 0.0005;
        let a0 = u.pt[0];
        if (a0.z > -100.0 && u.time - a0.z < max(max(LIFE, WAKE_LIFE), TRAIL_RIPPLE_LIFE)) { busy = true; }
        for (var k: i32 = 0; k < MAXC; k = k + 1) {
            let tc = u.time - u.clicks[k].z;
            if (tc >= 0.0 && tc <= 6.0) { busy = true; }
        }
        let sl = abs(u.slosh);
        if (max(max(sl.x, sl.y), max(sl.z, sl.w)) > 0.01) { busy = true; }
        if (!busy) { return vec4<f32>(0.0, 0.0, 0.0, 0.0); }
    }

    let e = 2.0;
    let hdv = dragHeight3(p, e);
    let hd = hdv.x;
    let hdx = hdv.y;
    let hdy = hdv.z;
    let press = hdv.w;                                   // how hard the nearby trail was pressed
    let hc = clickHeight(p);
    let hcx = clickHeight(p + vec2<f32>(e, 0.0));
    let hcy = clickHeight(p + vec2<f32>(0.0, e));
    let gD = vec2<f32>(hdx - hd, hdy - hd) / e * 24.0 * mix(1.0, PRESS_DEPTH_SLOPE, press);   // slope from the boat's drag, steeper where pressed
    let gC = vec2<f32>(hcx - hc, hcy - hc) / e * 24.0;   // slope from the click rings
    let gR = trailRipple(p);                             // slope from the ripples around the trail

    // Whole-surface slosh: a few broad standing waves (spring-driven from the script) that
    // tilt the entire water back and forth, so the cursor moves ALL of it, a little.
    let su = uv;
    let sg = -PI * vec2<f32>(
        u.slosh.x * sin(PI * su.x) + 0.9 * u.slosh.y * sin(2.0 * PI * su.x),
        u.slosh.z * sin(PI * su.y) + 0.9 * u.slosh.w * sin(2.0 * PI * su.y));

    // Shading is built as a premultiplied overlay so it can sit on any background.
    let Ldir = normalize(vec2<f32>(-0.6, -0.8));
    let toneC = -dot(gC + sg * 0.08, Ldir);
    let toneD = -dot(gD, Ldir);
    let darkC = vec3<f32>(0.03, 0.00, 0.14);
    let lightC = vec3<f32>(0.38, 0.70, 0.68);
    let ringDark = tint(darkC, RING_HUE, RING_SAT);
    let ringLight = tint(lightC, RING_HUE, RING_SAT);
    let trailDark = tint(darkC, TRAIL_HUE, TRAIL_SAT);
    let trailLight = tint(lightC, TRAIL_HUE, TRAIL_SAT);

    // Click rings and slosh
    var ov = vec4<f32>(0.0, 0.0, 0.0, 0.0);
    ov = blendOver(ov, ringDark, smoothstep(0.05, 0.9, -toneC) * RING_DARK_OPACITY);
    ov = blendOver(ov, ringLight, smoothstep(0.05, 0.9, toneC) * RING_LIGHT_OPACITY);

    // Ripples around the trail: same colours and strength rules as the click rings
    let toneR = -dot(gR, Ldir);
    ov = blendOver(ov, ringDark, smoothstep(0.05, 0.9, -toneR) * RING_DARK_OPACITY * TRAIL_RIPPLE_OPACITY);
    ov = blendOver(ov, ringLight, smoothstep(0.05, 0.9, toneR) * RING_LIGHT_OPACITY * TRAIL_RIPPLE_OPACITY);

    // The boat's drag, eased back so it sits with the ripples (same shape, less opacity)
    let depthOp = mix(1.0, PRESS_DEPTH_OPACITY, press);   // pressed areas are darker and brighter
    ov = blendOver(ov, trailDark, smoothstep(0.05, 0.9, -toneD) * 0.92 * DRAG_DARK * depthOp);
    ov = blendOver(ov, trailLight, smoothstep(0.05, 0.9, toneD) * 0.65 * DRAG_LIGHT * depthOp);
    ov = blendOver(ov, trailDark, smoothstep(0.55, 1.0, hd) * 0.35 * DRAG_DARK * depthOp);

    // White water: stylised froth that follows the wake. Density comes from foamField(); the
    // lumps come from smooth noise that slowly churns. FOAM_SOFT sets how crisp the edges are,
    // FOAM_CEL snaps the shading into three flat tones, FOAM_GRAIN adds fine grit and spray.
    let Fd = foamField(p) * FOAM_AMOUNT;
    let sc = FOAM_SCALE;
    let fl = vec2<f32>(u.time * 0.5, -u.time * 0.35);
    let billow = onoise(p * (0.16 * sc) + fl, 2.2);
    let billow2 = onoise(p * (0.34 * sc) + vec2<f32>(3.0, 0.0) - fl * 1.4, 5.5);
    let slowN = onoise(p * (0.075 * sc) + vec2<f32>(11.0, 0.0), 3.3);
    let fine = vnoise(p * (0.6 * sc) + fl * 3.0);
    let lumpN = 0.65 * billow + 0.35 * slowN;
    let Fn = 1.0 - exp(-0.7 * Fd);
    let fval = Fn * 1.3 + FOAM_LUMP * 0.7425 * (lumpN - 0.5)
             + FOAM_GRAIN * (0.30 * (billow2 - 0.5) + 0.12 * (fine - 0.5));
    let cover = smoothstep(0.465 - FOAM_SOFT, 0.465 + FOAM_SOFT, fval);
    let inner = smoothstep(0.55, 1.25, fval);
    let q = 0.5 * (smoothstep(0.30, 0.36, inner) + smoothstep(0.62, 0.68, inner));   // three flat tones
    let tone = mix(inner, q, FOAM_CEL);
    let tex = 0.5 * billow2 + 0.5 * slowN;
    var falpha = cover * (0.55 + 0.45 * tone) * (0.80 + 0.35 * tex * (1.0 - 0.7 * FOAM_CEL));
    let speck = smoothstep(0.80, 0.90, fine) * smoothstep(0.05, 0.35, Fn) * 0.7 * FOAM_GRAIN;
    falpha = clamp(max(falpha, speck), 0.0, 0.95);
    let fcol = mix(vec3<f32>(0.66, 0.88, 0.92), vec3<f32>(0.99, 1.0, 1.0),
                   clamp(0.25 + 0.75 * tone * (0.7 + 0.5 * tex * (1.0 - 0.7 * FOAM_CEL)), 0.0, 1.0));
    ov = blendOver(ov, fcol, falpha);

    if (u.showBg > 0.5) {
        // Stripes get bent by the goo, with the dark violet vignette on the backdrop only
        var col = backdrop(p + (gD * DRAG_DISP + gC + gR * TRAIL_RIPPLE_OPACITY) * 40.0 + sg * 5.0);
        let vg = smoothstep(0.30, 0.58, length(uv - vec2<f32>(0.5, 0.5)));
        col = mix(col, vec3<f32>(0.0, 0.0, 0.03), vg);
        col = col * (1.0 - ov.a) + ov.rgb;
        return vec4<f32>(col, 1.0);
    }
    return ov;   // premultiplied alpha, nothing behind it
}
