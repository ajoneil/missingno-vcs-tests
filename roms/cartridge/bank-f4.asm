; bank-f4 — the F4 board (32K) holds eight 4K banks and shows one at a time;
; touching a hotspot switches which bank is visible.
;
; The cart answers whenever address line A12 is high: a 4K window the CPU sees at
; $F000-$FFFF. Only 4K fits there at once, so a 32K cart keeps eight banks and
; swaps which one shows. Eight addresses near the top of the window are hotspots
; (an address the board watches; touching it switches banks). A read or a write
; both count as a touch, and the data value does not matter.
;
;   $1FF4  selects bank 0        $1FF8  selects bank 4
;   $1FF5  selects bank 1        $1FF9  selects bank 5
;   $1FF6  selects bank 2        $1FFA  selects bank 6
;   $1FF7  selects bank 3        $1FFB  selects bank 7
;
; The cart decodes only 13 address lines, so each hotspot also answers at its
; mirror near the top of the window ($FFF4..$FFFB), which is where the CPU
; reaches it. The switch takes effect on the next bus cycle: the instruction
; fetched right after a hotspot access already comes from the new bank.
;
;   CODE $01..$08 = write $1FF4..$1FFB did not page in bank 0..7
;        $09 = write $1FF4 did not return to the home bank
;        $0A = read (bit) $1FFB did not page in bank 7
;        $0B = read (bit) $1FF4 did not return to the home bank
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: F4

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF4                ; -> bank 0 (home)
HOTSPOT1 = $FFF5
HOTSPOT2 = $FFF6
HOTSPOT3 = $FFF7
HOTSPOT4 = $FFF8
HOTSPOT5 = $FFF9
HOTSPOT6 = $FFFA
HOTSPOT7 = $FFFB
SIG      = $FC00                ; per-bank signature (mid-bank, clear of $FFxx)

ENTRY    = $F000                ; stub entry (reset target), identical in every bank
PROBE    = $F006                ; probe routine (jsr target), after the 6-byte entry

SIGBASE  = $90                  ; write-selected readbacks for banks 0..7 -> $90..$97
SIGWH    = $98                  ; signature after write-strobing home
SIGRD    = $99                  ; signature after read-strobing bank 7
SIGRH    = $9A                  ; signature after read-strobing home

; The shared stub — emitted identically into all eight banks at the same address,
; so execution can cross a switch and carry on. sta-strobe each hotspot, let the
; switch settle (nop nop), read the now-paged signature; then bit-strobe (read) a
; hotspot to prove a read access pages a bank too: a board that switched only on
; writes would pass the write cells and fail the read ones.
        MAC STUB
        bit HOTSPOT0            ; ENTRY ($F000): power-on bank is undefined -> force bank 0
        jmp Main                ; ...then run the test (Main lives in bank 0)
        ; PROBE: walk every bank, saving its signature
        sta HOTSPOT0            ; select bank 0
        nop                     ; settle
        nop
        lda SIG                 ; bank 0 signature -> SIGBASE+0
        sta SIGBASE+0
        sta HOTSPOT1            ; select bank 1
        nop
        nop
        lda SIG                 ; bank 1 signature -> SIGBASE+1
        sta SIGBASE+1
        sta HOTSPOT2            ; select bank 2
        nop
        nop
        lda SIG                 ; bank 2 signature -> SIGBASE+2
        sta SIGBASE+2
        sta HOTSPOT3            ; select bank 3
        nop
        nop
        lda SIG                 ; bank 3 signature -> SIGBASE+3
        sta SIGBASE+3
        sta HOTSPOT4            ; select bank 4
        nop
        nop
        lda SIG                 ; bank 4 signature -> SIGBASE+4
        sta SIGBASE+4
        sta HOTSPOT5            ; select bank 5
        nop
        nop
        lda SIG                 ; bank 5 signature -> SIGBASE+5
        sta SIGBASE+5
        sta HOTSPOT6            ; select bank 6
        nop
        nop
        lda SIG                 ; bank 6 signature -> SIGBASE+6
        sta SIGBASE+6
        sta HOTSPOT7            ; select bank 7
        nop
        nop
        lda SIG                 ; bank 7 signature -> SIGBASE+7
        sta SIGBASE+7
        sta HOTSPOT0            ; write -> back to the home bank
        nop
        nop
        lda SIG                 ; home signature -> SIGWH
        sta SIGWH
        ; reads page the bank just the same
        bit HOTSPOT7            ; read -> select bank 7
        nop
        nop
        lda SIG                 ; bank 7 signature -> SIGRD
        sta SIGRD
        bit HOTSPOT0            ; read -> back to the home bank
        nop
        nop
        lda SIG                 ; home signature -> SIGRH
        sta SIGRH
        rts
        ENDM

; a bank body: shared stub + signature + vectors, at the given file base
        MAC BANK
        ORG {1}
        RORG $F000
        STUB
        ORG {1}+$C00
        RORG $FC00
        .byte {2}
        ORG {1}+$FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        CLEAN_START
        TEST_BEGIN
        jsr PROBE               ; collect a signature from each of the eight banks
        ASSERT_EQ SIGBASE+0, $A0, $01   ; bank 0 -> expect $A0
        ASSERT_EQ SIGBASE+1, $A1, $02   ; bank 1 -> expect $A1
        ASSERT_EQ SIGBASE+2, $A2, $03   ; bank 2 -> expect $A2
        ASSERT_EQ SIGBASE+3, $A3, $04   ; bank 3 -> expect $A3
        ASSERT_EQ SIGBASE+4, $A4, $05   ; bank 4 -> expect $A4
        ASSERT_EQ SIGBASE+5, $A5, $06   ; bank 5 -> expect $A5
        ASSERT_EQ SIGBASE+6, $A6, $07   ; bank 6 -> expect $A6
        ASSERT_EQ SIGBASE+7, $A7, $08   ; bank 7 -> expect $A7
        ASSERT_EQ SIGWH, $A0, $09       ; write $1FF4 returned home -> expect $A0
        ASSERT_EQ SIGRD, $A7, $0A       ; read  $1FFB -> bank 7 -> expect $A7
        ASSERT_EQ SIGRH, $A0, $0B       ; read  $1FF4 returned home -> expect $A0
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

; -------------------------------------------------------------- banks 1..7 (data)
        SEG BANK1
        BANK $1000, $A1
        SEG BANK2
        BANK $2000, $A2
        SEG BANK3
        BANK $3000, $A3
        SEG BANK4
        BANK $4000, $A4
        SEG BANK5
        BANK $5000, $A5
        SEG BANK6
        BANK $6000, $A6
        SEG BANK7
        BANK $7000, $A7
