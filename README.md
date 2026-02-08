# NORA Bytebeat Synth

Number-Operated Real-time Audio (NORA) is a real-time bytebeat synthesizer in C that:
- Accepts bytebeat equations written as short JavaScript-style expressions, transpiles them to a C-style expression in realtime, then evaluates them in a low-latency audio callback.
- Includes 30 built-in bytebeat presets (based on well known examples) that you can switch between instantly.
- Offers smooth and direct, real-time control of pitch, tempo, and (up to) four other bytebeat equation variables.

There's a short video demo [HERE](https://youtu.be/1mU3bytRPes) and you can download a Mac build (tested on Mac OS 13.7.8) [HERE](https://github.com/maetyu-d/NORA/releases), or follow the build instructions below.

## Build (macOS)

```bash
make
```

## Run

```bash
./bytebeat_synth
```

## GUI App (native macOS)

Build and run:

```bash
make
./bytebeat_synth_gui
```

## macOS .app Bundle

Build a double-clickable Mac app:

```bash
make app
open "NORA_ByteBeat_Synthesizer.app"
```

GUI features:
- Realtime equation editor with Apply button
- 30 built-in presets via dropdown + Prev/Next
- Smooth realtime Pitch slider (-24..+24 semitones)
- Smooth realtime Tempo slider (0.05x..8x)
- Macro sliders run in fine-control integer ranges (`a..d`: `-16..16`, `sh`: `0..12`, `mask`: `0..127`)
- Live macro bar visualization + waveform preview while you move controls
- Live status of current preset/custom equation
- Equation Macro Map is built into the main UI as a colorized equation pane

## Commands

- `eq <js>`: set equation (expression or `return ...;` snippet)
- `a <value>`, `b <value>`, `c <value>`, `d <value>`: set macro params
- `sh <value>`: set bit-shift macro (quantized to integer)
- `mask <value>`: set bitmask macro (quantized to integer)
- `pl`: list built-in presets
- `ps <index>`: switch preset by index (1..30)
- `pn`: next preset
- `pp`: previous preset
- `p <semitones>`: set pitch shift (smoothly slews to target)
- `tm <multiplier>`: set tempo multiplier (smoothly slews to target)
- `s`: show current controls
- `h`: help
- `q`: quit

## Examples

```text
pl
ps 3
pn
pp
eq (t*(t>>sh|t>>(sh+3)))>>(t>>16)
eq ((t*a)&(t>>c))|((t*b)&(t>>d))
eq (t*(a&(t>>sh)))&mask
a 9
b 5
c 7
d 11
sh 8
mask 127
eq return (t*5&t>>7)|(t*3&t>>10);
p 7
tm 0.8
```

## Notes

- JS `Math.` prefixes are stripped automatically (`Math.sin` -> `sin`).
- `>>>` (unsigned shift) is supported by the evaluator.
- Supported realtime variables: `t, a, b, c, d, sh, mask`.
- The transpiler focuses on bytebeat-oriented expression syntax (not full JavaScript semantics).
