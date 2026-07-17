; ram-superchip — the Superchip (SARA) adds cart RAM under the bottom of the
; window, split into a write port and a read port.
;
; This is an F8 board (two 4K banks; $1FF8 selects bank 0, $1FF9 selects bank 1,
; each reached at its $FFF8/$FFF9 mirror) carrying an extra 128 bytes of static
; RAM. The cart edge has address lines and a data bus but no read/write line, so
; the cart cannot tell a load from a store by the bus alone. The Superchip splits
; the RAM into two ports so the address itself says which:
;
;   $F000-$F07F  write port  (a bus access latches the data bus into RAM)
;   $F080-$F0FF  read port   (a bus access drives the addressed RAM byte out)
;
; Both ports reach the same 128 cells: storing to $F000+n and loading from
; $F080+n touch cell n. Because RAM occupies $F000-$F0FF, the ROM bytes under it
; are shadowed (hidden) — a read-port load returns RAM, never the image. The RAM
; sits outside the banked ROM, so an F8 bank switch never disturbs it.
;
;   CODE $01 = write $F000 did not read back through $F080
;        $02 = write $F001 did not read back through $F081 (offset n preserved)
;        $03 = write $F07F (last cell) did not read back through $F0FF
;        $04 = read port returned the shadowed ROM byte, not the RAM value
;        $05 = RAM did not survive a switch to bank 1
;        $06 = a byte written under bank 1 was not visible under bank 0 (shared RAM)
;        $07 = RAM was not intact after switching back to bank 0
;        $08 = a read that landed on the write port did not clobber the cell with
;              the bus residue ($F0) — see the ghost-write note below
;
; Ghost-write note ($08): the split is decoded from the address alone, so the board
; cannot tell a load of a write-port address from a store to one. It takes the
; access for a store and latches the data bus into the cell — the load destroys the
; byte. A page-crossing indexed read puts the un-carried
; address on the bus for one cycle, and if that lands on the write port the cell is
; gone. Reading ROM corrupts RAM, and games have shipped with the bug.
;
; What lands in the cell is the bus residue: nothing drives the lines during the
; ghost cycle, so they hold the last byte driven — the operand high byte $F0 for
; the `lda $F080,y` here. A real PAL console confirmed that undriven loads keep
; the last bus byte (a rival model would read the effective address's low byte,
; $00). The destruction itself is untested here, for want of a Superchip board.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: F8SC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8               ; touch -> select bank 0 (mirror of $1FF8)
HOTSPOT1 = $FFF9               ; touch -> select bank 1 (mirror of $1FF9)

WRITE00  = $F000               ; RAM write port, cell 0
WRITE01  = $F001
WRITE02  = $F002
WRITE40  = $F040
WRITE7F  = $F07F               ; RAM write port, cell 127 (last)
READ80   = $F080               ; RAM read port, cell 0
READ81   = $F081
READ82   = $F082
READC0   = $F0C0               ; read port, cell 64 (ROM byte $E7 sits under it)
READFF   = $F0FF               ; RAM read port, cell 127 (last)

ENTRY    = $F100               ; stub entry (reset target), identical in both banks
                               ;   ($F000-$F0FF is RAM at run time: no code or
                               ;    vectors may live there)
PROBE    = $F106               ; probe routine (jsr target), after the 6-byte entry

ROMFILL  = $E7                 ; shadowed ROM under the RAM window (fingerprint fill);
                               ;   differs from every value the test writes, so a
                               ;   plain F8 board with no RAM reads back $E7 and fails

S80    = $90                   ; read-port readbacks collected in Main (bank 0)
S81    = $91
SFF    = $92
SC0    = $93
P_B1_80 = $97                  ; probe: $F080 read while bank 1 selected
P_B0_82 = $98                  ; probe: $F082 read (byte written under bank 1)
P_B0_80 = $99                  ; probe: $F080 read after the round trip
GHOST   = $9A                  ; cell 0 after a read landed on its write port

; The shared stub — emitted identically into both banks at $F100. The persistence
; probe writes cell 2 while bank 1 is paged in and reads it back under bank 0, so
; a correct board (RAM outside the banked ROM) shows the write in both banks.
        MAC STUB
        bit HOTSPOT0            ; ENTRY ($F100): power-on bank is undefined -> force bank 0
        jmp Main                ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F106): the RAM pattern is already written; cross a switch and back.
        sta HOTSPOT1            ; page in bank 1 (next fetch is bank 1's identical stub)
        nop                     ; let the switch settle
        nop
        lda READ80              ; RAM read port $F080 under bank 1 -> should still be $A5
        sta P_B1_80
        lda #$18
        sta WRITE02             ; write cell 2 = $18 while bank 1 is selected
        sta HOTSPOT0            ; page back to bank 0
        nop
        nop
        lda READ82              ; $F082 -> the $18 written under bank 1 (shared RAM)
        sta P_B0_82
        lda READ80              ; $F080 -> still $A5 after the round trip
        sta P_B0_80
        rts
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        REPEAT 256              ; ROM under the RAM window: 0-127 == 128-255 (SC fingerprint)
        .byte ROMFILL
        REPEND
        STUB                    ; ENTRY/PROBE at $F100
Main:
        CLEAN_START
        TEST_BEGIN

        lda #$A5                ; write the pattern through the write port
        sta WRITE00             ; cell 0
        lda #$3C
        sta WRITE01             ; cell 1
        lda #$5A
        sta WRITE7F             ; cell 127 (last)
        lda #$6D
        sta WRITE40             ; cell 64 (ROM byte $E7 lies under its read port)

        lda READ80              ; read them all back through the read port
        sta S80
        lda READ81
        sta S81
        lda READFF
        sta SFF
        lda READC0
        sta SC0

        ASSERT_EQ S80, $A5, $01         ; cell 0 written low, read high
        ASSERT_EQ S81, $3C, $02         ; cell 1 -> offset n carried across the port split
        ASSERT_EQ SFF, $5A, $03         ; cell 127 (last)
        ASSERT_EQ SC0, $6D, $04         ; RAM shadows the ROM ($E7) under $F0C0

        jsr PROBE                       ; persistence across an F8 bank switch
        ASSERT_EQ P_B1_80, $A5, $05     ; RAM survived the switch to bank 1
        ASSERT_EQ P_B0_82, $18, $06     ; bank-1 write visible under bank 0 (shared RAM)
        ASSERT_EQ P_B0_80, $A5, $07     ; RAM intact after switching home

        ; --- a read that lands on the write port latches the bus into the cell ---
        ; Runs last: it destroys cell 0, which $01/$05/$07 above rely on.
        ; `lda $F080,y` with y=$80 wants $F100, which crosses a page, so the 6502
        ; puts the un-carried address $F000 on the bus for one cycle while the ALU
        ; finishes the add. $F000 is the WRITE port, cell 0. The board reads
        ; direction off the address alone, takes that cycle for a store, and
        ; latches whatever the data bus holds. Nothing is driving it — the write
        ; port has no output and the ROM under it is shadowed — so the lines keep
        ; the last byte driven, which the fetch order makes the operand high byte.
        ldy #$80
        lda READ80,y                    ; B9 80 F0: wants $F100, ghost-writes $F000
        lda READ80                      ; cell 0 back through the read port
        sta GHOST
        ASSERT_EQ GHOST, $F0, $08       ; cell 0 clobbered with the residue, not $A5

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
        REPEAT 256              ; same fingerprint fill (every bank must satisfy it)
        .byte ROMFILL
        REPEND
        STUB                    ; byte-identical entry/probe
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
