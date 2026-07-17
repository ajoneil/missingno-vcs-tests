; dpc-bank — F8 program banking around the DPC chip. A Pitfall II cart is an 8K
; F8-banked program ROM plus the DPC ("Display Processor Chip"). The chip sits
; outside the banked ROM: it gates the program ROM's chip-enable, but its own
; state (the fetchers, their Top/Bottom limits and flags) belongs to neither
; bank. So paging the program ROM must switch code like a plain F8 board while
; leaving all DPC state untouched. This test proves both halves.
;
; F8 banking: two 4K banks share the CPU's $F000-$FFFF window. Touching hotspot
; $FFF8 pages in bank 0, $FFF9 pages in bank 1 (a hotspot is an address the board
; watches; touching it switches banks). The switch fires on the bus access, read
; or write, and the data does not matter. It takes effect on the next bus cycle,
; so code can run across a switch.
;
; The fetcher mechanism is explained in dpc-fetch. The chip's registers are
; reached through the $F000-$F07F mirror.
;
;   CODE $01 = write $FFF9 did not page in bank 1
;        $02 = write $FFF8 did not return to the home bank
;        $03 = read (bit) $FFF9 did not page in bank 1 (read access must switch too)
;        $04 = DF6 read from bank 1 wrong (the chip is outside the banked ROM)
;        $05 = DF6 pointer did not survive the switch (it reset instead of decrementing)
;        $06 = DF7 masked read wrong: flag not set in bank 0, or lost across the switch
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8               ; touch -> program bank 0 (mirror of $1FF8)
HOTSPOT1 = $FFF9               ; touch -> program bank 1 (mirror of $1FF9)
SIG      = $FC00               ; per-bank signature (mid-bank, clear of registers/hotspots/vectors)

; DPC register file (+x picks DFx). $F000-$F007 is never touched and music stays
; off, so the readings below are deterministic on every implementation.
DATA     = $F008              ; read DFx data unmasked (decrements)
MASKED   = $F010              ; read DFx data AND flag (decrements)
TOP      = $F040              ; write DFx Top (clears flag)
BOTTOM   = $F048              ; write DFx Bottom
CLOW     = $F050              ; write DFx counter low
CHIGH    = $F058              ; write DFx counter high (DF4=$F05C, DF5-7=$F05D-F)

ENTRY    = $F080              ; reset target, identical in both banks (clear of $F000-$F07F)
PROBE    = $F086              ; probe routine (after the 6-byte entry)

; probe results (collected across switches, checked by Main afterwards)
BW1      = $90               ; write $FFF9 -> bank 1 signature
BWH      = $91               ; write $FFF8 -> home signature
RD1      = $92               ; read  $FFF9 -> bank 1 signature
D6B      = $93               ; DF6 data read from bank 1
D6H      = $94               ; DF6 data read from home after the switch
D7A      = $95               ; DF7 masked read in bank 0 (flag set here)
D7B      = $96               ; DF7 masked read from bank 1 (flag survived?)

; The shared stub — byte-identical in both banks at $F080. nop/nop after each
; strobe lets the switch settle before the next trusted access.
        MAC STUB
        bit HOTSPOT0            ; ENTRY ($F080): power-on bank undefined -> force bank 0
        jmp Main                ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F086):
        ; --- hotspot walk: writes and reads both page a bank (cells 01-03) ---
        sta HOTSPOT1            ; write -> bank 1 (next fetch is bank 1's identical stub)
        nop
        nop
        lda SIG
        sta BW1
        sta HOTSPOT0            ; write -> home bank
        nop
        nop
        lda SIG
        sta BWH
        bit HOTSPOT1            ; read -> bank 1
        nop
        nop
        lda SIG
        sta RD1
        bit HOTSPOT0            ; read -> home
        nop
        nop
        ; --- DF6 responds from bank 1, and its pointer survives (cells 04-05) ---
        ; Main pre-loaded DF6 counter = $044 while bank 0 was live.
        sta HOTSPOT1            ; -> bank 1
        nop
        nop
        lda DATA+6             ; $F00E from bank 1: f($044)=$40, DF6 ptr -> $043
        sta D6B
        sta HOTSPOT0            ; -> home bank
        nop
        nop
        lda DATA+6             ; $F00E from home: f($043)=$47 (survived: it kept decrementing)
        sta D6H
        ; --- DF7 Top/Bottom/flag survive a switch (cell 06) ---
        ; Main set DF7 Top=$90/Bottom=$20/low=$90 and did one bank-0 masked read,
        ; which set the flag and left the pointer at $8F.
        sta HOTSPOT1            ; -> bank 1
        nop
        nop
        lda MASKED+7           ; $F017 from bank 1: flag still set -> data f($8F)=$87
        sta D7B
        sta HOTSPOT0            ; -> home bank
        nop
        nop
        rts
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        ds 128                 ; DPC register window: no code/vectors
        STUB                   ; ENTRY/PROBE at $F080
Main:
        CLEAN_START
        TEST_BEGIN

        ; Pre-load DPC state while bank 0 is live.
        lda #$44
        sta CLOW+6            ; DF6 counter low  = $44
        lda #$00
        sta CHIGH+6           ; $F05E: DF6 counter high, D4=0 music off -> DF6 c = $044

        lda #$90
        sta TOP+7            ; DF7 Top = $90 (clears flag)
        lda #$20
        sta BOTTOM+7         ; DF7 Bottom = $20
        lda #$00
        sta CHIGH+7          ; $F05F: DF7 counter high, D4=0 music off
        lda #$90
        sta CLOW+7           ; DF7 low = $90 == Top
        lda MASKED+7         ; bank-0 masked read: low==Top sets flag -> data f($90)=$99, ptr->$8F
        sta D7A

        jsr PROBE            ; walk banks, cross-bank DPC reads (crosses switches)

        ASSERT_EQ BW1, $B1, $01   ; write $FFF9 -> bank 1
        ASSERT_EQ BWH, $A0, $02   ; write $FFF8 -> home
        ASSERT_EQ RD1, $B1, $03   ; read  $FFF9 -> bank 1
        ASSERT_EQ D6B, $40, $04   ; DF6 read from bank 1 (chip outside the banked ROM)
        ASSERT_EQ D6H, $47, $05   ; DF6 pointer survived the switch (kept decrementing)
        ASSERT_EQ D7A, $99, $06   ; DF7 flag set, bank-0 masked read returned data
        ASSERT_EQ D7B, $87, $06   ; DF7 flag survived the switch: bank-1 masked read = data

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0                ; bank 0 signature
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        ds 128
        STUB                   ; byte-identical entry+probe at $F080
        ORG $1C00
        RORG $FC00
        .byte $B1                ; bank 1 signature (differs)
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
