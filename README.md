# Realtime Bytebeat Synth in C

A realtime digital synthesizer in C that:
- accepts **bytebeat equations** written as JavaScript-style expressions/program snippets,
- transpiles them to a C-style expression in realtime,
- evaluates them in a low-latency audio callback,
- includes **30 built-in famous-style bytebeat presets** you can switch instantly,
- supports smooth realtime control of pitch and tempo.

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
