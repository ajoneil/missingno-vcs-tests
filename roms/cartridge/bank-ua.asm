; bank-ua — the UA Ltd board (8K): two 4K banks, switched by hotspots (an
; address the board watches; touching it switches banks) that live outside the
; cartridge window and are decoded so loosely that many addresses alias each one.
;
; The 6507 gives the cart a 4K window at $F000-$FFFF (any access with A12 high),
; filled from one of two 4K banks. The select hotspots do not sit in that
; window: they are down in low memory, where A12=0.
;
;   $0220   select bank 0
;   $0240   select bank 1
;
; The cart has no chip-select down there, so it just watches the bus: any
; access to a hotspot — read or write, data value irrelevant — flips the bank.
; The switch takes effect on the next bus cycle, so code that runs across a
; switch must be byte-identical in both banks.
;
; The decode is partial: the board checks only four address lines and ignores
; the rest.
;
;   bank 0   A12=0  A9=1  A6=0  A5=1    (canonical address $0220)
;   bank 1   A12=0  A9=1  A6=1  A5=0    (canonical address $0240)
;
; So each hotspot is a whole family of addresses. $0320 and $02A0 both match
; bank 0's pattern; $0340 and $02C0 both match bank 1's.
;
; Because the hotspots have A12=0, they also land on TIA and RIOT mirrors (a
; write to $0220 pokes TIA HMP0, $0240 pokes VSYNC).
;
;   CODE $01 = write $0220 did not page in bank 0
;        $02 = write $0240 did not page in bank 1
;        $03 = write $0220 did not return to bank 0
;        $04 = read (bit) $0240 did not page in bank 1 (reads switch too)
;        $05 = read (bit) $0220 did not return to bank 0
;        $06 = alias $0320 did not page in bank 0 (A8 is a don't-care)
;        $07 = alias $02A0 did not page in bank 0 (A7 is a don't-care)
;        $08 = alias $0340 did not page in bank 1
;        $09 = alias $02C0 did not page in bank 1
;
; Cells $06-$09 (the aliases) are contested: some implementations decode only the
; exact addresses $0220/$0240 and leave the bank unchanged on an alias. The test
; asserts the loose four-line decode. Untested on hardware.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: UA

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

UA_B0  = $0220                  ; access -> select bank 0
UA_B1  = $0240                  ; access -> select bank 1
A0_1   = $0320                  ; alias of $0220 (A8 set, don't-care) -> bank 0
A0_2   = $02A0                  ; alias of $0220 (A7 set, don't-care) -> bank 0
B1_1   = $0340                  ; alias of $0240 -> bank 1
B1_2   = $02C0                  ; alias of $0240 -> bank 1
SIG    = $FC00                  ; per-bank signature (mid-bank, clear of stub/vectors)

ENTRY  = $F000                  ; stub entry (reset target), identical in both banks
PROBE  = $F006                  ; probe routine (jsr target), after the 6-byte entry

; probe result cells
UB0    = $90                    ; write $0220 -> bank 0
UB1    = $91                    ; write $0240 -> bank 1
UBH    = $92                    ; write $0220 -> home
URD1   = $93                    ; read  $0240 -> bank 1
URD0   = $94                    ; read  $0220 -> home
UAL0A  = $95                    ; alias $0320 -> bank 0
UAL0B  = $96                    ; alias $02A0 -> bank 0
UAL1A  = $97                    ; alias $0340 -> bank 1
UAL1B  = $98                    ; alias $02C0 -> bank 1

; The shared stub — byte-identical in both banks, so a switch mid-stub still
; fetches the same code. Entry forces bank 0; the probe walks both banks by write
; strobe, re-selects by read strobe, then exercises two aliases of each hotspot.
; nop nop lets a switch settle before the signature read. No frame is drawn while
; the probe runs, so the incidental TIA/RIOT pokes do nothing visible; the probe
; still keeps A=$00 on write strobes and uses read strobes (bit) for the A7=1
; RIOT-mirror aliases. The named hotspots are asserted before the aliases, so a
; board decoding only the exact addresses still passes the core cells.
        MAC STUB
        bit UA_B0                       ; ENTRY ($F000): power-on bank is undefined
                                        ;   -> force bank 0 (read strobe $0220)
        jmp Main                        ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F006): write-strobe walk (A=0 keeps the incidental TIA writes benign)
        lda #0
        sta UA_B0                       ; write $0220 -> bank 0
        nop
        nop
        lda SIG
        sta UB0
        sta UA_B1                       ; 8D 40 02 : write $0240 -> bank 1
        nop
        nop
        lda SIG
        sta UB1
        lda #0
        sta UA_B0                       ; write $0220 -> back to the home bank
        nop
        nop
        lda SIG
        sta UBH
        ; read strobes: an access of either kind switches
        bit UA_B1                       ; read $0240 -> bank 1
        nop
        nop
        lda SIG
        sta URD1
        bit UA_B0                       ; read $0220 -> home
        nop
        nop
        lda SIG
        sta URD0
        ; aliases of $0220 (park bank 1 first, so a real switch is visible)
        bit UA_B1
        nop
        nop
        bit A0_1                        ; $0320 -> bank 0
        nop
        nop
        lda SIG
        sta UAL0A
        bit UA_B1
        nop
        nop
        bit A0_2                        ; $02A0 -> bank 0
        nop
        nop
        lda SIG
        sta UAL0B
        ; aliases of $0240 (park bank 0 first)
        bit UA_B0
        nop
        nop
        bit B1_1                        ; $0340 -> bank 1
        nop
        nop
        lda SIG
        sta UAL1A
        bit UA_B0
        nop
        nop
        bit B1_2                        ; $02C0 -> bank 1
        nop
        nop
        lda SIG
        sta UAL1B
        bit UA_B0                       ; restore the home bank before returning
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

        ASSERT_EQ UB0,  $A0, $01        ; write $0220 -> bank 0
        ASSERT_EQ UB1,  $B1, $02        ; write $0240 -> bank 1
        ASSERT_EQ UBH,  $A0, $03        ; write $0220 returned home
        ASSERT_EQ URD1, $B1, $04        ; read  $0240 -> bank 1
        ASSERT_EQ URD0, $A0, $05        ; read  $0220 returned home
        ASSERT_EQ UAL0A,$A0, $06        ; alias $0320 -> bank 0
        ASSERT_EQ UAL0B,$A0, $07        ; alias $02A0 -> bank 0
        ASSERT_EQ UAL1A,$B1, $08        ; alias $0340 -> bank 1
        ASSERT_EQ UAL1B,$B1, $09        ; alias $02C0 -> bank 1

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
