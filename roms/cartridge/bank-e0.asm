; bank-e0 — the E0 board (Parker Bros, 8K) shows three changeable 1K windows
; plus one fixed 1K window.
;
; The cartridge answers every access with address line A12 high: the 4K window
; $F000-$FFFF. E0 cuts that window into four 1K parts. The 8K ROM is stored as
; eight 1K slices, and the first three parts each show one slice at a time:
;
;   $F000-$F3FF  window 0  shows slice N after any access to $FFE0+N
;   $F400-$F7FF  window 1  shows slice N after any access to $FFE8+N
;   $F800-$FBFF  window 2  shows slice N after any access to $FFF0+N
;   $FC00-$FFFF  fixed     always slice 7 (the hotspots and vectors live here)
;
; A select fires on the bus access alone: read or write, the data value does
; not matter. The three windows are independent — changing one leaves the
; other two as they were.
;
; Each slice holds a signature byte ($A0..$A7) at in-slice offset $3F8, read back
; at $F3F8/$F7F8/$FBF8 to prove which slice a window shows.
;
;   CODE $01..$07 = a write strobe ($FFE1..$FFE7) did not page slice 1..7 into
;                   window 0 (so slice 7, the fixed slice, also shows in window 0)
;        $08 = write $FFE9 did not page slice 1 into window 1
;        $09 = read  $FFED did not page slice 5 into window 1 (reads select too)
;        $0A = write $FFF2 did not page slice 2 into window 2
;        $0B = write $FFF6 did not page slice 6 into window 2
;        $0C = paging window 0 disturbed window 1 (windows not independent)
;        $0D = a read strobe ($FFE9) did not re-page window 1
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: E0

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

; signature read addresses (in-slice offset $3F8, per window)
WIN0 = $F3F8
WIN1 = $F7F8
WIN2 = $FBF8

; probe result cells
W0BASE = $8F           ; window-0 walk: slice X sig -> $8F+X ($90..$96 for X=1..7)
W1A    = $97           ; slice 1 in window 1 (write strobe)
W1B    = $98           ; slice 5 in window 1 (read strobe)
W2A    = $99           ; slice 2 in window 2
W2B    = $9A           ; slice 6 in window 2
INDEP  = $9B           ; window 1's slice after re-paging window 0
RDSEL  = $9C           ; window 1 after a read strobe re-select

; ---------------------------------------------------------------- slice 0 (harness)
; The harness (Main, asserts, result screen) does not fit in the fixed slice
; beside the probe, so it lives here and the entry pages it into window 0.
        SEG SLICE0
        ORG $0000
        RORG $F000
Main:
        CLEAN_START            ; (entry has already paged slice 0 into window 0)
        TEST_BEGIN

        jsr PROBE              ; strobe every window, collect signatures (in slice 7)

        ASSERT_EQ $90, $A1, $01        ; $FFE1 -> slice 1 in window 0
        ASSERT_EQ $91, $A2, $02        ; $FFE2 -> slice 2
        ASSERT_EQ $92, $A3, $03        ; $FFE3 -> slice 3
        ASSERT_EQ $93, $A4, $04        ; $FFE4 -> slice 4
        ASSERT_EQ $94, $A5, $05        ; $FFE5 -> slice 5
        ASSERT_EQ $95, $A6, $06        ; $FFE6 -> slice 6
        ASSERT_EQ $96, $A7, $07        ; $FFE7 -> slice 7 in window 0
        ASSERT_EQ W1A, $A1, $08        ; $FFE9 (write) -> slice 1 in window 1
        ASSERT_EQ W1B, $A5, $09        ; $FFED (read)  -> slice 5 in window 1
        ASSERT_EQ W2A, $A2, $0A        ; $FFF2 -> slice 2 in window 2
        ASSERT_EQ W2B, $A6, $0B        ; $FFF6 -> slice 6 in window 2
        ASSERT_EQ INDEP, $A5, $0C      ; window 1 kept slice 5 while window 0 changed
        ASSERT_EQ RDSEL, $A1, $0D      ; $FFE9 read strobe re-paged window 1

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $03F8
        RORG $F3F8
        .byte $A0                      ; slice 0 signature (slice 0 proves itself:
                                       ;   the result screen runs from it)
        ds 7, $FF                      ; pad slice 0 to its 1K boundary

; a pure-data slice: non-uniform header + signature at offset $3F8
        MAC DATASLICE          ; {1}=file base, {2}=signature byte
        ORG {1}
        RORG $F000
        .byte $E0, {2}                 ; header bytes (dodge a phantom-Superchip fingerprint)
        ds ($3F8-2), $00               ; gap to the signature offset
        .byte {2}                      ; signature at in-slice offset $3F8
        ds 7, $FF                      ; pad to the 1K boundary
        ENDM

; ------------------------------------------------------------ slices 1..6 (data)
        SEG SLICE1
        DATASLICE $0400, $A1
        SEG SLICE2
        DATASLICE $0800, $A2
        SEG SLICE3
        DATASLICE $0C00, $A3
        SEG SLICE4
        DATASLICE $1000, $A4
        SEG SLICE5
        DATASLICE $1400, $A5
        SEG SLICE6
        DATASLICE $1800, $A6

; ----------------------------------------------------------- slice 7 (fixed code)
; Always mapped at $FC00-$FFFF. Holds the reset entry, the strobing probe (every
; opcode here is fetched from the fixed slice, so it survives a page), slice 7's
; own signature, and the vectors. Code stays clear of the hotspots $FFE0-$FFF7.
        SEG SLICE7
        ORG $1C00
        RORG $FC00
ENTRY:
        ldx #0                 ; power-on window state is undefined -> strobe all three
        sta $FFE0,x            ; window 0 = slice 0 (the harness)
        sta $FFE8              ; window 1 = slice 0 (known baseline)
        sta $FFF0              ; window 2 = slice 0
        jmp Main               ; run the harness from window 0 (slice 0)

; PROBE — walk the three windows, storing each slice's signature. Window-0 uses
; indexed stores (9D E0 FF) to keep absolute $FFE0-$FFE7 reads (a rival board's
; fingerprint) out of the image; windows 1/2 use the detector's own E0 forms.
PROBE:
        ldx #1
.w0:
        sta $FFE0,x           ; window 0 = slice X (write strobe)
        lda WIN0              ; signature at $F3F8
        sta W0BASE,x          ; -> $90..$96
        inx
        cpx #8
        bne .w0
        ; window 1: a write strobe then a read strobe (both must page)
        sta $FFE9             ; 8D E9 FF  window 1 = slice 1 (write)
        lda WIN1
        sta W1A               ; expect $A1
        lda $FFED             ; AD ED FF  window 1 = slice 5 (read)
        lda WIN1
        sta W1B               ; expect $A5
        ; window 2: independent third select
        sta $FFF2             ; window 2 = slice 2
        lda WIN2
        sta W2A               ; expect $A2
        sta $FFF6             ; window 2 = slice 6
        lda WIN2
        sta W2B               ; expect $A6
        ; independence: re-page window 0, window 1 must keep slice 5
        ldx #3
        sta $FFE0,x           ; window 0 = slice 3
        lda WIN1
        sta INDEP             ; expect $A5 (window 1 untouched)
        ; a read strobe re-pages window 1 just like a write
        lda $FFE9             ; AD E9 FF  window 1 = slice 1 (read)
        lda WIN1
        sta RDSEL             ; expect $A1
        ; restore window 0 = harness slice 0 so the rts lands on real code
        ldx #0
        sta $FFE0,x
        rts

        ORG $1FF8
        RORG $FFF8
        .byte $A7                      ; slice 7 signature (read at $F3F8 when paged in)
        .byte $FF                      ; $FFF9 filler
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
