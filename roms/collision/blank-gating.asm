; blank-gating — the collision latches watch the object serialisers on
; every colour clock: two objects that cross inside horizontal blank
; collide even though nothing is drawn, and vertical blank alone
; suppresses latching.
;
; The TIA (the console's video chip) draws the picture live as the beam
; sweeps each scanline, and carries five movable objects: two players, two
; missiles, and the ball. Whenever two of them emit a pixel on the same
; colour clock the TIA sets a sticky "collision" latch for that pair; the
; latches read back through CXM0P..CXPPMM, and a CXCLR write clears them
; all. On the TIA-1A schematic each object's serial output enters that
; latch matrix gated by exactly one signal: the inverted VBLANK bit
; (register D1). Horizontal blanking in every form — the blank that opens
; each line, the HMOVE comb, the stretched blank after a line-start HMOVE
; — cuts the video signal but not the matrix. An object whose serialiser
; fires inside horizontal blank paints nothing and still collides; games
; lean on this — Fatal Run parks a missile in the blanked columns as an
; invisible fence and reads its latch to notice road objects that have
; drifted off the visible field.
;
; Objects are clocked only across the visible beam, so a pulse inside
; horizontal blank needs the extra motion clocks of a line-start HMOVE.
; With a motion value of zero an object is still fed 8 of them early in
; the blank — they exactly replace the 8 clocks the stretched blank
; withholds, so its position holds still. A missile whose reset strobe
; landed during horizontal blank sits at the left edge with its start
; pending: on a plain line the start plays out on the first visible
; clocks, but on a line-start-HMOVE line the extra clocks consume it early
; and the missile's pulse falls around colour clocks 20-40, deep inside
; blank.
;
; The test parks missile 0 (4 clocks wide) and missile 1 (1 clock wide)
; with reset strobes on the same CPU cycle of successive lines, so their
; pulses share the same clocks, and reads the pair's latch (CXPPMM bit 6)
; once per line — a 16-line hit profile per group. Five groups walk the
; same coincidence through the regimes: visible (control), inside
; horizontal blank, deliberately apart (control), under VBLANK, and with
; VBLANK released (control). The hits must track the coincidence and the
; VBLANK bit alone, never the beam blanking.
;
;   CODE $01/$02 = group 1, lines 0-7 / 8-15 (visible control)
;        $03/$04 = group 2 — a missing hit means horizontal blank is
;                  wrongly gating the collision matrix
;        $05/$06 = group 3 (non-coincidence control)
;        $07/$08 = group 4 — a present hit means VBLANK is wrongly not
;                  gating the matrix
;        $09/$0A = group 5 (VBLANK-off control)
;
; Each group's 16-bit profile is stashed at $A0+ (two bytes per group, in
; code order) before it is asserted, so a RAM capture shows every group
; even though the verdict stops at the first mismatch.
;
; The HMOVE-comb columns pass through the same matrix gate and get no
; separate construction; group 2's deep-blank coincidence is the
; discriminating case. Expected result from the TIA-1A schematic (collision
; inputs NANDed with inverted VBLANK), verified on real hardware (PAL
; console, 2026-07-25: PASS).
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PROFILE = $90                   ; 16-bit per-line latch profile
SAVE    = $A0                   ; per-group profile stash (2 bytes per group)

GRP_N   SET 0                   ; running save-slot offset

; One 16-line measurement group. SUBROUTINE scopes the local labels.
;   {1} SLEEP before the RESM1 park strobe ({1} = {2}: the two pulses
;       coincide; different: they are clocks apart and never overlap)
;   {2} SLEEP before the RESM0 park strobe (0 = strobe in hblank ->
;       pulse at the left edge / inside blank; larger = pulse mid-screen)
;   {3} 1 = line-start HMOVE on every measurement line, 0 = plain lines
;   {4} VBLANK value during the measurement lines ($02 on, $00 off)
;   {5} expected byte0 (lines 0-7)   {6} expected byte1 (lines 8-15)
;   {7} fail code for byte0 (byte1 uses {7}+1)
    MAC GROUP
        SUBROUTINE
        ; park both missiles at the same in-line clock. The park lines run
        ; in the group's own line regime (HMOVE groups park under HMOVE,
        ; like the game fence this replicates), so the delivery phase the
        ; parks establish is the phase the measurement sees.
        sta WSYNC
        sta HMCLR               ; every HM nibble 0: stuffs move nothing
        sta WSYNC
        IF {3}
        sta HMOVE
        ENDIF
        IF {2}
        SLEEP {2}
        ENDIF
        sta RESM0
        sta WSYNC
        IF {3}
        sta HMOVE
        ENDIF
        IF {1}
        SLEEP {1}
        ENDIF
        sta RESM1
        ; eight settle lines in the group's own line regime, so the parks'
        ; delivery phase has converged before the window opens; then set
        ; VBLANK for the group and clear the latches at that line's END so
        ; nothing from the settling rides into line 0's window
        ldy #8
.settle:
        sta WSYNC
        IF {3}
        sta HMOVE
        ENDIF
        dey
        bne .settle
        sta WSYNC
        IF {3}
        sta HMOVE
        ENDIF
        lda #{4}
        sta VBLANK
        SLEEP 48
        sta CXCLR
        lda #0
        sta PROFILE
        sta PROFILE+1
        ldx #16
        ; per line: the coincidence (if any) fires by clock ~45 (blank
        ; pulses) or ~110 (mid-screen pulses); read from clock ~130, clear
        ; well before the next line's stuff train
.line:
        sta WSYNC
        IF {3}
        sta HMOVE               ; strobe lands in CPU cycles 0-2
        ENDIF
        SLEEP 40
        lda CXPPMM              ; D6 = M0-M1
        and #$40
        cmp #$40                ; carry = this line's hit
        rol PROFILE
        rol PROFILE+1           ; after 16: $91 = lines 0-7, $90 = 8-15
        sta CXCLR
        dex
        bne .line
        lda #0
        sta VBLANK              ; beam back on between groups
        ; stash for trace diagnosis, then assert
        lda PROFILE+1
        sta SAVE+GRP_N
        lda PROFILE
        sta SAVE+GRP_N+1
        ASSERT_EQ PROFILE+1, {5}, {7}
        ASSERT_EQ PROFILE,   {6}, {7}+1
GRP_N   SET GRP_N+2
    ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUP0              ; missiles white (collision is colour-blind;
        sta COLUP1              ; the picture is for eyes on real hardware)
        lda #$20
        sta NUSIZ0              ; missile 0: width 4, one copy
        lda #$00
        sta NUSIZ1              ; missile 1: width 1
        lda #$02
        sta ENAM0
        sta ENAM1

        jsr vertical_sync
        jsr vblank_lines        ; beam on; groups run as raw lines and the
                                ; verdict lands within the first frames

        ;     M1   M0  HMOVE VBL  exp0 exp1 code

        ; 1: plain lines. Both pulses fire together at the visible left
        ;    edge; every line must latch — proves the parks coincide and
        ;    the latch machinery works before anything subtler is blamed.
        GROUP 0,   0,   0,   $00, $FF, $FF, $01
        ; 2: line-start HMOVE on every line. The same coincidence now
        ;    plays out on the stuffed clocks around colour clock 20-40 —
        ;    inside blank, drawing nothing. Hardware latches every line;
        ;    a model sampling collisions only on visible clocks reads $00.
        GROUP 0,   0,   1,   $00, $FF, $FF, $03
        ; 3: as group 2 but missile 1 re-parked mid-screen: M0 pulses in
        ;    blank, M1 in the picture, never on the same clock — nothing
        ;    may latch (group 2's hits are coincidences, not blank-clock
        ;    phantoms).
        GROUP 30,  0,   1,   $00, $00, $00, $05
        ; 4: plain lines, both pulses together mid-screen, VBLANK on. The
        ;    coincidence is real but the matrix is gated: nothing may
        ;    latch. A model that keeps latching under VBLANK reads $FF.
        GROUP 30,  30,  0,   $02, $00, $00, $07
        ; 5: group 4 with VBLANK off — every line latches again.
        GROUP 30,  30,  0,   $00, $FF, $FF, $09

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
