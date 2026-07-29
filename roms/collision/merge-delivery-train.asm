; merge-delivery-train — a double-width player's pattern scan takes a
; merged motion nudge by the same state rule whether the pulse is alone
; or deep inside a pulse train: the train carries no memory. From the
; fourth pattern bit on, delivery follows the nudge grid's own alignment
; instead. Real PAL console, 2026-07-29.
;
; The TIA (the console's video chip) draws each scanline live, one pixel
; per "colour clock". At double width (NUSIZ $05) a player's 8-bit
; pattern is walked out two clocks per bit by a scan its free-running
; counter starts each line. Writing HMOVE nudges objects: during a burst
; an extra step rides every fourth clock, merging in the visible span
; with the player's own pixel clock into one stretched pulse carrying
; TWO advances. A jammed burst (hmove-stuck-latch) makes the train
; endless; whether each pulse's second advance reaches the scan is what
; this test pins, cell by cell:
;
;   * within the first three pattern bits the SCAN decides — the second
;     bit's first clock takes the advance, the first and third bits'
;     first clocks refuse it — the same at every grid alignment, for a
;     lone pulse and for a pulse with a full train behind it alike
;     (merge-delivery-stretch holds the lone-pulse cells; this test
;     holds the train's, plus the boundary below);
;   * from the fourth bit on the GRID decides: the advance lands only on
;     the alignment the doubled stepping derives from — measured on a
;     scan's very first pulse, so the gate owes nothing to pulse history;
;   * a taken advance always swallows the following tick.
;
; Each leg parks the player so a named cell meets a pulse — legs 3-5
; inside a jammed train, leg 2 a lone first pulse — and reads width-one
; probes through the collision latches at the columns where taken and
; refused draw differently. Leg 1 is the no-motion control pair.
;
;   CODE $01-$07 = probe bits 1-7 wrong (OBSERVED = all seven, EXPECTED
;   = $7F); $08-$09 = control pair wrong (OBSERVED = both, EXPECTED $02):
;     1  4th bit's 1st clock, lone FIRST pulse, its own alignment:
;        the grid gate fires past the scan rule's reach     collide
;     2  train row: start lead's last step                  collide
;     3  train row: 2nd bit's 1st clock (the scan rule,     collide
;        train context — fires exactly as a lone pulse)
;     4  train row: 4th bit's 1st clock, off-alignment      collide
;        (silent: the plain pattern pixel shows)
;     5  train row, next alignment class: 1st bit's 1st     collide
;        clock (refused: the pattern's own pixel shows)
;     6  train row, walked park: 4th bit off-alignment      collide
;        (silent: the pattern's own pixel shows)
;     7  same row: 2nd bit's 1st clock fired               collide
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

P1      = $90                   ; probe cells 1-7
C0      = $97                   ; control dark
C1      = $98                   ; control lit
PROF    = $99

A_EXPECTED = $7F

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
        sta CTRLPF              ; ball width 1
        sta PF0
        sta PF1
        sta PF2
        sta NUSIZ1
        sta GRP1
        sta ENABL
        sta VDELP0
        sta VDELP1
        sta VDELBL
        sta REFP0
        sta REFP1
        sta RESMP0
        sta RESMP1
        sta HMCLR
        sta HMP1
        sta PROF
        lda #$05
        sta NUSIZ0              ; double-width player; missiles width 1
        lda #$B4
        sta GRP0                ; %10110100: every leg's verdict column flips
        lda #$02
        sta ENAM0
        sta ENAM1
        sta ENABL
        lda #$0E
        sta COLUP0              ; cosmetic; the collision matrix ignores colour
        sta COLUP1
        sta COLUPF
        TEST_BEGIN

        jsr vertical_sync
        jsr vblank_lines        ; beam on; collisions latch in the visible field

        ; ---- leg 1: control, NO motion anywhere ---------------------------
        ; park cycle 55 puts the pattern at x=[103..119): M0 at 101 sits
        ; two clear of it (dark), M1 at 104 on the first bit (lit)
        sta WSYNC
        SLEEP 52
        sta RESM0               ; write ends clock 165 -> column 101
        sta WSYNC
        SLEEP 53
        sta RESM1               ; write ends clock 168 -> column 104
        sta WSYNC
        SLEEP 52
        sta RESP0               ; write cycle 55
        sta WSYNC
        sta CXCLR
        sta WSYNC
        lda CXM0P
        and #$40
        sta C0
        lda CXM1P
        and #$80
        sta C1

        ; ---- leg 2 (probe 1): 4th bit's 1st clock, lone first pulse -------
        ; plant-138 park base 76 walked to 69; scan start 133; the single
        ; pulse at 145 = start+12 meets the 4th bit's first clock on its
        ; own alignment; fired -> the 6th bit draws a clock early at 78
        sta WSYNC
        SLEEP 44
        sta RESM0               ; ends 141 -> base 77
        lda #$F0
        sta HMM0                ; -> 78
        sta WSYNC
        SLEEP 45
        sta RESM1               ; ends 144 -> base 80
        lda #$00
        sta HMM1                ; -> 80 (swallow side: lit either way)
        sta WSYNC
        SLEEP 43
        sta RESP0               ; ends clock 138
        lda #$70
        sta HMP0
        sta WSYNC
        sta HMOVE
        SLEEP 30
        sta HMCLR
        lda #$90
        sta HMP0                ; one pulse at clock 145
        lda #$80
        sta HMM0
        sta HMM1
        sta WSYNC
        sta CXCLR
        SLEEP 40
        sta HMOVE               ; write ends clock 138
        sta WSYNC
        lda CXM0P
        and #$40
        sta P1+0
        lda #$80
        sta HMP0

        ; ---- legs 3-5 (probes 2-4 + 5): one jammed-train pass -------------
        ; the stuck-stretch construction (park cycle 55, jam 3/19); probes
        ; parked ahead, latches retired before the train: the first
        ; post-jam row carries the lead cell at 78, the 2nd bit's first
        ; clock at 82, the 4th bit off-alignment at 86; two rows later the
        ; next class's 1st-bit cell sits at 46
        sta WSYNC
        SLEEP 44
        sta RESM0               ; ends 141 -> base 77
        lda #$70
        sta HMM0                ; -> 78
        sta WSYNC
        SLEEP 45
        sta RESM1               ; ends 144 -> base 80
        lda #$60
        sta HMM1                ; -> 82
        sta WSYNC
        SLEEP 46
        sta RESBL               ; ends 147 -> base 83
        lda #$50
        sta HMBL                ; -> 86
        sta WSYNC
        sta HMOVE               ; positioning nudge; probes retire in-burst
        SLEEP 30
        lda #$80
        sta HMM0
        sta HMM1
        sta HMBL
        sta HMP0
        sta WSYNC
        lda #$05
        sta NUSIZ0
        lda #$70
        sta HMP0
        sta WSYNC
        SLEEP 52
        sta RESP0               ; write cycle 55
        sta WSYNC
        sta HMOVE               ; write cycle 3
        lda #$00
        SLEEP 11
        sta HMP0                ; write cycle 19: the train runs
        sta WSYNC
        sta CXCLR               ; measured row 1: the ring-1 drift row
        sta WSYNC
        lda CXM0P
        and #$40
        sta P1+1
        lda CXM1P
        and #$80
        sta P1+2
        lda CXP0FB
        and #$40
        sta P1+3
        lda #$80
        sta HMP0                ; free the train

        ; ---- leg 5 (probe 5): fresh pass, the ring-3 row's col 46 ---------
        sta WSYNC
        SLEEP 33
        sta RESM0               ; ends 108 -> base 44
        lda #$60
        sta HMM0                ; -> 46
        sta WSYNC
        SLEEP 45
        sta RESM1               ; ends 144 -> base 80
        lda #$80
        sta HMM1                ; parked clear at 96
        sta WSYNC
        sta HMOVE
        SLEEP 30
        lda #$80
        sta HMM0
        sta HMM1
        sta HMP0
        sta WSYNC
        lda #$05
        sta NUSIZ0
        lda #$70
        sta HMP0
        sta WSYNC
        SLEEP 52
        sta RESP0               ; write cycle 55
        sta WSYNC
        sta HMOVE               ; write cycle 3
        lda #$00
        SLEEP 11
        sta HMP0
        sta WSYNC               ; drift row 1
        sta WSYNC               ; drift row 2
        sta WSYNC
        sta CXCLR               ; measured: the ring-3 row (two after jam)
        sta WSYNC
        lda CXM0P
        and #$40
        sta P1+4
        lda #$80
        sta HMP0

        ; ---- legs 6-7 (probes 6-7): the walked-park train row -------------
        ; park walked $B0, spacer row, then the measured row holds the
        ; 4th-bit-off-alignment cell at 50 and the fired 2nd-bit cell at 46
        sta WSYNC
        SLEEP 33
        sta RESM0               ; ends 108 -> base 44
        lda #$20
        sta HMM0                ; -> 50
        sta WSYNC
        SLEEP 32
        sta RESM1               ; ends 105 -> base 41
        lda #$30
        sta HMM1                ; -> 46
        sta WSYNC
        SLEEP 44
        sta RESP0               ; ends 141
        lda #$B0
        sta HMP0
        sta WSYNC
        sta HMOVE
        SLEEP 30
        lda #$70
        sta HMP0
        lda #$80
        sta HMM0
        sta HMM1
        sta WSYNC
        sta HMOVE
        lda #$00
        SLEEP 11
        sta HMP0
        sta WSYNC               ; spacer
        sta WSYNC
        sta CXCLR               ; measured row
        sta WSYNC
        lda CXM0P
        and #$40
        sta P1+5
        lda CXM1P
        and #$80
        sta P1+6
        lda #$80
        sta HMP0

        ; ---- verdict ------------------------------------------------------
        ldx #6
.pack:
        lda P1,x
        beq .next
        lda PROF
        ora BitTab,x
        sta PROF
.next:
        dex
        bpl .pack
        lda PROF
        cmp #A_EXPECTED
        bne .afail
        lda C0
        bne .cfail0
        lda C1
        beq .cfail1
        PASS_TEST
.cfail0:
        ldx #8
        ldy #$00
        bne .cshow              ; X is never zero: always taken
.cfail1:
        ldx #9
        ldy #$02
.cshow:
        stx CODE
        sty EXPECTED
        lda #$00
        ldx C0
        beq .c1
        ora #$01
.c1:    ldx C1
        beq .c2
        ora #$02
.c2:    sta OBSERVED
        jmp fail_result
.afail:
        ; CODE = the first probe bit differing from expectation
        ldx #0
.find:
        lda PROF
        eor #A_EXPECTED
        and BitTab,x
        bne .found
        inx
        bne .find
.found:
        inx
        stx CODE
        lda PROF
        sta OBSERVED
        lda #A_EXPECTED
        sta EXPECTED
        jmp fail_result

BitTab:
        .byte $01,$02,$04,$08,$10,$20,$40

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
