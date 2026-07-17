; bank-0fa0 — the 0FA0 board (Brazilian "Fotomania", 8K) switches its two 4K
; banks from hotspots down in low memory, decoded so loosely that a whole family
; of addresses aliases each one.
;
; The cartridge answers every access that has address line A12 high: the 4K
; window $F000-$FFFF, filled from one of two 4K banks. The select hotspots
; (addresses the board watches; an access to one switches banks) do not live in
; that window: they sit in the $0000-$0FFF TIA/RIOT space, and the cart watches
; the bus for them — any access, read or write, the data value does not matter,
; flips the bank on the next cycle.
;
; The board watches only six address lines — A12, A10, A9, A7, A6, A5 — and
; ignores the rest. It switches when those six match one of two patterns:
;       bank 0:  A12=0 A10=1 A9=1 A7=1 A6=0 A5=1   (base address $06A0)
;       bank 1:  A12=0 A10=1 A9=1 A7=1 A6=1 A5=0   (base address $06C0)
;
; The unwatched lines — A11, A8, and A4..A0 — are don't-cares, so each pattern
; covers a whole family of addresses. Toggling A11 ($800) and A8 ($100) gives the
; four page variants the board intercepts for each bank:
;       $06A0  $07A0  $0EA0  $0FA0   all -> bank 0   ($0FA0 gives the board its name)
;       $06C0  $07C0  $0EC0  $0FC0   all -> bank 1
; The low five bits A4..A0 are free too, so $06A0..$06BF all read as bank 0. An
; address on an intercepted page whose A5/A6 miss both patterns does not switch:
; $06E0 (A6=1 and A5=1) matches neither and leaves the bank alone.
;
;   CODE $01 = read  $06A0 did not page in bank 0
;        $02 = read  $06C0 did not page in bank 1
;        $03 = write $06A0 did not page in bank 0 (writes switch too)
;        $04 = write $06C0 did not page in bank 1
;        $05 = alias $0FA0 did not page in bank 0 (A11+A8 don't-cares)
;        $06 = alias $0EA0 did not page in bank 0 (A11 don't-care)
;        $07 = alias $0FC0 did not page in bank 1
;        $08 = alias $07C0 did not page in bank 1 (A8 don't-care)
;        $09 = near-miss $06E0 wrongly switched while parked in bank 1
;        $0A = near-miss $06E0 wrongly switched while parked in bank 0
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: 0FA0

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HS0    = $06A0                  ; access -> bank 0
HS1    = $06C0                  ; access -> bank 1
A0_1   = $0FA0                  ; alias of HS0 (A11+A8 set) -> bank 0
A0_2   = $0EA0                  ; alias of HS0 (A11 set)    -> bank 0
B1_1   = $0FC0                  ; alias of HS1 (A11+A8 set) -> bank 1
B1_2   = $07C0                  ; alias of HS1 (A8 set)     -> bank 1
MISS   = $06E0                  ; A6=1 AND A5=1 -> matches neither -> no switch
SIG    = $FC00                  ; per-bank signature (mid-bank, clear of stub/vectors)

ENTRY  = $F000                  ; stub entry (reset target), identical in both banks
PROBE  = $F006                  ; probe routine (jsr target), after the 6-byte entry

; probe result cells
FB0    = $90                    ; read  $06A0 -> bank 0
FB1    = $91                    ; read  $06C0 -> bank 1
FW0    = $92                    ; write $06A0 -> bank 0
FW1    = $93                    ; write $06C0 -> bank 1
FA0A   = $94                    ; alias $0FA0 -> bank 0
FA0B   = $95                    ; alias $0EA0 -> bank 0
FA1A   = $96                    ; alias $0FC0 -> bank 1
FA1B   = $97                    ; alias $07C0 -> bank 1
FNM1   = $98                    ; near-miss $06E0 while parked bank 1
FNM0   = $99                    ; near-miss $06E0 while parked bank 0

; The shared stub — byte-identical in both banks, so execution can cross a select
; (the switch takes effect on the next cycle). The probe walks both banks by read
; and write strobe, then the aliases and near-misses. nop nop lets a switch settle
; before the signature read.
        MAC STUB
        bit HS0                         ; ENTRY ($F000): power-on bank is undefined ->
                                        ;   force bank 0 (read strobe $06A0)
        jmp Main                        ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F006): read-strobe walk
        bit HS0                         ; read $06A0 -> bank 0
        nop
        nop
        lda SIG
        sta FB0
        bit HS1                         ; read $06C0 -> bank 1
        nop
        nop
        lda SIG
        sta FB1
        ; write-strobe walk (A7=1 A9=1, so the incidental write lands in RIOT
        ; I/O; A=0 keeps that poke benign)
        lda #0
        sta HS0                         ; write $06A0 -> bank 0
        nop
        nop
        lda SIG
        sta FW0
        lda #0
        sta HS1                         ; 8D C0 06 : write $06C0 -> bank 1
        nop
        nop
        lda SIG
        sta FW1
        ; aliases of $06A0 (park bank 1 first, so a real switch is visible)
        bit HS1
        nop
        nop
        bit A0_1                        ; $0FA0 -> bank 0
        nop
        nop
        lda SIG
        sta FA0A
        bit HS1
        nop
        nop
        bit A0_2                        ; $0EA0 -> bank 0
        nop
        nop
        lda SIG
        sta FA0B
        ; aliases of $06C0 (park bank 0 first)
        bit HS0
        nop
        nop
        bit B1_1                        ; $0FC0 -> bank 1
        nop
        nop
        lda SIG
        sta FA1A
        bit HS0
        nop
        nop
        bit B1_2                        ; $07C0 -> bank 1
        nop
        nop
        lda SIG
        sta FA1B
        ; near-miss: parked in bank 1, an access to $06E0 must not switch
        bit HS1
        nop
        nop
        bit MISS                        ; $06E0 -> no match -> stay bank 1
        nop
        nop
        lda SIG
        sta FNM1
        ; near-miss: parked in bank 0, $06E0 must not switch
        bit HS0
        nop
        nop
        bit MISS                        ; $06E0 -> no match -> stay bank 0
        nop
        nop
        lda SIG
        sta FNM0
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
        ASSERT_EQ FB0,  $A0, $01        ; read  $06A0 -> bank 0
        ASSERT_EQ FB1,  $B1, $02        ; read  $06C0 -> bank 1
        ASSERT_EQ FW0,  $A0, $03        ; write $06A0 -> bank 0
        ASSERT_EQ FW1,  $B1, $04        ; write $06C0 -> bank 1
        ASSERT_EQ FA0A, $A0, $05        ; alias $0FA0 -> bank 0
        ASSERT_EQ FA0B, $A0, $06        ; alias $0EA0 -> bank 0
        ASSERT_EQ FA1A, $B1, $07        ; alias $0FC0 -> bank 1
        ASSERT_EQ FA1B, $B1, $08        ; alias $07C0 -> bank 1
        ASSERT_EQ FNM1, $B1, $09        ; near-miss $06E0: stayed bank 1
        ASSERT_EQ FNM0, $A0, $0A        ; near-miss $06E0: stayed bank 0
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
