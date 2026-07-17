; hmove-line-end — an HMOVE strobed at the very end of a line takes effect on
; the NEXT line.
;
; HMOVE is the object-motion strobe of the TIA (the chip that generates the video).
; A store's write reaches the TIA on the store instruction's final CPU cycle, so
; the exact cycle within the 76-cycle line at which that write lands decides
; what HMOVE does. Strobe it early and the object moves by its programmed amount
; with the 8-pixel horizontal-blank extension (the "comb") on that same line.
; Strobe it right at the line's end and the whole effect — the comb and a full
; displacement — appears on the FOLLOWING line instead, as if strobed at that
; line's start. In the couple of cycles just before the boundary the object
; instead takes its deepest leftward displacement (down to -15 for a $7x motion
; value) with no comb at all — the trick rows games use for combless HMOVE
; screens.
;
; The test sweeps the strobe cycle across this boundary one cycle at a time,
; k = 65..80 (write cycle mod 76), one horizontal band per k, 16 bands top to
; bottom. Two 1-pixel white missiles take the same strobe:
;   M0 with HMM0=$70: settled displacement -9,-9,-10,-11,-12,-12,-13,-14,-15,-15
;      for k=65..74, then -7 from k=75 and -6 at k=80.
;   M1 with HMM1=$80: no motion for k<=74, then +8 from k=75.
; The background is blue, so the comb — absent for k<=74, present from k=75 —
; shows as a black notch at x 0-7 on the line the strobe lands on. Each band
; re-homes the missiles first (M0 base column x=23, M1 base column x=65), so the
; settled columns read directly against those bases:
;   M0 = 14,14,13,12,11,11,10,9,8,8   (k=65..74), then 16,16,16,16,16,17 (k=75..80)
;   M1 = 65 for k<=74, then 73.
;
; Verdict: the captured frame vs hmove-line-end_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; current band 0..15 (strobe cycle k = 65+BAND)
ODD     = $82                   ; BAND & 1 (adds the odd cycle)
T       = $83                   ; scratch
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
SET     = $86                   ; settle lines after the strobe (8, or 7 from band 9 up)

        org $F000

Reset:
        CLEAN_START

        lda #$92
        sta COLUBK              ; blue field: the comb notch reads as black
        lda #$0E
        sta COLUP0              ; M0 white
        sta COLUP1              ; M1 white
        lda #$70
        sta HMM0                ; the -7 column of the displacement table
        lda #$80
        sta HMM1                ; the +8 column (no motion without the comb)

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0
.bandloop:
        stx BAND

        ; line 1: blank the missiles for the transitional lines and precompute
        ; the sled entry: VEC = Sled + 8 - BAND/2, ODD = BAND & 1
        sta WSYNC
        lda #$00
        sta ENAM0
        sta ENAM1
        lda BAND
        and #$01
        sta ODD
        lda BAND
        lsr
        sta T
        lda #$08
        sec
        sbc T
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        lda #$08                ; settle-line count: from band 9 (k = 74) the
        ldy BAND                ; strobe or its following WSYNC write slides
        cpy #9                  ; past the line boundary, spending a line —
        bcc .s8                 ; drop one settle line to keep every band 12
        lda #$07                ; (k = 73's WSYNC write lands exactly on the
.s8:                            ; final cycle and does not spill)
        sta SET

        ; line 2: re-home both missiles (M0 base x=23, M1 base x=65)
        sta WSYNC
        SLEEP 26
        sta RESM0
        SLEEP 11
        sta RESM1

        ; line 3: strobe HMOVE at write cycle k = 65 + BAND. For k >= 76 the
        ; write slides past the boundary into the next line's blank cycles 0-4 —
        ; a deliberate overshoot, and the only way to reach cycles 0-2 at all.
        sta WSYNC
        lda ODD
        lsr                     ; C = BAND & 1
        bcs .go                 ; +1 cycle on odd bands: the sled steps 2 cycles
                                ; at a time, so the branch reaches the odd k
.go:
        jmp (VEC)
Sled:
        REPEAT 33
        nop
        REPEND
        sta HMOVE

        ; lines 4..12: re-enable and show the settled columns (+ the comb on
        ; the applied line for k >= 75)
        sta WSYNC
        lda #$02
        sta ENAM0
        sta ENAM1
        ldy SET
.settle:
        sta WSYNC
        dey
        bne .settle

        ldx BAND
        inx
        cpx #16
        beq .bandsdone
        jmp .bandloop           ; loop body outgrew a relative branch
.bandsdone:

        ; 16 bands x 12 lines = 192 visible; 50 Hz fields are taller — pad blank
        lda #$00
        sta ENAM0
        sta ENAM1
        IFCONST FIELD_50HZ
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        ENDIF
        lda #$02
        sta ENAM0
        sta ENAM1

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
