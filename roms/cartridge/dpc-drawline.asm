; dpc-drawline — the DPC's patent-only "draw line" circuit (US 4,644,495 Fig. 5).
;
; Data fetcher DF4 carries an extra circuit meant to sweep a line or object
; horizontally across scanlines: an 8-bit adder repeatedly adds DF4's Top register
; into a latch pair, and its carry-out DLC — ANDed with a 4-bit MOVAMT register —
; feeds the high nibble of the $1004-$1007 amplitude reads.
;
; Pitfall II never uses this circuit; it exists only in the patent's description,
; untested on hardware. This test asserts what the patent describes.
;
; The mechanism is a "draw line add" (DL-add), pulsed by any read of $1004 or
; $1005: on the falling edge latch 64 copies into latch 62, and on the rising
; edge the adder result (latch 62 + DF4-Top) latches back into latch 64, with the
; 8-bit carry-out becoming DLC. So each with-add read advances latch 64 by Top and
; republishes DLC = carry(latch 64 + Top). More of the circuit:
;   - MOVAMT is a 4-bit register loaded from data bits D7-D4 by a write to
;     $1060-$1067. The high nibble of a $1004-$1007 read is MOVAMT when DLC=1, and
;     0 when DLC=0.
;   - $1006/$1007 read the same value without pulsing the add.
;   - $105C bit D4 (DF4's counter-high write) enables draw-line; DF4's counter-low
;     write loads latch 64 with the seed.
;
;   CODE $01 = MOVAMT=0 baseline high nibble not 0
;        $02 = carrying add did not put MOVAMT in the high nibble ($F0)
;        $03 = non-carrying add did not clear the high nibble ($00)
;        $04 = DLC ratio wrong (expected $F0,$00,$F0,$00 over four adds)
;        $05 = $F006 without-add read pulsed/altered the carry phase
;        $06 = draw-line disabled ($105C D4=0) still drove the high nibble
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8
HOTSPOT1 = $FFF9

; Music stays off (DF5-7 are music-disabled at start, and MOVAMT is zeroed —
; the patent gives neither a reset value), so the $F004 low nibble is always 0
; and every cell asserts the isolated high nibble as a full byte.
; Only $F004 and $F006 are read; never $F000-$F003, $F005 or $F007.
ADD      = $F004             ; read amplitude with draw-line add (pulses DL-add)
NOADD    = $F006             ; read amplitude without draw-line add (no pulse)
TOP      = $F040             ; write DFx Top       (DF4 = $F044)
CLOW     = $F050             ; write DFx counter low (DF4 = $F054: also loads latch 64)
CHIGH    = $F058             ; write DFx counter high (DF4 = $F05C: D4 = draw-line enable)
MOVAMT   = $F060             ; write MOVAMT from data bits D7-D4

V1       = $90
V2       = $91
V3       = $92
V4       = $93

ENTRY    = $F080

        MAC ENTRYSTUB
        bit HOTSPOT0
        jmp Main
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        ds 128                 ; DPC register window: no code/vectors
        ENTRYSTUB              ; ENTRY ($F080)
Main:
        CLEAN_START
        TEST_BEGIN

        ; Force the DPC state the cells rely on — the patent gives no reset
        ; values, so nothing is left to power-on chance: MOVAMT = 0 and the
        ; DF5-7 music latches off (a music-on voice would put its mixer value
        ; in every $F004 low nibble; see dpc-music).
        lda #$00
        sta MOVAMT+0
        sta CHIGH+5
        sta CHIGH+6
        sta CHIGH+7

        ; --- cell 01: MOVAMT=0 isolates the high nibble to 0.
        ; Enable draw-line and seed a carrying add with MOVAMT still zero: the
        ; high nibble is MOVAMT&DLC = 0 regardless of the carry, so $F004 is
        ; $00. Proves the amplitude plumbing before the probes.
        lda #$10
        sta CHIGH+4         ; $F05C: DF4 counter-high, D4=1 (draw-line enable)
        lda #$80
        sta TOP+4           ; DF4 Top = $80
        lda #$C0
        sta CLOW+4          ; seed latch 64 = $C0 (would carry with Top)
        lda ADD             ; with-add: DLC=1 but MOVAMT=0 -> high nibble 0 -> $00
        sta V1
        ASSERT_EQ V1, $00, $01

        ; --- cell 02 (patent headline): a carrying add drives MOVAMT into the
        ; high nibble. Top=$80, seed $C0 -> $C0+$80 carries -> DLC=1 -> $F0.
        lda #$10
        sta CHIGH+4         ; enable
        lda #$80
        sta TOP+4           ; Top = $80
        lda #$F0
        sta MOVAMT+0        ; MOVAMT = %1111 (data D7-D4)
        lda #$C0
        sta CLOW+4          ; seed latch 64 = $C0
        lda ADD             ; latch62=$C0; latch64=$C0+$80=$40, DLC=1 -> $F0
        sta V1
        ASSERT_EQ V1, $F0, $02

        ; --- cell 03: a non-carrying add clears the high nibble. Top=$20,
        ; seed $10 -> $10+$20 = $30, no carry -> DLC=0 -> $00.
        lda #$20
        sta TOP+4           ; Top = $20
        lda #$10
        sta CLOW+4          ; seed latch 64 = $10
        lda ADD             ; latch62=$10; latch64=$30, DLC=0 -> $00
        sta V1
        ASSERT_EQ V1, $00, $03

        ; --- cell 04: the DLC ratio. Top=$80 carries every other pulse from a
        ; seed of $80: $80+$80 carry, $00+$80 no-carry, repeat.
        lda #$80
        sta TOP+4           ; Top = $80
        lda #$80
        sta CLOW+4          ; seed latch 64 = $80
        lda ADD             ; latch64 $80->$00, DLC=1 -> $F0
        sta V1
        lda ADD             ; latch64 $00->$80, DLC=0 -> $00
        sta V2
        lda ADD             ; latch64 $80->$00, DLC=1 -> $F0
        sta V3
        lda ADD             ; latch64 $00->$80, DLC=0 -> $00
        sta V4
        ASSERT_EQ V1, $F0, $04
        ASSERT_EQ V2, $00, $04
        ASSERT_EQ V3, $F0, $04
        ASSERT_EQ V4, $00, $04

        ; --- cell 05: $F006 reads without pulsing the add. Seed $80/Top $80 for
        ; a carrying first phase; then read add / no-add / add / no-add. The
        ; no-add read republishes the current DLC but must not advance the phase,
        ; so the second add read still sees the un-advanced $00 step:
        ;   $F004 -> $F0 (carry), $F006 -> $F0 (same DLC, no pulse),
        ;   $F004 -> $00 (next step), $F006 -> $00.
        ; A model that let $F006 pulse the add would instead read $F0,$00,$F0,...
        lda #$80
        sta TOP+4           ; Top = $80
        lda #$80
        sta CLOW+4          ; seed latch 64 = $80
        lda ADD             ; latch64 $80->$00, DLC=1 -> $F0
        sta V1
        lda NOADD           ; no pulse: republishes DLC=1 -> $F0
        sta V2
        lda ADD             ; latch64 $00->$80, DLC=0 -> $00 (phase not advanced by NOADD)
        sta V3
        lda NOADD           ; no pulse: DLC=0 -> $00
        sta V4
        ASSERT_EQ V1, $F0, $05
        ASSERT_EQ V2, $F0, $05
        ASSERT_EQ V3, $00, $05
        ASSERT_EQ V4, $00, $05

        ; --- cell 06: draw-line disabled ($105C D4=0) -> high nibble stays 0
        ; even with MOVAMT=$F0 and a carrying seed (patent: the enable gates the
        ; whole circuit).
        lda #$00
        sta CHIGH+4         ; $F05C: D4=0 -> draw-line disabled
        lda #$80
        sta TOP+4           ; Top = $80
        lda #$F0
        sta MOVAMT+0        ; MOVAMT = %1111
        lda #$C0
        sta CLOW+4          ; seed latch 64 = $C0 (would carry if enabled)
        lda ADD             ; disabled -> high nibble 0 -> $00
        sta V1
        ASSERT_EQ V1, $00, $06

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        ds 128
        ENTRYSTUB
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ------------------------------------------------- 2K display ROM + 256B pad
; Unused by this ROM, but the 2K block + 256B pad set the 10496-byte size
; accepted as a DPC cart. Laid out identically to dpc-fetch.
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
