; dpc-shift — the DPC's shift read windows, and the rotate-vs-shift question. The
; DPC ("Display Processor Chip", Pitfall II) exposes each fetcher's masked data
; through extra read windows that transform the byte on the way out. Two of them
; move the bits by one position (US Patent 4,644,495 text):
;   read $F028+x   shift right   data AND flag, right one, zero into the top
;                                (ABCDEFGH -> 0ABCDEFG)
;   read $F030+x   shift left    data AND flag, left one, zero into the bottom
;                                (ABCDEFGH -> BCDEFGH0)
; The flag is applied first (data AND flag), then the byte is shifted, so a clear
; flag gives $00.
;
; The fetcher mechanism — an 11-bit down-counter, destructive reads, and a
; graphics ROM laid out so a counter holding c returns the byte
; f(c) = (c XOR (c >> 4)) AND $FF — is explained in dpc-fetch. The flag is set by
; a read whose counter-low lands exactly on Top, as in dpc-flag. Registers are
; reached through the $F000-$F07F mirror.
;
; Patent Table 1 labels these windows "rotated", but the patent's own text
; describes a zero-fill shift. The two differ only when a boundary bit is set: a
; shift-right of a byte whose top bit is set loses that bit and fills zero, while
; a rotate-right would carry it into bit 0. A source byte with bit7 and bit0 both
; set settles it. Using f($89)=$81 (10000001):
;       shift right = $40   rotate right = $C0   unimplemented = $00
;       shift left  = $02   rotate left  = $03   unimplemented = $00
;
; These windows are specified in the patent but unused by Pitfall II — untested
; on hardware; implementations without them return $00 for reads of $F028-$F037.
; A flag-set shift read separates every case: shift $40/$02, rotate $C0/$03,
; absent $00. This test asserts the zero-fill shift.
;
;   CODE $01 = flag-clear shift windows did not return $00 (data AND flag must be
;              $00 when the flag is clear, on every model)
;        $02 = shift-right window wrong (low==Top, f($89)=$81 -> expected $40; an
;              unimplemented window returns $00, a rotate $C0 — first divergent cell)
;        $03 = shift-left window wrong (low==Top, f($89)=$81 -> expected $02;
;              a rotate would return $03)
;        $04 = a shift read did not decrement the shared pointer (interleaved with
;              unmasked reads; only the agreed unmasked bytes are asserted)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8
HOTSPOT1 = $FFF9

; Cell 01 (flag clear -> $00) is agreed by every model, so it runs first and
; proves the plumbing; cells 02-03 then grade the transform itself. $F000-$F007
; is never read and music stays off (counter-high writes keep D4/D5 = 0).
DATA     = $F008             ; read DFx data unmasked (decrements)
SHR      = $F028             ; read DFx (data AND flag) shifted right (0ABCDEFG)
SHL      = $F030             ; read DFx (data AND flag) shifted left  (BCDEFGH0)
TOP      = $F040             ; write DFx Top    (clears the flag)
BOTTOM   = $F048             ; write DFx Bottom
CLOW     = $F050             ; write DFx counter low
CHIGH    = $F058             ; write DFx counter high (DF4=$F05C, DF5-7=$F05D-F)

V1       = $90
V2       = $91

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

        ; --- cell 01 (green): flag clear -> shift windows return $00
        lda #$C0
        sta TOP+0           ; DF0 Top = $C0 (clears the flag)
        lda #$40
        sta BOTTOM+0        ; Bottom = $40
        lda #$00
        sta CHIGH+0
        lda #$80
        sta CLOW+0          ; low = $80 between -> flag stays clear
        lda SHR+0           ; shift-right of $00 = $00, ptr -> $7F
        sta V1
        lda SHL+0           ; shift-left  of $00 = $00, ptr -> $7E
        sta V2
        ASSERT_EQ V1, $00, $01
        ASSERT_EQ V2, $00, $01

        ; --- cell 02: shift-right window, flag set (first divergent cell)
        ; low == Top sets the flag; f($89)=$81 (bit7 & bit0 set) -> zero-fill
        ; shift right = $40. An unimplemented window -> $00; a rotate -> $C0.
        lda #$89
        sta TOP+0           ; Top = $89 (clears flag)
        lda #$00
        sta BOTTOM+0
        lda #$00
        sta CHIGH+0
        lda #$89
        sta CLOW+0          ; low == Top -> flag sets
        lda SHR+0           ; shr($81) = $40, ptr -> $88
        sta V1
        ASSERT_EQ V1, $40, $02

        ; --- cell 03: shift-left window, flag set
        ; same source f($89)=$81 -> zero-fill shift left = $02; a rotate -> $03.
        lda #$89
        sta TOP+0
        lda #$00
        sta BOTTOM+0
        lda #$00
        sta CHIGH+0
        lda #$89
        sta CLOW+0          ; low == Top -> flag sets
        lda SHL+0           ; shl($81) = $02, ptr -> $88
        sta V1
        ASSERT_EQ V1, $02, $03

        ; --- cell 04: a shift read decrements the shared pointer
        ; Interleave unmasked reads (uncontested bytes) with a shift read; the
        ; shift read's return value diverges (not asserted), the following
        ; unmasked byte proves the pointer advanced. Sequence: c=$50 f($50)=$55;
        ; shift-right read (c=$4F) advances to $4E; shift-left read (c=$4E)
        ; advances to $4D; f($4D)=$49.
        lda #$50
        sta CLOW+0
        lda #$00
        sta CHIGH+0
        lda DATA+0          ; unmasked f($50) = $55, ptr -> $4F
        sta V1
        lda SHR+0           ; shift-right read (value diverges; not asserted), ptr -> $4E
        lda SHL+0           ; shift-left read  (value diverges; not asserted), ptr -> $4D
        lda DATA+0          ; unmasked f($4D) = $49 -> both shift reads decremented
        sta V2
        ASSERT_EQ V1, $55, $04
        ASSERT_EQ V2, $49, $04

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
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
