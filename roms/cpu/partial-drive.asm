; partial-drive — a TIA read register drives only its defined data lines; the
; rest of the bus floats.
;
; The TIA (the video/sound chip) has read registers for its collision latches
; and its input ports, but none of them drives all eight data lines. Most
; collision registers drive only the top two lines, D7 and D6 (the two
; collision bits for that object pair); an input-port register (INPT0-INPT5)
; drives only the top line, D7. Every data line the register does not drive is
; left undriven, and — exactly as in cpu/floating-bus — an undriven line keeps
; the last byte on the bus, which for a `lda $nn` read is the instruction's
; own operand $nn. So a collision read presents its two real collision bits
; over the low six bits of the operand, and an input read its one real bit
; over the low seven.
;
; The TIA decodes reads from address lines A0-A3 only (A4, A5 and A6 are
; ignored), so each read register answers at every $10 step across $00-$3F.
; Reading one register through several of these mirrors holds the driven bits
; fixed while the operand — and thus the floating remainder — changes. That
; separates genuine partial drive from an implementation that returns the
; whole register (the byte would not change with the operand) or the whole
; operand (the driven bits would never appear).
;
; INPT0's D7 reads 0 because the paddle-capacitor dump (VBLANK D7 set) grounds
; that input; INPT4's D7 reads 1 because the unpressed fire button is held high
; by its pull-up. The M0-P0 collision is created by overlapping missile 0 with
; player 0 mid-screen for two drawn lines before CXM0P is re-read — and it is
; M0-P0 (bit D6), not M0-P1 (bit D7), that latches.
;
;   CODE $01 = CXM0P via $30, no collision yet: expected $30
;        $02 = INPT0 via $18, paddles dumped (D7 grounded): expected $18
;        $03 = INPT4 via $3C, button open (D7 high): expected $BC
;        $04 = INPT4 via $1C, button open: expected $9C (new operand, D7 stays 1)
;        $05 = CXM0P via $10, M0-P0 latched: expected $50
;        $06 = CXM0P via $20, M0-P0 latched: expected $60 (new operand)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

S1      = $90                   ; CXM0P via $30, clear
S2      = $91                   ; INPT0 via $18, dumped
S3      = $92                   ; INPT4 via $3C
S4      = $93                   ; INPT4 via $1C
S5      = $94                   ; CXM0P via $10, latched
S6      = $95                   ; CXM0P via $20, latched

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ; no-collision collision read: D7-6 driven low, D5-0 keep the operand
        sta CXCLR               ; clear all collision latches
        lda $30                 ; CXM0P mirror (A4-A5 ignored on reads)
        sta S1                  ; S1 = $30 (D7-6 driven 00, D5-0 hold operand $30)

        ; input reads: D7 driven, D6-0 keep the operand
        lda #$82
        sta VBLANK              ; blank + dump: INPT0-3 grounded (D7 = 0)
        sta WSYNC
        sta WSYNC               ; let the dump settle
        lda $18                 ; INPT0 mirror: D7 grounded low
        sta S2                  ; S2 = $18 (D7 driven 0, D6-0 hold operand $18)
        lda $3C                 ; INPT4 mirror: button open -> D7 = 1
        sta S3                  ; S3 = $BC (D7 driven 1, D6-0 hold operand $3C)
        lda $1C                 ; INPT4 again, different operand
        sta S4                  ; S4 = $9C (D7 driven 1, D6-0 hold operand $1C)

        ; latch M0-P0: draw a solid P0 with a 1px M0 inside it, then re-read
        lda #$FF
        sta GRP0                ; solid 8px P0
        lda #$02
        sta ENAM0               ; 1px M0

        jsr vertical_sync
        jsr vblank_lines        ; beam on (also clears the paddle dump)

        sta WSYNC
        SLEEP 30
        sta RESP0               ; P0 spans [36..44) (suite calibration)
        sta WSYNC
        SLEEP 31
        sta RESM0               ; M0 at 38, inside P0's span
        sta WSYNC
        sta WSYNC               ; two drawn lines: the overlap latches M0-P0

        lda $10                 ; CXM0P mirror: D7-6 = 01 (M0-P0, not M0-P1)
        sta S5                  ; S5 = $50 (D7-6 driven 01, D5-0 hold operand $10)
        lda $20                 ; another CXM0P mirror, different operand
        sta S6                  ; S6 = $60 (D7-6 driven 01, D5-0 hold operand $20)

        ASSERT_EQ S1, $30, $01  ; cleared collision over operand $30
        ASSERT_EQ S2, $18, $02  ; INPT0 D7 grounded over operand $18
        ASSERT_EQ S3, $BC, $03  ; INPT4 D7 high over operand $3C
        ASSERT_EQ S4, $9C, $04  ; INPT4 D7 high over operand $1C
        ASSERT_EQ S5, $50, $05  ; M0-P0 latch (D6) over operand $10
        ASSERT_EQ S6, $60, $06  ; M0-P0 latch (D6) over operand $20
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
