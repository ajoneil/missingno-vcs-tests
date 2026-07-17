; bank-f8 — the F8 board (8K) holds two 4K banks and shows one at a time;
; touching a hotspot switches which bank is visible.
;
; The cart answers whenever address line A12 is high: a 4K window the CPU sees at
; $F000-$FFFF. Only 4K fits there at once, so an 8K cart keeps two banks and swaps
; which one shows. Two addresses near the top of the window are hotspots (an
; address the board watches; touching it switches banks). A read or a write both
; count as a touch, and the data value does not matter.
;
;   $1FF8  selects bank 0
;   $1FF9  selects bank 1
;
; The cart decodes only 13 address lines, so each hotspot also answers at its
; mirror near the top of the window ($FFF8/$FFF9), which is where the CPU reaches
; it. The switch takes effect on the next bus cycle: the instruction fetched
; right after a hotspot access already comes from the new bank.
;
;   CODE $01 = write $1FF8 did not page in bank 0
;        $02 = write $1FF9 did not page in bank 1
;        $03 = write $1FF8 did not return to the home bank
;        $04 = read (bit) $1FF9 did not page in bank 1
;        $05 = read (bit) $1FF8 did not return to the home bank
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: F8

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8                ; touch -> select bank 0  (mirror of $1FF8)
HOTSPOT1 = $FFF9                ; touch -> select bank 1  (mirror of $1FF9)
SIG      = $FC00                ; per-bank signature byte (mid-bank, clear of $FFxx)

ENTRY    = $F000                ; stub entry (reset target), identical in both banks
PROBE    = $F006                ; probe routine (jsr target), after the 6-byte entry

SIGA     = $90                  ; signature read with bank 0 write-selected
SIGB     = $91                  ; signature read with bank 1 write-selected
SIGWH    = $92                  ; signature after write-strobing home
SIGRD    = $93                  ; signature after read-strobing bank 1
SIGRH    = $94                  ; signature after read-strobing home

; The shared stub — emitted identically into both banks. First strobe with
; sta (a write) to walk both banks, then strobe with bit (a read) to prove a
; read access pages a bank too. nop nop lets each switch settle before the read.
        MAC STUB
        bit HOTSPOT0            ; ENTRY ($F000): power-on bank is undefined -> force bank 0
        jmp Main                ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F006): writes page the bank...
        sta HOTSPOT0            ; write -> select bank 0
        nop                     ; let the switch settle before trusting the bank
        nop
        lda SIG                 ; bank 0's signature -> SIGA
        sta SIGA
        sta HOTSPOT1            ; write -> select bank 1 (the next fetch comes from
        nop                     ;   bank 1's identical stub, so it runs undisturbed)
        nop
        lda SIG                 ; bank 1's signature -> SIGB
        sta SIGB
        sta HOTSPOT0            ; write -> back to the home bank (bank 0)
        nop
        nop
        lda SIG                 ; home signature -> SIGWH
        sta SIGWH
        ; ...and reads page the bank just the same
        bit HOTSPOT1            ; read -> select bank 1
        nop
        nop
        lda SIG                 ; bank 1's signature -> SIGRD
        sta SIGRD
        bit HOTSPOT0            ; read -> back to the home bank
        nop
        nop
        lda SIG                 ; home signature -> SIGRH
        sta SIGRH
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

        jsr PROBE                       ; collect a signature after every strobe
        ASSERT_EQ SIGA,  $A0, $01       ; write $1FF8 -> bank 0 -> expect $A0
        ASSERT_EQ SIGB,  $B1, $02       ; write $1FF9 -> bank 1 -> expect $B1
        ASSERT_EQ SIGWH, $A0, $03       ; write $1FF8 returned home -> expect $A0
        ASSERT_EQ SIGRD, $B1, $04       ; read  $1FF9 -> bank 1 -> expect $B1
        ASSERT_EQ SIGRH, $A0, $05       ; read  $1FF8 returned home -> expect $A0

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
