; ram-cv — the CommaVid board: 2K of ROM plus 1K of RAM, with the RAM's read
; and write ports in the opposite halves from the usual Atari RAM board.
;
; The 6507 gives the cart a 4K window at $F000-$FFFF. CommaVid fills the lower
; 2K with the RAM and the upper 2K, $F800-$FFFF, with the ROM (the whole
; program and the reset vectors). There is no banking.
;
; The cartridge edge has no read/write line, so the board tells a load from a
; store by which half of the RAM window you touch:
;
;   read  port  $F000-$F3FF   a load here drives the addressed RAM byte onto the bus
;   write port  $F400-$F7FF   a store here latches the data bus into RAM
;
; Cell n is one RAM byte reached two ways: read it at $F000+n, write it at
; $F400+n. (The Superchip/FA boards do the reverse — write low, read high.)
;
; Because the split is decoded from the address alone, the board cannot tell a
; load of a write-port address from a store to one: it takes the load for a
; store and latches the bus, destroying the cell. Cell $05 asserts that, and
; runs last for the same reason. The byte it leaves is the residue — nothing
; drives the bus, so the lines keep the last one driven, the operand high byte
; $F4. A real PAL console confirmed that undriven loads keep the last bus byte
; (a rival model would read the effective address's low byte, $00); the
; destruction itself is untested here, for want of a CommaVid board.
;
;   CODE $01 = cell 0 (write $F400 / read $F000) did not read back
;        $02 = cell 1 (write $F401 / read $F001) — offset lost across the ports
;        $03 = cell 1023 (write $F7FF / read $F3FF) did not read back
;        $04 = a second write to cell 0 did not replace the first (RAM, not latch)
;        $05 = a load of the write port ($F400) did not destroy cell 0 — see above
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: CV

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

RD0    = $F000                  ; RAM read port, cell 0
RD1    = $F001
RD1023 = $F3FF                  ; RAM read port, cell 1023 (last)
WR0    = $F400                  ; RAM write port, cell 0
WR1    = $F401                  ; RAM write port, cell 1
WR1023 = $F7FF                  ; RAM write port, cell 1023 (last)
; cell 0's write is emitted as `sta $F400,y` (99 00 F4) — the CV fingerprint.

; scratch cells (cart RAM is separate; these live in RIOT RAM $90+)
CM0    = $90                    ; cell 0 read back
CM1    = $91                    ; cell 1 read back
CM1023 = $92                    ; cell 1023 read back
CM0B   = $93                    ; cell 0 read back after the second write
GHOST  = $94                    ; cell 0 after a load landed on its write port

        SEG ROM
        ORG $0000
        RORG $F800
ENTRY:
Main:
        CLEAN_START
        TEST_BEGIN

        ; Write three cells across the 1K through the write port, then read them
        ; back through the read port: the readbacks prove the port split and that
        ; the offset is the same on both ports. Every cell is written before it is
        ; read — power-on RAM content is undefined. Nothing here loads from the
        ; write port.
        ldy #0
        lda #$A5
        sta $F400,y                     ; 99 00 F4 : write cell 0 (the CV fingerprint)
        lda #$3C
        sta WR1                         ; write cell 1
        lda #$5A
        sta WR1023                      ; write cell 1023 (last)

        ; read them back through the read port (read-low)
        lda RD0
        sta CM0
        lda RD1
        sta CM1
        lda RD1023
        sta CM1023

        ASSERT_EQ CM0,    $A5, $01
        ASSERT_EQ CM1,    $3C, $02      ; offset carried intact across the port split
        ASSERT_EQ CM1023, $5A, $03

        ; a second write to cell 0 replaces the value — proves real RAM, not a latch
        lda #$C7
        sta $F400
        lda RD0
        sta CM0B
        ASSERT_EQ CM0B, $C7, $04

        ; --- a load of the write port destroys the cell (runs last: clobbers cell 0) ---
        lda WR0                         ; AD 00 F4 : LOAD the write port -> ghost store
        lda RD0                         ; cell 0 back through the read port
        sta GHOST
        ASSERT_EQ GHOST, $F4, $05       ; cell 0 holds the residue, not $C7

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $07FC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
