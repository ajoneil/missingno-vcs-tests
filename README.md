# missingno-vcs-tests

A hardware-accuracy test suite for the Atari 2600 (VCS) covering
the TIA (rendering, cycle-exact timing, collisions), the RIOT (timer, RAM,
I/O ports), cartridge bankswitching, and NTSC/PAL/SECAM regional behaviour.
One behaviour per test, specified in the test's header. Developed alongside
[missingno](https://github.com/ajoneil/missingno)'s VCS core; prebuilt
binaries are available
[in that repository](https://github.com/ajoneil/missingno/tree/main/crates/missingno-vcs/tests/accuracy/roms).

Verified on real hardware (an Australian PAL all-black unit, July 2026);
where sources disagreed, the console decided. The cartridge tests are the
exception — they need mapper hardware a flashcart lacks — and contested
cartridge behaviour is marked "untested on hardware" in its header.

The 6507's instruction-level behaviour is out of scope (covered by
[SingleStepTests](https://github.com/SingleStepTests/65x02)); the `cpu/` tests
cover only Atari-specific bus quirks — the floating bus, read/modify/write to
strobe registers, and stack/TIA address aliasing.

## How a test works

Each test is one of two kinds:

- **Self-test** — the ROM computes its own verdict, writes it to a fixed block
  of RAM, and also draws a PASS/FAIL screen so the result is legible on a real
  console. The RAM convention (`include/result.h`):

  | Address | Meaning |
  |---|---|
  | `$80` RESULT | `$00` running → `$A5` PASS / `$5A` FAIL |
  | `$81` CODE | which sub-check failed (`$00` on pass) |
  | `$82` / `$83` OBSERVED / EXPECTED | the mismatched values |

  A self-test stops at its first failing check. CODE/OBSERVED/EXPECTED are
  hexadecimal, and each test's header tabulates its codes.

- **Screenshot test** — a test with an accompanying `_<region>.png` is verified
  by comparing a rendered frame against that reference image, pixel-exact. A
  reference covers every scanline after the three VSYNC lines — 160×259 NTSC,
  160×309 PAL/SECAM — one pixel per colour clock of the visible line. The
  references are missingno's renders; the `*_pal_capture.png` files alongside
  are the real console's captures (stacked stills off the RF output), with
  which missingno's behaviour has been aligned.

Every `.asm` file opens with a header that fully specifies the behaviour under
test: the hardware mechanism, the exact expected result, and how a wrong
implementation shows up.

## Build

Requires `dasm` with the standard Atari 2600 includes (`vcs.h` / `macro.h`,
expected at `/usr/include/dasm/atari2600`), and Python 3 for the three
Supercharger tests (their assembled RAM images are wrapped into loadable
"fastload" `.a26` files by `scripts/build_ar.py`, the only script here).

```
make          # assemble every roms/<subsystem>/*.asm to _ntsc / _pal / _secam .a26
make clean
```

Each source builds one binary per TV standard: an NTSC 262-line field and PAL and
SECAM 312-line fields (`-DPAL` / `-DSECAM` select the line counts, and the
result-screen palette). Self-test verdicts are region-independent, but every
binary renders a true frame of its own shape. SECAM shares PAL's 50 Hz line
geometry but has no hue — its 8 colours are driven by the luminance nibble alone
— so the on-screen result colours are chosen on distinct luminance steps to stay
legible there too (see `include/region.h`).

## Run

To check an emulator against the suite, build the ROMs, load one, and inspect
its result: for a self-test, read the RESULT byte at `$80` (`$A5` PASS / `$5A`
FAIL), or read the green/red screen and its hex digits by eye; for a screenshot
test, compare the rendered frame against the matching `_<region>.png`.

## Layout

Tests are filed by subsystem:

```
roms/cpu/         Atari-specific 6507 bus behaviour (floating bus, RMW-to-TIA, stack aliasing)
roms/riot/        timer and divisors, RAM, I/O ports, PA7 edge, address mirroring
roms/tia-render/  the static picture: playfield, players, missiles, ball, colour, priority, NUSIZ
roms/tia-timing/  racing the beam: WSYNC, mid-line writes, HMOVE, RSYNC (cycle-exact)
roms/collision/   TIA collision latches
roms/cartridge/   bankswitching across two dozen mapper families, the DPC coprocessor, the Supercharger, cartridge RAM
roms/harness/     sanity (proves the RESULT convention) and calibration (the capture-rig target)

include/          result.h + result_screen.asm (RESULT convention), frame.asm, region.h
scripts/          build_ar.py — wraps the Supercharger tests into loadable fastload images
```

## A note on initialisation

Every ROM starts with dasm's `CLEAN_START`, whose stack wipe passes through the
TIA mirror at `$0100–$017F` and so strobes several TIA registers (RSYNC twice
among them) before the kernel runs. This is intended and hardware-real, but an
emulator without full TIA address-mirror decoding, or with an RSYNC timing
quirk, will diverge during init and shift whole frames. If the first frames look
scrambled or shifted, check the mirror decode and RSYNC before suspecting the
kernel.

## Thanks

To [James Villarreal (ArkoSammy12)](https://github.com/ArkoSammy12) and
[Dennis Munsie (munsie)](https://github.com/munsie) for testing the suite
and for their feedback.

## Development

Claude (Fable 5, Opus 4.8-5) was used extensively in the development of this
suite.

## License

MIT — see [LICENSE](LICENSE).
