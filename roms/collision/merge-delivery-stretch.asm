; merge-delivery-stretch — a lone motion nudge merging into a
; double-width player mid-line is taken or refused by WHICH pattern bit
; is starting: the start lead and every second bit take it, at either
; grid alignment; the other bits refuse it, even on their own. Real PAL
; console, 2026-07-29.
;
; The TIA (the console's video chip) draws each scanline live, one pixel
; per "colour clock". A player object is an 8-bit pattern walked out by a
; scan a free-running counter starts at the player's column every line;
; at double width (NUSIZ $05) each pattern bit spans two clocks, led in
; by a two-step start lead and a one-clock pacing lag. Writing HMOVE
; nudges objects sideways: for a short burst an extra step arrives every
; fourth clock, and in the visible span it merges with the player's own
; pixel clock into one stretched pulse carrying TWO advances.
;
; Whether the second advance reaches the pattern scan is what this test
; reads out, for a lone pulse (a pulse inside a longer burst obeys the
; same rule, held by merge-delivery-train along with the grid-gated
; bits past the third):
;
;   * in the start lead it is taken, and the following tick is swallowed
;     — the first bit draws a clock early and a clock wider;
;   * on the second, fourth, ... bits' first clocks it is taken — at the
;     bit's natural grid alignment and at a re-grounded one alike — and
;     the bit's second clock is skipped;
;   * on the first, third, ... bits' first clocks it is REFUSED, and the
;     pattern draws as if plainly ticked.
;
;   (the nudge grid repeats every four clocks and the bits every two, so
;   consecutive bits' first clocks naturally sit on opposite alignments)
;
; Each leg parks the player so that one mid-line pulse catches a named
; cell, and reads two width-one missile probes through the collision
; latches: probe A at the column where taken and refused draw
; differently, probe B further along. Leg 1 is the control pair.
; Geometry in the comments below.
;
;   CODE $01-$06 = probe A of legs 1-6 read wrong (OBSERVED = all six A
;   bits, EXPECTED = $3E); $07-$0C = probe B of leg CODE-6 (vs $3B):
;     1  control (no pulse)          A dark and B lit, whatever happens
;     2  start lead's last step      A: first bit early   B: swallowed
;     3  1st bit's 1st clock         A: 2nd clock kept    B: dark
;     4  2nd bit's 1st clock         A: 3rd bit early     B: lit
;     5  3rd bit's 1st clock         A: 2nd clock kept    B: tail in place
;     6  leg 4's cell on the         A: lead fire         B: 3rd bit early
;        re-grounded alignment
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

ARES    = $90                   ; 6 cells: probe A masked latch per leg
BRES    = $96                   ; 6 cells: probe B
APROF   = $9C
BPROF   = $9D

A_EXPECTED = $3E
B_EXPECTED = $3B

; One leg, six lines. {1} player walk, {2} GRP0, {3} probe A walk, {4}
; probe B walk, {5} measured-line pulse value, {6} 1 = the mid-scan RESP0
; (leg 6), {7}/{8} the leg's ARES/BRES cells.
;
; Geometry (colour clocks, WSYNC-anchored): the player parks at base
; column 79 (RESP0 write ending clock 141), walked per leg by the one
; HMOVE nudge line; its scan starts at clock (park column + 64). The
; measured line's HMOVE write ends clock 138 and its first stuff pulse
; lands at clock 145; leg 6 arms two pulses and uses the second, at 149,
; with a mid-scan RESP0 ending clock 147 re-grounding the grid after the
; scan's start at 143. A taken advance first draws at the clock after its
; pulse. The probes park off RESM0/RESM1 (write ends 141/144, base
; columns 77/80) and carry zero-pulse nudge values through the measured
; line. CXCLR scrubs the parking traffic in the measured line's entering
; hblank; the latches are read in the hblank after it. Every strobe is a
; fixed straight-line run off a fresh WSYNC (leg variants are assembled,
; not branched).
    MAC DOLEG
        ; probe park lines: A (missile 0) and B (missile 1)
        sta WSYNC
        SLEEP 44
        sta RESM0               ; write ends clock 141 -> base column 77
        lda #{3}
        sta HMM0
        sta WSYNC
        SLEEP 45
        sta RESM1               ; write ends clock 144 -> base column 80
        lda #{4}
        sta HMM1
        ; player park line
        sta WSYNC
        SLEEP 44
        sta RESP0               ; write ends clock 141 -> base column 79
        lda #{1}
        sta HMP0
        lda #{2}
        sta GRP0
        ; nudge line: one line-start HMOVE walks player and probes; then
        ; the motion registers are set for the measured line
        sta WSYNC
        sta HMOVE
        SLEEP 30
        sta HMCLR
        lda #{5}
        sta HMP0
        lda #$80
        sta HMM0
        sta HMM1
        ; measured line
        sta WSYNC
        sta CXCLR
        SLEEP 40
        sta HMOVE               ; write ends clock 138 -> pulse at clock 145
        IF {6}
        sta RESP0               ; write ends clock 147: re-grounds the grid
                                ; mid-scan, ahead of the 149 pulse
        ENDIF
        ; read line
        sta WSYNC
        lda CXM0P
        and #$40
        sta {7}
        lda CXM1P
        and #$80
        sta {8}
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
        sta NUSIZ1
        sta GRP1
        sta ENABL
        sta VDELP0
        sta VDELBL
        sta REFP0
        sta HMCLR
        sta APROF
        sta BPROF
        lda #$05
        sta NUSIZ0              ; double-width player; missile 0 width 1
        lda #$02
        sta ENAM0               ; both probes on
        sta ENAM1
        lda #$0E
        sta COLUP0              ; cosmetic; the collision matrix ignores colour
        sta COLUP1
        TEST_BEGIN

        jsr vertical_sync
        jsr vblank_lines        ; beam on; collisions latch in the visible field

        ; leg  park  scan start  pulse catches            probe A  probe B
        ;  1    77      141      (no pulse)                  85       78
        ;  2    79      143      145: start lead's last      78       80
        ;  3    77      141      145: 1st bit's 1st clock    78       80
        ;  4    75      139      145: 2nd bit's 1st clock    78       80
        ;  5    73      137      145: 3rd bit's 1st clock    78       84
        ;  6    79      143      149: 2nd bit's 1st clock,   78       82
        ;                        grid re-grounded (the 145
        ;                        pulse takes the lead, as
        ;                        leg 2, leaving the walk
        ;                        one clock ahead)
        ;
        ; patterns: $B4 (%10110100) flips legs 2/3's columns. $A4
        ; (%10100100) darkens the FOURTH pattern bit: leg 5's refusal reads
        ; as the lit third bit's second clock, where a taken advance would
        ; put the dark fourth bit — under $B4 both are lit and the cell
        ; could not flip. Legs 4/6 read the lit third bit arriving a clock
        ; early against the dark second, true under either pattern.
leg1:   DOLEG $20, $B4, $80, $20, $80, 0, ARES+0, BRES+0
leg2:   DOLEG $00, $B4, $F0, $00, $90, 0, ARES+1, BRES+1
leg3:   DOLEG $20, $B4, $F0, $00, $90, 0, ARES+2, BRES+2
leg4:   DOLEG $40, $A4, $F0, $00, $90, 0, ARES+3, BRES+3
leg5:   DOLEG $60, $A4, $F0, $C0, $90, 0, ARES+4, BRES+4
leg6:   DOLEG $00, $A4, $F0, $E0, $A0, 1, ARES+5, BRES+5

        ; ---- verdict ------------------------------------------------------
        ; pack the legs into the two profiles, bits 0-5
        ldx #5
.pack:
        lda ARES,x
        beq .b
        lda APROF
        ora BitTab,x
        sta APROF
.b:
        lda BRES,x
        beq .next
        lda BPROF
        ora BitTab,x
        sta BPROF
.next:
        dex
        bpl .pack
        lda APROF
        cmp #A_EXPECTED
        bne .afail
        lda BPROF
        cmp #B_EXPECTED
        beq .pass
        ; CODE = 6 + the first probe-B leg differing from expectation
        lda #6
        sta CODE
        lda BPROF
        ldx #B_EXPECTED
        bne .find               ; X is never zero: always taken
.afail: ; CODE = the first probe-A leg differing from expectation
        lda #0
        sta CODE
        lda APROF
        ldx #A_EXPECTED
.find:
        sta OBSERVED
        stx EXPECTED
        txa
        eor OBSERVED            ; the disagreeing bits
        tay
        ldx #0
.bit:
        tya
        and BitTab,x
        bne .found
        inx
        bne .bit
.found:
        txa
        sec
        adc CODE                ; leg number (+6 on the B side; carry adds 1)
        sta CODE
        jmp fail_result
.pass:
        PASS_TEST

BitTab:
        .byte $01,$02,$04,$08,$10,$20

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
