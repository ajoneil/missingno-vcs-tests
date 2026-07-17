; bank-f6 — the F6 board (16K) holds four 4K banks and shows one at a time;
; touching a hotspot switches which bank is visible.
;
; The cart answers whenever address line A12 is high: a 4K window the CPU sees at
; $F000-$FFFF. Only 4K fits there at once, so a 16K cart keeps four banks and
; swaps which one shows. Four addresses near the top of the window are hotspots
; (an address the board watches; touching it switches banks). A read or a write
; both count as a touch, and the data value does not matter.
;
;   $1FF6  selects bank 0
;   $1FF7  selects bank 1
;   $1FF8  selects bank 2
;   $1FF9  selects bank 3
;
; The cart decodes only 13 address lines, so each hotspot also answers at its
; mirror near the top of the window ($FFF6..$FFF9), which is where the CPU
; reaches it. The switch takes effect on the next bus cycle: the instruction
; fetched right after a hotspot access already comes from the new bank.
;
;   CODE $01..$04 = write $1FF6..$1FF9 did not page in bank 0..3
;        $05 = write $1FF6 did not return to the home bank
;        $06 = read (bit) $1FF9 did not page in bank 3
;        $07 = read (bit) $1FF6 did not return to the home bank
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: F6

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF6                ; -> bank 0 (home)
HOTSPOT1 = $FFF7                ; -> bank 1
HOTSPOT2 = $FFF8                ; -> bank 2
HOTSPOT3 = $FFF9                ; -> bank 3
SIG      = $FC00                ; per-bank signature (mid-bank, clear of $FFxx)

ENTRY    = $F000                ; stub entry (reset target), identical in every bank
PROBE    = $F006                ; probe routine (jsr target), after the 6-byte entry

SIGA     = $90                  ; write-selected readbacks for banks 0..3
SIGB     = $91
SIGC     = $92
SIGD     = $93
SIGWH    = $94                  ; signature after write-strobing home
SIGRD    = $95                  ; signature after read-strobing bank 3
SIGRH    = $96                  ; signature after read-strobing home

; The shared stub — emitted identically into all four banks at the same address,
; so execution can cross a switch and carry on. sta-strobe each hotspot, let the
; switch settle (nop nop), read the now-paged signature; then bit-strobe (read) a
; hotspot to prove a read access pages a bank too: a board that switched only on
; writes would pass the write cells and fail the read ones.
        MAC STUB
        bit HOTSPOT0            ; ENTRY ($F000): power-on bank is undefined -> force bank 0
        jmp Main                ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F006): walk every bank, saving its signature
        sta HOTSPOT0            ; select bank 0
        nop                     ; settle
        nop
        lda SIG                 ; bank 0 signature -> SIGA
        sta SIGA
        sta HOTSPOT1            ; select bank 1
        nop
        nop
        lda SIG                 ; bank 1 signature -> SIGB
        sta SIGB
        sta HOTSPOT2            ; select bank 2
        nop
        nop
        lda SIG                 ; bank 2 signature -> SIGC
        sta SIGC
        sta HOTSPOT3            ; select bank 3
        nop
        nop
        lda SIG                 ; bank 3 signature -> SIGD
        sta SIGD
        sta HOTSPOT0            ; write -> back to the home bank
        nop
        nop
        lda SIG                 ; home signature -> SIGWH
        sta SIGWH
        ; reads page the bank just the same
        bit HOTSPOT3            ; read -> select bank 3
        nop
        nop
        lda SIG                 ; bank 3 signature -> SIGRD
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
        jsr PROBE               ; collect a signature from each of the four banks
        ASSERT_EQ SIGA, $A0, $01        ; bank 0 -> expect $A0
        ASSERT_EQ SIGB, $A1, $02        ; bank 1 -> expect $A1
        ASSERT_EQ SIGC, $A2, $03        ; bank 2 -> expect $A2
        ASSERT_EQ SIGD, $A3, $04        ; bank 3 -> expect $A3
        ASSERT_EQ SIGWH, $A0, $05       ; write $1FF6 returned home -> expect $A0
        ASSERT_EQ SIGRD, $A3, $06       ; read  $1FF9 -> bank 3 -> expect $A3
        ASSERT_EQ SIGRH, $A0, $07       ; read  $1FF6 returned home -> expect $A0
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1
        SEG BANK1
        ORG $1000
        RORG $F000
        STUB
        ORG $1C00
        RORG $FC00
        .byte $A1
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 2
        SEG BANK2
        ORG $2000
        RORG $F000
        STUB
        ORG $2C00
        RORG $FC00
        .byte $A2
        ORG $2FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 3
        SEG BANK3
        ORG $3000
        RORG $F000
        STUB
        ORG $3C00
        RORG $FC00
        .byte $A3
        ORG $3FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
