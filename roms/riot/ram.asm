; ram — the RIOT's 128 bytes of on-chip RAM store and return each byte
; faithfully, every cell independent of its neighbours.
;
; The RIOT (the 6532 support chip that sits beside the TIA) contains 128 bytes
; of static RAM — the console's only read/write memory. It appears in the
; 6507's zero page at $80-$FF: the low address lines A0-A6 pick one of the 128
; cells, and each cell holds eight bits. A write latches all eight data lines
; into the addressed cell; a read drives them back onto the bus. This is the
; memory every other test leans on for scratch and for the 6502 stack, so the
; suite needs one place that proves the RAM itself before trusting it elsewhere.
;
; The test makes three passes over the range $90..$F9. ($80..$8F is reserved for
; the RESULT convention's bookkeeping and $FA..$FF for the stack, so neither is
; touched here.)
;
;   1. Data patterns. Write $55 (01010101) to every cell and read it back, then
;      $AA (10101010), then $00. $55 and $AA are bit-complements, so between them
;      every bit position is driven both high and low; a data bit stuck high or
;      low shows up as a mismatch. $00 confirms an all-zero byte holds.
;
;   2. Address-identity march. Write into each cell its own address low byte,
;      then read the whole range back. If two addresses collapse onto one
;      physical cell — an address line not decoded within this window — the later
;      write clobbered the earlier cell and the readback mismatches.
;
;   3. Walking-1 coupling. Clear every cell, then set one cell to $FF, confirm
;      its neighbour is still $00, clear it and move on. This catches write-
;      coupling, where storing into one cell bleeds into the next cell — a
;      fault the uniform patterns and the march both miss, because they never
;      leave a lone changed cell sitting beside an unchanged one.
;
;   CODE $01 = the $55 pattern didn't read back: a data bit is stuck
;        $02 = the $AA pattern didn't read back (the complementary bits)
;        $03 = the all-zero pattern didn't read back
;        $04 = a cell didn't hold its own address: two addresses share one cell,
;              or an address line is stuck (OBSERVED = value read, EXPECTED = address)
;        $05 = walking a 1 through the cells disturbed a neighbour: setting one
;              cell changed the next (OBSERVED = the neighbour, should be $00)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$55                ; pattern $55 = 01010101
        ldy #$01                ; -> fail code $01
        jsr fill_check          ; fill $90..$F9, read back, assert all == $55
        lda #$AA                ; pattern $AA = 10101010 (every bit flipped)
        ldy #$02
        jsr fill_check
        lda #$00                ; pattern $00: all bits low
        ldy #$03
        jsr fill_check

        ; --- address-identity march: write each cell its own address, read back ---
        ldx #$90
.march_fill:
        txa                     ; A = this cell's address low byte
        sta $00,x               ; [$90+i] = $90+i
        inx
        cpx #$FA                ; stop before $FA (stack region)
        bne .march_fill
        ldx #$90
.march_check:
        txa                     ; expected = the address low byte
        cmp $00,x               ; the cell must still hold its address
        bne .march_fail
        inx
        cpx #$FA
        bne .march_check

        ; --- walking-1 coupling: background $00, set each cell to $FF and confirm
        ; its neighbour is still $00 (a write coupling into an adjacent cell is a
        ; fault the block patterns/march can miss), then clear it and walk on ---
        lda #$00
        ldx #$90
.w0fill:
        sta $00,x               ; clear every cell to $00
        inx
        cpx #$FA
        bne .w0fill
        ldx #$90
.wcheck:
        lda #$FF
        sta $00,x               ; set cell x to $FF
        cpx #$F9
        beq .wnext              ; last cell: no neighbour past the tested range
        lda $01,x               ; neighbour (cell x+1) must still be $00
        bne .wcoup_fail
.wnext:
        lda #$00
        sta $00,x               ; clear cell x (walk the 1 onward)
        inx
        cpx #$FA
        bne .wcheck

        PASS_TEST

.wcoup_fail:
        sta OBSERVED            ; the disturbed neighbour (should be $00)
        lda #$00
        sta EXPECTED
        lda #$05
        sta CODE
        jmp fail_result

.march_fail:
        lda $00,x               ; observed = what the cell actually held
        sta OBSERVED
        stx EXPECTED            ; expected = the address
        lda #$04
        sta CODE
        jmp fail_result

; fill_check: A = pattern, Y = failcode.
; Fills $90..$F9 with the pattern, reads back, asserts every cell equals it.
fill_check:
        sta EXPECTED            ; remember the pattern as "expected"
        sty CODE                ; and the fail code, in case a cell mismatches
        ldx #$90
.fc_fill:
        sta $00,x               ; write the pattern into cell x
        inx
        cpx #$FA
        bne .fc_fill
        ldx #$90
.fc_check:
        lda $00,x               ; read cell x back
        cmp EXPECTED            ; it must match the pattern
        bne .fc_fail
        inx
        cpx #$FA
        bne .fc_check
        rts                     ; all cells matched
.fc_fail:
        sta OBSERVED            ; the byte that came back wrong
        jmp fail_result

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
