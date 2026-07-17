; open-bus — an undriven data-bus line keeps the last byte that was driven onto
; it, so a TIA read hands back its own driven bits merged with that leftover
; residue on the lines it does not drive.
;
; The 2600 has no truly unmapped addresses: every access with A12=0 selects the
; TIA or the RIOT, and A12=1 selects the cartridge. But selecting a chip is not
; the same as the chip driving all eight data lines. The TIA drives only its top
; bit(s):
;   - most collision registers drive D7 and D6 (the two collision bits)
;   - an input port (INPT0-5) drives D7
;   - a read address whose low nibble is $E or $F decodes to no register and
;     drives nothing
; Every line the TIA does not drive is left floating. The console has no bus
; pull-up resistors, so a floating line holds its charge — it keeps the last byte
; that was driven onto it. So a TIA read returns a byte in which the driven
; bits arrive as driven, and every undriven bit keeps the bus residue.
;
; The residue is the byte the bus carried on the cycle before the read, and
; the addressing mode fixes which byte that is. Walking the 6502 bus cycle by
; cycle:
;
;   lda $nn      (zero page, bytes A5 nn): fetch opcode / fetch operand $nn /
;                read $00nn. The cycle before the read fetched the operand, so
;                the residue is the operand byte $nn.
;   lda $hhll    (absolute, bytes AD ll hh): fetch opcode / fetch low $ll / fetch
;                high $hh / read $hhll. The cycle before the read fetched the high
;                address byte, so the residue is the high byte $hh.
;
; So the same TIA read register, reached by two addressing modes, floats to two
; different residues: the returned byte tracks the live bus, not the operand and
; not a fixed function of the register.
;
; The retained-byte model is hardware-measured: real PAL console, 2026-07-16.
; The lines hold the last byte driven, which the 6502 fetch order makes the
; address high byte for an absolute read, so lda $013E and lda $073E float to
; $01 and $07. Some implementations instead return the effective-address low
; byte regardless of addressing mode; that agrees with the retained byte only
; for zero-page reads (the operand is the low byte) and would hand back $3E for
; lda $3E, lda $013E and lda $073E alike. The zero-page cells ($02/$05) pass
; either way; only the absolute-high cells ($03/$04/$06) tell the two apart.
;
;   CODE $01 = driven RAM read wrong (a real, driven read returned something
;              other than the stored byte) — the control
;        $02 = lda $3E did not return operand residue $3E
;        $03 = lda $013E did not return abs-high residue $01 (same register as
;              $3E, so a differing result proves the bus, not the operand)
;        $04 = lda $073E did not return abs-high residue $07
;        $05 = lda $70 (CXM0P) did not return $30 (D7/D6 driven 0 masking the
;              operand residue's D6; low six lines keep the residue's low six
;              bits ($30))
;        $06 = lda $0970 (CXM0P) did not return $09 (same register and low byte
;              as $70, residue now the abs-high byte $09)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

CTRL    = $96                   ; a driven RAM cell for the control read
S1      = $90                   ; driven read result
S2      = $91                   ; lda $3E    (undriven, operand residue)
S3      = $92                   ; lda $013E  (undriven, abs-high residue)
S4      = $93                   ; lda $073E  (undriven, abs-high residue)
S5      = $94                   ; lda $70    (CXM0P, operand residue)
S6      = $95                   ; lda $0970  (CXM0P, abs-high residue)

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ; control: a real, driven read returns the stored byte, not a residue
        lda #$99
        sta CTRL                ; ram[$16] = $99  (driven via $0096)
        lda CTRL                ; RAM drives the bus
        sta S1                  ; S1 = $99 (stored), not $96 (operand) or anything else
        ASSERT_EQ S1, $99, $01

        ; --- undriven read registers: value is the residue ---
        lda $3E                 ; A5 3E : zp, residue = operand $3E
        sta S2
        lda $013E               ; AD 3E 01 : abs, residue = high byte $01
        sta S3
        lda $073E               ; AD 3E 07 : abs, residue = high byte $07
        sta S4

        ASSERT_EQ S2, $3E, $02  ; operand residue
        ASSERT_EQ S3, $01, $03  ; abs-high residue (same register $E as $3E)
        ASSERT_EQ S4, $07, $04  ; abs-high residue

        ; --- driven register CXM0P: D7/D6 driven 0, low six lines float ---
        sta CXCLR               ; clear all collision latches -> D7/D6 read 0
        lda $70                 ; A5 70 : CXM0P mirror, residue = operand $70
        sta S5                  ; expect (00) | ($70 & $3F) = $30  (D6 masked off)
        lda $0970               ; AD 70 09 : CXM0P mirror, residue = high byte $09
        sta S6                  ; expect (00) | ($09 & $3F) = $09

        ASSERT_EQ S5, $30, $05  ; operand residue, D7/D6 driven 0
        ASSERT_EQ S6, $09, $06  ; abs-high residue, same register/low byte as $70

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
