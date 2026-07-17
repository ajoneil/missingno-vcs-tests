; sanity — the simplest possible self-test: it asserts no hardware behaviour and
; only exercises the result harness that every other self-test depends on.
;
; A self-test reports its verdict through a fixed convention (result.h): the ROM
; writes a RESULT byte to RAM at $80 — $00 while running, $A5 for PASS, $5A for
; FAIL — so a headless runner can read the outcome, and it also drops into a
; PASS/FAIL result screen so the same ROM is legible on a real console. That RAM
; lives in the 6532 (RIOT), the console's combined RAM, timer and I/O chip.
;
; Three macros carry the convention. CLEAN_START (from dasm's macro.h) zeroes
; RAM, the CPU registers and the decimal flag, giving a known power-on state.
; TEST_BEGIN then clears the carry and overflow flags (both undefined at
; power-on) and zeroes the RESULT/CODE/OBSERVED/EXPECTED block, leaving the
; machine fully deterministic. PASS_TEST writes $A5 to RESULT and jumps to the
; green pass screen.
;
; The test runs exactly those three steps and nothing else — begin, then pass —
; so RESULT ends at $A5 with CODE $00 whenever the harness itself is sound.
; Because the ROM makes no assertion of its own it has no FAIL codes: a $5A here
; means the begin/pass path is broken, not that any hardware behaviour diverged.
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

        org $F000

Reset:
        CLEAN_START             ; zero RAM + registers: known power-on state
        TEST_BEGIN              ; clear carry/overflow, zero the RESULT block
        PASS_TEST               ; RESULT = $A5, show the green pass screen

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
