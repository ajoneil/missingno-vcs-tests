; dpc-swizzle — the DPC's nibble-swap and bit-reverse read windows. The DPC
; ("Display Processor Chip", Pitfall II) exposes each fetcher's masked data
; through extra read windows that transform the byte on the way out. Two of them
; permute the bits (US Patent 4,644,495 Table 1, Fig. 11a/11b):
;   read $F018+x   nibble-swap   data AND flag with its two nibbles swapped
;                                (ABCDEFGH -> EFGHABCD)
;   read $F020+x   bit-reverse   data AND flag with its bits reversed
;                                (ABCDEFGH -> HGFEDCBA)
; In both, the flag is applied first (data AND flag), then the byte is permuted,
; so a clear flag gives $00 (any permutation of zero is zero).
;
; The fetcher mechanism — an 11-bit down-counter, destructive reads, and a
; graphics ROM laid out so a counter holding c returns the byte
; f(c) = (c XOR (c >> 4)) AND $FF — is explained in dpc-fetch. The flag is set by
; a read whose counter-low lands exactly on Top, as in dpc-flag. Registers are
; reached through the $F000-$F07F mirror.
;
; These windows are specified in the patent but unused by Pitfall II — untested
; on hardware; implementations without them return $00 for reads of $F018-$F027.
; A flag-set read tells them apart: the documented side returns the permuted
; byte, the unimplemented side $00. (With the flag clear both sides return $00.)
;
;   CODE $01 = flag-clear permuting windows did not return $00 (data AND flag
;              must be $00 when the flag is clear, on every model)
;        $02 = nibble-swap window wrong (low==Top, expected swap of f($4F)=$4B ->
;              $B4; an unimplemented window returns $00 — first divergent cell)
;        $03 = bit-reverse window wrong (low==Top, expected reverse of
;              f($1C)=$1D -> $B8)
;        $04 = the identity, nibble-swap and bit-reverse of one byte did not
;              come out distinct (masked f($1C)=$1D, swap=$D1, reverse=$B8)
;        $05 = a permuting read did not decrement the shared pointer (interleaved
;              with unmasked reads; only the agreed unmasked bytes are asserted)
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
; proves the plumbing; cells 02-05 then grade the transforms themselves. The
; counters are picked so the three transforms of one byte all differ. $F000-$F007
; is never read and music stays off (the music fetchers DF5-7 are never configured).
DATA     = $F008             ; read DFx data unmasked (decrements)
MASKED   = $F010             ; read DFx data AND flag (decrements)
SWIZ     = $F018             ; read DFx (data AND flag), nibble-swapped (decrements)
REVW     = $F020             ; read DFx (data AND flag), bit-reversed  (decrements)
TOP      = $F040             ; write DFx Top    (clears the flag)
BOTTOM   = $F048             ; write DFx Bottom
CLOW     = $F050             ; write DFx counter low
CHIGH    = $F058             ; write DFx counter high (DF4=$F05C, DF5-7=$F05D-F)

V1       = $90
V2       = $91
V3       = $92

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

        ; --- cell 01 (green): flag clear -> permuting windows return $00
        ; Loading counter-low strictly between Bottom and Top leaves the flag
        ; clear, so (data AND flag) is $00 and any permutation of it is $00.
        lda #$C0
        sta TOP+0            ; DF0 Top = $C0 (the write also clears the flag)
        lda #$40
        sta BOTTOM+0         ; Bottom = $40
        lda #$00
        sta CHIGH+0
        lda #$80
        sta CLOW+0           ; low = $80, strictly between -> flag stays clear
        lda SWIZ+0           ; nibble-swap window: swap($00) = $00, ptr -> $7F
        sta V1
        lda REVW+0           ; bit-reverse window:  rev($00)  = $00, ptr -> $7E
        sta V2
        ASSERT_EQ V1, $00, $01
        ASSERT_EQ V2, $00, $01

        ; --- cell 02: nibble-swap window with the flag set (first divergent cell)
        ; low == Top sets the flag before the byte is formed; the window then
        ; swaps the nibbles of f($4F)=$4B -> $B4. An unimplemented window -> $00.
        lda #$4F
        sta TOP+0            ; Top = $4F (clears flag)
        lda #$00
        sta BOTTOM+0        ; Bottom = $00 (out of the way)
        lda #$00
        sta CHIGH+0
        lda #$4F
        sta CLOW+0          ; low == Top -> flag sets on the read
        lda SWIZ+0          ; swap(f($4F)) = swap($4B) = $B4, ptr -> $4E
        sta V1
        ASSERT_EQ V1, $B4, $02

        ; --- cell 03: bit-reverse window with the flag set
        ; reverse(f($1C)=$1D) = $B8 (chosen so reverse != nibble-swap != identity).
        lda #$1C
        sta TOP+0           ; Top = $1C (clears flag)
        lda #$00
        sta BOTTOM+0
        lda #$00
        sta CHIGH+0
        lda #$1C
        sta CLOW+0          ; low == Top -> flag sets
        lda REVW+0          ; rev(f($1C)) = rev($1D) = $B8, ptr -> $1B
        sta V1
        ASSERT_EQ V1, $B8, $03

        ; --- cell 04: three transforms of one display byte, off the same c
        ; Reloading low == Top before each read re-lands on Top (re-setting the
        ; flag) and re-presents f($1C)=$1D, so the plain masked window returns the
        ; identity, the nibble-swap window $D1, the bit-reverse window $B8.
        lda #$1C
        sta TOP+0
        lda #$00
        sta BOTTOM+0
        lda #$00
        sta CHIGH+0
        lda #$1C
        sta CLOW+0
        lda MASKED+0        ; identity:    f($1C)      = $1D, ptr -> $1B
        sta V1
        lda #$1C
        sta CLOW+0          ; reload low == Top
        lda SWIZ+0          ; nibble-swap: swap($1D)   = $D1, ptr -> $1B
        sta V2
        lda #$1C
        sta CLOW+0          ; reload low == Top
        lda REVW+0          ; bit-reverse: rev($1D)    = $B8, ptr -> $1B
        sta V3
        ASSERT_EQ V1, $1D, $04
        ASSERT_EQ V2, $D1, $04
        ASSERT_EQ V3, $B8, $04

        ; --- cell 05: a permuting read decrements the shared pointer
        ; Interleave unmasked reads (uncontested bytes) with
        ; a nibble-swap read. The swizzle read's return value diverges, so it is
        ; not asserted; the following unmasked byte proves the pointer advanced
        ; across it. Sequence: c=$50 -> f($50)=$55; swap read (c=$4F) advances to
        ; $4E; f($4E)=$4A; f($4D)=$49.
        lda #$50
        sta CLOW+0
        lda #$00
        sta CHIGH+0
        lda DATA+0          ; unmasked f($50) = $55, ptr -> $4F
        sta V1
        lda SWIZ+0          ; nibble-swap read (value diverges; not asserted), ptr -> $4E
        lda DATA+0          ; unmasked f($4E) = $4A -> the swizzle read decremented once
        sta V2
        lda DATA+0          ; unmasked f($4D) = $49
        sta V3
        ASSERT_EQ V1, $55, $05
        ASSERT_EQ V2, $4A, $05
        ASSERT_EQ V3, $49, $05

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
