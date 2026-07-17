; bank-mdm — the MDM Menu Driven Megacart board (Edwin Blink, homebrew; up to
; 512K) selects a bank by the low byte of a low-memory access, and has a one-way
; lock: once a bank with bit 7 set is selected, all switching freezes until a
; console reset. This image is a modest 32K / 8 banks.
;
; The cartridge answers every access with address line A12 high: the 4K window
; $F000-$FFFF, filled from one of 8 (here) 4K banks. The board watches the low
; band $0800-$0BFF: it acts on any access there — read or write, data value does
; not matter. The selected bank is the low byte of the address, so within the
; band the page bits A9,A8 are don't-cares:
;       $0800 $0900 $0A00 $0B00  all select bank 0
;       $0807 $0907 $0A07 $0B07  all select bank 7
; With 8 banks the value wraps: bank = value mod 8 (the remainder after dividing
; by 8). A10 bounds the band at $0BFF; $0C00 (A10=1) is not intercepted and does
; not switch — the near-miss above the band.
;
; The lock: selecting any value above 127 (bit 7 set) performs that one switch and
; then freezes the board — every later select returns without effect until reset.
; The switch still happens first, through the same value mod 8: selecting value
; $80 pages in bank 0 (128 mod 8 = 0) and locks.
;
;   CODE $01 = write $0801 did not page in bank 1
;        $02 = read  $0802 did not page in bank 2 (reads switch too)
;        $03 = write $0807 did not page in bank 7
;        $04 = alias $0901 did not page in bank 1 (A8 don't-care)
;        $05 = near-miss $0C00 (A10=1) wrongly switched from bank 7
;        $06 = lock select $0880 (value $80) did not page in bank 0 (128 mod 8)
;        $07 = a post-lock select $0801 was not frozen (bank changed)
;        $08 = a post-lock read select $0807 was not frozen
;        $09 = the lock did not persist across many further selects
;
; Self-test: verdict in RESULT ($80); region-independent.
;
; mapper: MDM

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HS0     = $0800                 ; access -> select bank 0 (entry force)
SEL1    = $0801                 ; select bank 1
SEL2    = $0802                 ; select bank 2
SEL3    = $0803                 ; select bank 3
SEL4    = $0804                 ; select bank 4
SEL5    = $0805                 ; select bank 5
SEL7    = $0807                 ; select bank 7
ALIAS1  = $0901                 ; A8 don't-care twin of $0801 -> bank 1
MISS    = $0C00                 ; A10=1: above the $0800-$0BFF band -> not a hotspot
LOCK    = $0880                 ; value $80: pages physical bank 0 (128 mod 8) and locks
SIG     = $FC00                 ; per-bank signature ($A0+bank), mid-bank

ENTRY   = $F000                 ; stub entry (reset target), identical in all 8 banks
PROBE   = $F006                 ; probe routine (jsr target), after the 6-byte entry

; probe result cells
M1      = $90                   ; write $0801 -> bank 1
M2      = $91                   ; read  $0802 -> bank 2
MAL     = $92                   ; alias $0901 -> bank 1
M7      = $93                   ; write $0807 -> bank 7
MNM     = $94                   ; near-miss $0C00 -> stayed bank 7
MLK     = $95                   ; lock select $0880 -> bank 0
ML1     = $96                   ; post-lock $0801 -> frozen (bank 0)
ML2     = $97                   ; post-lock $0807 -> frozen (bank 0)
ML9     = $98                   ; lock persists across many selects (bank 0)

; The shared stub — emitted byte-identical into all 8 banks so execution can cross
; a bank select and keep fetching valid code at the same address.
        MAC STUB
        bit HS0                         ; ENTRY ($F000): power-on bank is undefined
                                        ;   -> force bank 0 (read strobe $0800)
        jmp Main                        ; ...then run the test (Main lives in bank 0)
        ; --- PROBE ($F006), entered in bank 0 ---
        ; select walk (A=0 keeps the incidental TIA pokes benign)
        lda #0
        sta SEL1                        ; write $0801 -> bank 1
        lda SIG
        sta M1
        bit SEL2                        ; read  $0802 -> bank 2
        lda SIG
        sta M2
        bit ALIAS1                      ; read  $0901 (A8 don't-care) -> bank 1
        lda SIG
        sta MAL
        lda #0
        sta SEL7                        ; write $0807 -> bank 7
        lda SIG
        sta M7
        bit MISS                        ; $0C00 (A10=1) not intercepted -> stay bank 7
        lda SIG
        sta MNM
        ; --- the lock (runs last: it cannot be undone without a reset) ---
        ; Locking into bank 0 is deliberate: the board freezes on the home bank,
        ; where Main and the result screen live, so the probe can confirm the
        ; freeze and still return into reachable code.
        bit LOCK                        ; $0880: value $80 -> physical bank 0 and freeze
        lda SIG
        sta MLK
        lda #0
        sta SEL1                        ; post-lock select attempt -> frozen, stays bank 0
        lda SIG
        sta ML1
        bit SEL7                        ; post-lock read select -> frozen, stays bank 0
        lda SIG
        sta ML2
        ; the freeze persists across any number of further attempts
        lda #0
        sta SEL2
        bit SEL3
        sta SEL4
        bit SEL5
        lda SIG
        sta ML9
        rts                             ; already locked in bank 0 -> returns into Main
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
        ASSERT_EQ M1,   $A1, $01        ; write $0801 -> bank 1
        ASSERT_EQ M2,   $A2, $02        ; read  $0802 -> bank 2
        ASSERT_EQ M7,   $A7, $03        ; write $0807 -> bank 7
        ASSERT_EQ MAL,  $A1, $04        ; alias $0901 -> bank 1
        ASSERT_EQ MNM,  $A7, $05        ; near-miss $0C00: stayed bank 7
        ASSERT_EQ MLK,  $A0, $06        ; lock select $0880 -> bank 0 (128 mod 8)
        ASSERT_EQ ML1,  $A0, $07        ; post-lock select frozen
        ASSERT_EQ ML2,  $A0, $08        ; post-lock read select frozen
        ASSERT_EQ ML9,  $A0, $09        ; lock persisted

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0                       ; bank 0 signature
        .byte "MDMC"                    ; MDM identification key (searched for in the first 8K)
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ------------------------------------------------------------- banks 1..7 (data)
; Each carries the identical stub (execution crosses into it on every select) plus
; a distinct signature $A0+bank. The macro emits stub + signature + vectors.
        MAC DATABANK            ; {1} = file base, {2} = signature byte
        SEG
        ORG {1}
        RORG $F000
        STUB
        ORG {1} + $0C00
        RORG $FC00
        .byte {2}
        ORG {1} + $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
        ENDM

        DATABANK $1000, $A1
        DATABANK $2000, $A2
        DATABANK $3000, $A3
        DATABANK $4000, $A4
        DATABANK $5000, $A5
        DATABANK $6000, $A6
        DATABANK $7000, $A7
