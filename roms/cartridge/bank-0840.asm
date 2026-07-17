; bank-0840 — the 0840 EconoBanking board (homebrew; 8K) picks
; between its two 4K banks using a single address line.
;
; The cartridge answers every access with address line A12 high: the 4K window
; $F000-$FFFF, filled from one of two 4K banks. The select hotspots (addresses
; the board watches; touching one switches banks) do not live in that window. The
; board watches the low band $0800-$0FFF, and any access there — read or write,
; the data value does not matter — flips the bank on the next cycle.
;
; The board examines only three address lines, A12, A11 and A6:
;       A12  A11  A6
;        0    1    0    -> bank 0   (named hotspot $0800)
;        0    1    1    -> bank 1   (named hotspot $0840)
; The whole $0800-$0FFF band already has A12=0 and A11=1, so inside the band the
; choice comes down to A6 alone. A10-A7 and A5-A0 are all don't-cares, so a family
; of addresses aliases each hotspot:
;       $0800  $0900  $0C00   (all A6=0) -> bank 0
;       $0840  $0940  $0C40   (all A6=1) -> bank 1
; $0840 selects bank 1, but its A12=1 twin $F840 falls inside the cart's own
; $F000-$FFFF window, is not a hotspot, and leaves the bank alone. That proves
; A12 gates the select band out of the window.
;
;   CODE $01 = write $0800 did not page in bank 0
;        $02 = write $0840 did not page in bank 1
;        $03 = write $0800 did not return to bank 0
;        $04 = read  $0840 did not page in bank 1 (reads switch too)
;        $05 = read  $0800 did not return to bank 0
;        $06 = alias $0900 did not page in bank 0 (A8 don't-care)
;        $07 = alias $0C00 did not page in bank 0 (A10 don't-care)
;        $08 = alias $0940 did not page in bank 1
;        $09 = alias $0C40 did not page in bank 1
;        $0A = near-miss $F840 (A12=1 twin) wrongly switched while parked bank 0
;        $0B = near-miss $F800 (A12=1 twin) wrongly switched while parked bank 1
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: 0840

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HS0    = $0800                  ; access -> select bank 0 (A6=0)
HS1    = $0840                  ; access -> select bank 1 (A6=1); sta form is 8D 40 08
A0_1   = $0900                  ; alias of HS0 (A8 don't-care)  -> bank 0
A0_2   = $0C00                  ; alias of HS0 (A10 don't-care) -> bank 0
B1_1   = $0940                  ; alias of HS1 (A8 don't-care)  -> bank 1
B1_2   = $0C40                  ; alias of HS1 (A10 don't-care) -> bank 1
NM1    = $F840                  ; ROM-window twin of HS1 (A12=1) -> not a hotspot
NM0    = $F800                  ; ROM-window twin of HS0 (A12=1) -> not a hotspot
SIG    = $FC00                  ; per-bank signature (mid-bank, clear of stub/vectors)

ENTRY  = $F000                  ; stub entry (reset target), identical in both banks
PROBE  = $F006                  ; probe routine (jsr target), after the 6-byte entry

; probe result cells
WB0    = $90                    ; write $0800 -> bank 0
WB1    = $91                    ; write $0840 -> bank 1
WBH    = $92                    ; write $0800 -> home
RB1    = $93                    ; read  $0840 -> bank 1
RB0    = $94                    ; read  $0800 -> home
AL0A   = $95                    ; alias $0900 -> bank 0
AL0B   = $96                    ; alias $0C00 -> bank 0
AL1A   = $97                    ; alias $0940 -> bank 1
AL1B   = $98                    ; alias $0C40 -> bank 1
NMB0   = $99                    ; near-miss $F840 while parked bank 0
NMB1   = $9A                    ; near-miss $F800 while parked bank 1

; The shared stub — byte-identical in both banks, so execution can cross a select
; (the switch takes effect on the next cycle). The probe walks both banks by write
; and read strobe, then the aliases and the ROM-window near-misses. nop nop lets a
; switch settle before the signature read.
        MAC STUB
        bit HS0                         ; ENTRY ($F000): power-on bank is undefined -> force
                                        ;   bank 0 (read strobe $0800; the doubled 2C 00 08
                                        ;   is also the board's id pattern)
        jmp Main                        ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F006): write-strobe walk (A=0 keeps the incidental TIA pokes benign)
        lda #0
        sta HS0                         ; write $0800 -> bank 0
        nop
        nop
        lda SIG
        sta WB0
        sta HS1                         ; 8D 40 08 : write $0840 -> bank 1
        nop
        nop
        lda SIG
        sta WB1
        lda #0
        sta HS0                         ; write $0800 -> back to the home bank
        nop
        nop
        lda SIG
        sta WBH
        ; read strobes: an access of either kind switches
        bit HS1                         ; read $0840 -> bank 1
        nop
        nop
        lda SIG
        sta RB1
        bit HS0                         ; read $0800 -> home
        nop
        nop
        lda SIG
        sta RB0
        ; aliases of $0800 (park bank 1 first, so a real switch is visible)
        bit HS1
        nop
        nop
        bit A0_1                        ; $0900 -> bank 0
        nop
        nop
        lda SIG
        sta AL0A
        bit HS1
        nop
        nop
        bit A0_2                        ; $0C00 -> bank 0
        nop
        nop
        lda SIG
        sta AL0B
        ; aliases of $0840 (park bank 0 first)
        bit HS0
        nop
        nop
        bit B1_1                        ; $0940 -> bank 1
        nop
        nop
        lda SIG
        sta AL1A
        bit HS0
        nop
        nop
        bit B1_2                        ; $0C40 -> bank 1
        nop
        nop
        lda SIG
        sta AL1B
        ; near-misses: the A12=1 ROM-window twins are not hotspots
        bit HS0                         ; park bank 0
        nop
        nop
        bit NM1                         ; $F840 -> no switch (A12 gates it out)
        nop
        nop
        lda SIG
        sta NMB0
        bit HS1                         ; park bank 1
        nop
        nop
        bit NM0                         ; $F800 -> no switch
        nop
        nop
        lda SIG
        sta NMB1
        bit HS0                         ; restore the home bank before returning
        nop
        nop
        rts
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        CLEAN_START
        TEST_BEGIN

        jsr PROBE

        ASSERT_EQ WB0,  $A0, $01        ; write $0800 -> bank 0
        ASSERT_EQ WB1,  $B1, $02        ; write $0840 -> bank 1
        ASSERT_EQ WBH,  $A0, $03        ; write $0800 returned home
        ASSERT_EQ RB1,  $B1, $04        ; read  $0840 -> bank 1
        ASSERT_EQ RB0,  $A0, $05        ; read  $0800 returned home
        ASSERT_EQ AL0A, $A0, $06        ; alias $0900 -> bank 0
        ASSERT_EQ AL0B, $A0, $07        ; alias $0C00 -> bank 0
        ASSERT_EQ AL1A, $B1, $08        ; alias $0940 -> bank 1
        ASSERT_EQ AL1B, $B1, $09        ; alias $0C40 -> bank 1
        ASSERT_EQ NMB0, $A0, $0A        ; near-miss $F840: stayed bank 0
        ASSERT_EQ NMB1, $B1, $0B        ; near-miss $F800: stayed bank 1

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0                       ; bank 0 signature
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        STUB
        ORG $1C00
        RORG $FC00
        .byte $B1                       ; bank 1 signature (differs)
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
