; rmw-strobe — a read-modify-write to a TIA strobe register fires it TWICE.
;
; A TIA strobe is a write-only register that performs an action the instant it
; is written; the value written does not matter, only that a write happens.
; RESM0 is one such strobe: writing it snaps missile 0's horizontal position to
; wherever the electron beam is at that moment ("reset missile 0"). RESM1 does
; the same for missile 1.
;
; A 6507 read-modify-write instruction (DEC, INC, ASL, ...) touches its target
; three times: it reads the byte, writes the old value straight back unchanged
; (a "dummy" write the CPU emits before it has computed the new value), then on
; the next cycle writes the real new value. Two bus writes, one CPU cycle apart.
; Aimed at a strobe, both writes fire it — so `dec RESM0` strobes RESM0 twice,
; on consecutive cycles. Because the strobe latches the beam position each time,
; the missile ends up where the SECOND (final) write fires: one CPU cycle — that
; is, 3 colour clocks, since the CPU clock is the TIA colour clock divided by 3
; — later than the dummy write, and so one cycle later than a model that strobed
; only once (on the dummy write) would place it.
;
; The test pins missile 0 once with `dec RESM0`, then sweeps a reference missile
; across the final-write column in 1-cycle steps. Two 1-pixel missiles collide
; only when they land on the same colour clock, so exactly one step — the one
; matching the final write — may report an M0-M1 collision. Strobing on the dummy
; write instead, strobing only once, or not strobing at all lands missile 0 on a
; different column and moves the hit off that step.
;
;   CODE $01 = the M0-M1 hit is not pinned to the final-write column: the sweep
;              collided at the wrong step, at more than one step, or at none
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PROFILE = $90                   ; zero-page scratch: the 5-bit swept collision profile

; probe one sweep step: place the reference missile 1 at {1} cycles into the
; line, test whether it collided with missile 0, and shift that bit into the
; profile — branchless (carry -> rol), so the sweep needs no per-step labels
        MAC PROBE_AT
        sta WSYNC               ; align to a fresh scanline
        SLEEP {1}               ; burn {1} CPU cycles into the line
        sta RESM1               ; strobe: land missile 1 at this column
        sta CXCLR               ; clear all collision latches
        jsr latch               ; hold a couple of lines so the overlap latches
        lda CXPPMM              ; CXPPMM = player/missile collision latches
        and #$40                ; isolate bit 6 = missile 0 hit missile 1
        cmp #$40                ; C = 1 if they collided, else 0
        rol PROFILE             ; shift that verdict bit into the profile
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$42
        sta COLUP0              ; missile 0 colour (from its player's COLUP0)
        lda #$C4
        sta COLUP1              ; missile 1 colour
        lda #$02
        sta ENAM0
        sta ENAM1               ; enable both missiles; width 1 (NUSIZ = 0)

        jsr vertical_sync
        jsr vblank_lines        ; beam on for the visible section

        ; pin missile 0 ONCE with a read-modify-write to RESM0: it strobes twice
        ; and the second (final) write latches the position. Fixed for the sweep.
        sta WSYNC               ; align to a fresh scanline
        SLEEP 20                ; burn 20 cycles; dec's final write = the SLEEP-22 column
        dec RESM0               ; double strobe -> missile 0 at the final-write column

        lda #0
        sta PROFILE             ; profile = 00000
        ; sweep the reference missile across the final-write column, +/-2 cycles
        ; (3px per step); only the centre step (SLEEP 22) can land on missile 0
        PROBE_AT 20             ; -2 cycles: no hit
        PROBE_AT 21             ; -1 cycle:  no hit
        PROBE_AT 22             ; centre = missile 0's final-write column: HIT
        PROBE_AT 23             ; +1 cycle:  no hit
        PROBE_AT 24             ; +2 cycles: no hit
        ASSERT_EQ PROFILE, $04, $01     ; require 00100 — collide at centre only

        PASS_TEST

; latch: hold two beam-on lines so a static overlap registers in the collision
; latches before we read them. Clobbers X.
latch:
        ldx #2
.ll:
        sta WSYNC
        dex
        bne .ll
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
