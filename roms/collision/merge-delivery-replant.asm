; merge-delivery-replant — a player reset written while the chip is
; already deciding to start that player's pattern does not corrupt the
; delivery: the in-flight start rides through the reset, kept or shifted
; per a fixed per-timing profile, and the stretched first-cell merge
; pixel is never deleted. Real PAL console, 2026-07-29.
;
; The TIA (the console's video chip) has no frame memory: it draws each
; scanline live. A player object is an 8-bit pattern walked out by a
; scan that a free-running counter starts at the player's column every
; line; at quad size each pattern bit spans four colour clocks. A few
; clocks before the first pixel, a start decode is "in flight". Writing
; RESP0 during those clocks replants the counter mid-decision. And under
; a stuck horizontal-motion train an extra motion step arrives every
; fourth clock; when one coincides with the start, the delivered first
; cell widens by one pixel.
;
; Measured, with the widening step coinciding — the tightest place a
; reset can land: the delivery is never lost and never loses its widened
; pixel to the reset; at each landing across the whole decode window the
; outcome is the same fixed keep-or-shift profile, and the shifts are
; always whole (the tail moves with the head).
;
;   OBSERVED = merge-pixel bits, legs 1-8. EXPECTED = merge-pixel bits,
;   legs 9-12 (bits 0-3), lost flag (bit 4), shifted flag (bit 5), probe
;   checks (bits 6-7). PASS = the measured profile $4D / $E0 exactly;
;   on FAIL, CODE = the first leg (1-16, bit order) reading wrong.
        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

M1B     = $90                   ; per-leg missile bits (the merge pixel)
BLB     = $A0                   ; per-leg ball bits (tail shift)
P1B     = $B0                   ; per-leg body-probe bits
CTLM1   = $AC
CTLBL   = $AD
CTLP1   = $AE
PROF1   = $B8
PROF2   = $B9

EXPECTED_P1 = $4D               ; legs 1-8 merge-pixel profile
EXPECTED_P2 = $E0               ; legs 9-12 clear + shifted flag + probes

        org $F000

        MAC LEG                 ; {1} trim {2} reset SLEEP {3} M1 walk
                                ; {4} BL walk {5} M1 cell {6} BL cell
                                ; {7} P1 walk {8} P1 cell
        ; park the quad player: write ends clock 141 -> column 79 (wide
        ; players land one clock later than single width's 78)
        sta WSYNC
        SLEEP 44
        sta RESP0
        lda #{1}
        sta HMP0
        ; park the missile (write ends clock 69 -> column 5) and arm
        sta WSYNC
        SLEEP 20
        sta RESM1
        lda #{3}
        sta HMM1
        ; park the ball (write ends clock 72 -> column 8) and arm
        sta WSYNC
        SLEEP 21
        sta RESBL
        lda #{4}
        sta HMBL
        ; park the body probe (write ends clock 69 -> column 7: a
        ; blank-edge player reset lands one clock later than mid-scan's
        ; "5 clocks after the strobe"; measured) and arm
        sta WSYNC
        SLEEP 20
        sta RESP1
        lda #{7}
        sta HMP1
        ; one HMOVE applies the player trim and all three probe walks
        sta WSYNC
        sta HMOVE
        SLEEP 30
        sta HMCLR               ; probes take no further motion
        lda #$70
        sta HMP0
        ; the stuck train: mid-burst rewrite wedges the motion latch
        sta WSYNC
        sta HMOVE
        lda #$00
        SLEEP 11
        sta HMP0                ; write cycle 19: the train runs from here
        ; three drift rows; the fourth row's start decode reaches the
        ; blank-edge clocks where a train step coincides with it
        ldy #3
.dr:
        sta WSYNC
        dey
        bne .dr
        sta CXCLR               ; scope the latches to the reset row
        sta WSYNC
        SLEEP {2}
        sta RESP0               ; the reset lands inside the decode
        ; the reset row's latches
        sta WSYNC
        lda CXM1P
        and #$80
        sta {5}
        lda CXP0FB
        and #$40
        sta {6}
        lda CXPPMM
        and #$80
        sta {8}
        ; free the wedged latch
        sta WSYNC
        lda #$80
        sta HMP0
        ENDM

Reset:
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
        sta NUSIZ1              ; missile width 1, single-copy probe
        sta ENAM0
        sta REFP1
        sta VDELP0
        sta VDELP1
        sta VDELBL
        sta REFP0
        sta RESMP0
        sta RESMP1
        sta HMCLR
        lda #$07
        sta NUSIZ0              ; quad player
        lda #$B4
        sta GRP0
        lda #$80
        sta GRP1                ; body probe: one pixel at its column
        lda #$02
        sta ENAM1
        sta ENABL
        clc
        clv

        ; settle
        ldx #24
.pre:
        sta WSYNC
        dex
        bne .pre

        ; Twelve legs: the player parked and trimmed to three start
        ; columns (3/7/11, one motion-step cycle apart, so the mod-3
        ; strobe grid covers every clock of the window) x four reset
        ; strobes (clocks 63/66/69/72). Probes, latched on the reset
        ; row only: a width-one missile on the widened pixel's column
        ; (2/6/10), a one-pixel second player on the cell body
        ; (3/7/11), the ball past the tail (7/11/15). Per leg the
        ; classes separate: delivered (missile 1, body 1, ball 0),
        ; widened pixel deleted (0,1,0), delivery shifted (0,1,1),
        ; delivery lost (0,0,0). A thirteenth leg with no coinciding
        ; step checks the probes themselves.
        ;   trim  reset M1walk BLwalk  M1cell  BLcell  P1walk P1cell
        LEG $10, 18,   $30,   $10,    M1B+0,  BLB+0,  $40,   P1B+0
        LEG $10, 19,   $30,   $10,    M1B+1,  BLB+1,  $40,   P1B+1
        LEG $10, 20,   $30,   $10,    M1B+2,  BLB+2,  $40,   P1B+2
        LEG $10, 21,   $30,   $10,    M1B+3,  BLB+3,  $40,   P1B+3
        LEG $D0, 18,   $F0,   $D0,    M1B+4,  BLB+4,  $00,   P1B+4
        LEG $D0, 19,   $F0,   $D0,    M1B+5,  BLB+5,  $00,   P1B+5
        LEG $D0, 20,   $F0,   $D0,    M1B+6,  BLB+6,  $00,   P1B+6
        LEG $D0, 21,   $F0,   $D0,    M1B+7,  BLB+7,  $00,   P1B+7
        LEG $90, 18,   $B0,   $90,    M1B+8,  BLB+8,  $C0,   P1B+8
        LEG $90, 19,   $B0,   $90,    M1B+9,  BLB+9,  $C0,   P1B+9
        LEG $90, 20,   $B0,   $90,    M1B+10, BLB+10, $C0,   P1B+10
        LEG $90, 21,   $B0,   $90,    M1B+11, BLB+11, $C0,   P1B+11
        ; probe check: no coinciding step; missile and body probe on lit
        ; pixels of the plain first cell, ball on a dark column
        LEG $00, 19,   $10,   $F0,    CTLM1,  CTLBL,  $20,   CTLP1

        ; ---- pack the two profile bytes -----------------------------------
        lda #$00
        ldx #7
.p1:
        asl
        ldy M1B,x
        beq .s1
        ora #$01
.s1:
        dex
        bpl .p1
        sta PROF1
        lda #$00
        ldx #3
.p2:
        asl
        ldy M1B+8,x
        beq .s2
        ora #$01
.s2:
        dex
        bpl .p2
        sta PROF2
        lda #$FF                ; lost flag: any body probe missing
        ldx #11
.p3:
        and P1B,x
        dex
        bpl .p3
        bne .s3
        lda #$10
        ora PROF2
        sta PROF2
.s3:
        lda #$00                ; shifted flag: any ball hit
        ldx #11
.p4:
        ora BLB,x
        dex
        bpl .p4
        beq .s4
        lda #$20
        ora PROF2
        sta PROF2
.s4:
        ldy CTLM1
        beq .s5
        lda #$40
        ora PROF2
        sta PROF2
.s5:
        ldy CTLP1
        beq .s6
        lda #$80
        ora PROF2
        sta PROF2
.s6:

        ; ---- verdict ------------------------------------------------------
        lda PROF1
        cmp #EXPECTED_P1
        bne .fail
        lda PROF2
        cmp #EXPECTED_P2
        beq .pass
.fail:
        ; CODE = the first differing bit, 1-16 across both bytes;
        ; OBSERVED/EXPECTED = the differing byte
        ldx #0
        lda PROF1
        eor #EXPECTED_P1
.f1:
        lsr
        bcs .in1
        inx
        cpx #8
        bne .f1
        lda PROF2
        eor #EXPECTED_P2
.f2:
        lsr
        bcs .in2
        inx
        cpx #16
        bne .f2
.in2:
        lda PROF2
        sta OBSERVED
        lda #EXPECTED_P2
        sta EXPECTED
        bne .code
.in1:
        lda PROF1
        sta OBSERVED
        lda #EXPECTED_P1
        sta EXPECTED
.code:
        inx
        stx CODE
        jmp fail_result
.pass:
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
