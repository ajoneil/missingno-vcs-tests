; merge-delivery — a motion nudge merging into a player mid-line reaches
; the player's pattern scan according to the SCAN'S OWN STATE: a scan still
; on its first pattern bit takes the nudge at any step phase, a counting
; scan only on its own; the first bit is never skipped; and a reset written
; over the scan's start suppresses the start. Real PAL console, 2026-07-28.
;
; The TIA (the console's video chip) has no frame memory: it draws each
; scanline live, one pixel per "colour clock". A player object is an 8-bit
; pattern walked out by a scan that a free-running counter starts at the
; player's column every line. Writing HMOVE nudges objects sideways: for a
; short burst, an extra step arrives every fourth colour clock. In the
; visible span that step coincides with a tick of the player's own pixel
; clock and the two merge into one stretched pulse carrying TWO advances —
; and whether the second advance reaches the pattern scan is what this
; test reads out, cell by cell.
;
; Measured: a scan still delivering its FIRST pattern bit takes the second
; advance at every phase of the four-clock step cycle its circuits can
; meet a nudge on. A scan already COUNTING takes it only at the one phase
; its own stepping derives from. A second advance that would carry the
; scan off its first bit before that bit reached the screen is consumed
; instead — the first bit is never skipped. And a RESP0 write whose
; three-clock strobe spans the moment the counter starts the scan
; suppresses the start — no pixel that line. That suppression also closes
; the only route to the step cycle's fourth phase, so the phase rules
; above are measured at every phase the silicon can realise.
;
; Each leg parks the player so that one mid-line nudge pulse catches its
; scan in one named cell, with a width-one missile parked at the ONE
; column where the leg's two outcomes draw differently; the player-missile
; collision latch is the verdict bit. Geometry in the comments below.
;
;   CODE = the first leg reading wrong; OBSERVED = all seven legs as bits
;   0-6; EXPECTED = $7B, every leg colliding except leg 3:
;     1  first bit still in its delivery lead; phase 0     collide
;     2  first bit on screen; phase 2                      collide
;     3  reset strobed over the scan's start (the          NO collision
;        suppression; probes the second missile)
;     4  first bit one step from being skipped; phase 1    collide (the
;        never-skipped rule: the nudge draws a plain tick)
;     5  counting, 4th bit; phase 1 — its own phase        collide
;     6  counting, 3rd bit; phase 0                        collide
;     7  leg 3 without the reset: the plain pattern        collide
;        (aliveness control — leg 3's darkness cannot
;        pass with a dead probe or a dead scan)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

LEGS    = $90                   ; 7 cells: the masked latch byte per leg
PROFILE = $97                   ; legs packed as bits 0-6

EXPECTED_PROFILE = $7B          ; every leg collides except the reset leg

; One leg, four lines. {1} park walk value, {2} pulse count value for the
; measured line, {3}/{4} collision register and mask, {5} 1 = the mid-scan
; RESP0 (leg 3), {6} the leg's LEGS cell.
;
; Geometry (colour clocks, WSYNC-anchored). The player parks at base
; column 78 (RESP0 write ending clock 141), then one line-start HMOVE
; walks it: its stretched blanking shifts every object 8 right and each
; blank-time pulse steps 1 back left. The measured line's HMOVE write ends
; clock 138; its first stuff pulse lands at clock 145, and a delivered
; second advance first draws at the NEXT clock — so each leg's verdict
; column is fixed by the pulse slot, not the park. The scan starts at
; clock (park column + 65); the park walks the start across the pulse to
; select the leg's cell. The probes carry eight-pulse values ($00) across
; the nudge line (eight steps cancel its 8-clock shift) and zero-pulse
; values ($80) across the measured line: they never move. Every strobe is
; a fixed straight-line run off a fresh WSYNC (leg variants are assembled,
; not branched).
    MAC DOLEG
        ; park line: replant the player, arm this leg's walk
        sta WSYNC
        SLEEP 44
        sta RESP0               ; write ends clock 141 -> base column 78
        lda #{1}
        sta HMP0
        lda #$00
        sta HMM0
        sta HMM1
        ; nudge line: the line-start HMOVE walks the park; then the motion
        ; registers are set for the measured line
        sta WSYNC
        sta HMOVE
        SLEEP 30
        sta HMCLR               ; the walk's burst is long over
        lda #{2}
        sta HMP0
        lda #$80
        sta HMM0
        sta HMM1
        ; measured line: scrub the latches while still blanked, then the
        ; mid-line HMOVE under test
        sta WSYNC
        sta CXCLR
        SLEEP 40
        sta HMOVE               ; write ends clock 138 -> pulse at clock 145
        IF {5}
        sta RESP0               ; write ends clock 147: the strobe level
                                ; spans the scan start at clock 146
        ENDIF
        ; read line: one line's collision, in the leaving hblank
        sta WSYNC
        lda {3}
        and #{4}
        sta {6}
    ENDM

        org $F000

Reset:
        ; Not CLEAN_START: a ~2600-cycle clear loop walks every strobe below
        ; onto one global-clock phase and can mask a phase-dependent landing
        ; fault (see reset-phase). Short straight-line init of what is used.
        sei
        cld
        ldx #$FF
        txs
        lda #$00
        sta VBLANK
        sta COLUBK
        sta CTRLPF
        sta PF0
        sta PF1
        sta PF2
        sta NUSIZ0              ; missile 0 width 1, one player copy
        sta NUSIZ1
        sta GRP1
        sta ENABL
        sta VDELP0
        sta VDELBL
        sta REFP0
        sta HMCLR
        sta PROFILE
        lda #$02
        sta ENAM0               ; both probes on
        sta ENAM1
        lda #$B4
        sta GRP0                ; %10110100 — pattern bits 1-6 read lit,
                                ; dark, lit, lit, dark, lit: every leg's
                                ; verdict column flips between its two
                                ; renderings (per-leg needs at the legs)
        lda #$0E
        sta COLUP0              ; cosmetic; the collision matrix ignores colour
        sta COLUP1
        TEST_BEGIN

        jsr vertical_sync
        jsr vblank_lines        ; beam on; collisions latch in the visible field

        ; ---- park the probes: M0 at column 78, M1 at 83 -------------------
        ; (missile base column = reset write end + 4 - 68; one line-start
        ; HMOVE applies both walks, +8 blank shift less one per pulse)
        sta WSYNC
        SLEEP 44
        sta RESM0               ; write ends clock 141 -> base column 77
        lda #$F0
        sta HMM0                ; 7 pulses -> 78 = the clock after the pulse
        sta WSYNC
        SLEEP 45
        sta RESM1               ; write ends clock 144 -> base column 80
        lda #$D0
        sta HMM1                ; 5 pulses -> 83 = leg 3/7's third bit
        sta WSYNC
        sta HMOVE               ; line-start nudge applies both walks
        SLEEP 30
        sta HMCLR
        lda #$80
        sta HMM0                ; zero-pulse values from here on: the probes
        sta HMM1                ; never move again
        sta HMP0

        ; ---- the seven legs -----------------------------------------------
        ; leg  park  scan start  cell at the pulse    verdict col 78 shows
        ;  1    79      144      delivery lead, ph 0  bit 1 early / dark lead
        ;  2    77      142      first bit, ph 2      bit 3 / dark bit 2
        ;  4    78      143      last lead step, ph 1 bit 1 kept / dark bit 2
        ;  5    74      139      4th bit, ph 1        bit 6 early / dark bit 5
        ;  6    75      140      3rd bit, ph 0        bit 4 / dark bit 5
        ; legs 3 and 7 stuff nothing and read column 83 (the pattern's
        ; third bit) through the second missile: lit unless leg 3's RESP0,
        ; strobed across the scan start at 146, suppressed the whole scan
leg1:   DOLEG $F0, $90, CXM0P, $40, 0, LEGS+0
leg2:   DOLEG $10, $90, CXM0P, $40, 0, LEGS+1
leg3:   DOLEG $D0, $80, CXM1P, $80, 1, LEGS+2
leg4:   DOLEG $00, $90, CXM0P, $40, 0, LEGS+3
leg5:   DOLEG $40, $90, CXM0P, $40, 0, LEGS+4
leg6:   DOLEG $30, $90, CXM0P, $40, 0, LEGS+5
leg7:   DOLEG $D0, $80, CXM1P, $80, 0, LEGS+6

        ; ---- verdict ------------------------------------------------------
        ; pack the legs into PROFILE bits 0-6
        ldx #6
.pack:
        lda LEGS,x
        beq .clear
        lda PROFILE
        ora BitTab,x
        sta PROFILE
.clear:
        dex
        bpl .pack
        lda PROFILE
        cmp #EXPECTED_PROFILE
        beq .pass
        ; CODE = the first leg differing from the expected profile
        ldx #0
.find:
        lda PROFILE
        eor #EXPECTED_PROFILE
        and BitTab,x
        bne .found
        inx
        bne .find
.found:
        inx                     ; 1-based leg number
        stx CODE
        lda PROFILE
        sta OBSERVED
        lda #EXPECTED_PROFILE
        sta EXPECTED
        jmp fail_result
.pass:
        PASS_TEST

BitTab:
        .byte $01,$02,$04,$08,$10,$20,$40

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
