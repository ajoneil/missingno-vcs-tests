; bank-e7 — the E7 board (M-Network, 16K): eight 2K ROM banks and two separate
; cart RAMs share the 4K window, with the select hotspots in a fixed top region.
;
; The 6507 reserves $F000-$FFFF for the cartridge. E7 divides that 4K window into
; three regions, and picks what two of them show by hotspot (an address the board
; watches; an access to one switches a region):
;
;   $F000-$F7FF   lower window (2K)     ROM bank N by any access to $FFE0+N (N=0..6),
;                                       or the 1K RAM by any access to $FFE7
;   $F800-$F9FF   page window (256 B)   one of four 256 B RAM pages, by $FFE8..$FFEB
;   $FA00-$FFFF   fixed (1.5K)          always the top 1.5K of bank 7
;
; So the board exposes two separately-addressed RAM regions, 2K in all: a 1K
; RAM that appears in the lower window when $FFE7 is touched, and a pool of four
; 256 B pages that appears in the page window. The cart edge has no read/write
; line, so each RAM splits its write and read addresses:
;
;   1K RAM       write $F000-$F3FF   read $F400-$F7FF
;   256 B page   write $F800-$F8FF   read $F900-$F9FF
;
; Note $FFE7 selects RAM, not an eighth ROM bank: bank 7 is never reachable in
; the lower window, because its top 1.5K is permanently the fixed region.
;
; Each ROM bank 0..6 carries a signature ($C0..$C6) at in-window offset $600, read
; at $F600 to prove which bank the lower window shows. The fixed region stores a
; known byte at each hotspot, so a read of a hotspot returns data as well as
; switching.
;
;   CODE $01..$07 = access $FFE0..$FFE6 did not page ROM bank 0..6 into the window
;        $08 = 1K RAM cell 0 (write $F000 / read $F400) did not read back
;        $09 = 1K RAM cell 1023 (write $F3FF / read $F7FF) did not read back
;        $0A = 1K RAM did not survive a 256 B page switch
;        $0B = 1K RAM cell 1 wrong (offset n carried across the write/read ports)
;        $0C = re-selecting a ROM bank did not restore its signature
;        $0D..$10 = 256 B page 0..3 (write $F800 / read $F900) did not read back
;        $11 = a 256 B page write leaked into the 1K RAM's cells (the two regions
;              must not overlap; whether they are one 2K chip or two is not what
;              this cell tests)
;        $12 = a hotspot read ($FFE5) did not return the fixed-region ROM byte
;        $13 = a load of the 1K RAM's write port ($F000) did not destroy cell 0
;        $14 = a load of a page's write port ($F800) did not destroy cell 0
;
; Ghost-write note ($13/$14): neither RAM can tell a load of a write-port address
; from a store to one — the split is decoded from the address alone — so the load
; is taken for a store and latches the bus, destroying the cell. The byte is the
; residue: nothing drives the bus, so the lines keep the last one driven, the
; load's high address byte ($F0 and $F8 here) — the same bus-capacitance residue
; an undriven read returns. Both of E7's RAMs put their halves in separate pages,
; so only this direct form can reach them: an indexed read's un-carried address
; stays in the base's page.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: E7

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SIG    = $F600         ; per-bank signature, read while a ROM bank is in the window
HOT5   = $FFE5         ; hotspot: selects bank 5 and drives the fixed byte $E5

; probe result cells
BWBASE = $90           ; bank walk: bank X sig -> $90+X ($90..$96 for X=0..6)
R1K0   = $97           ; 1K RAM cell 0
R1K1023= $98           ; 1K RAM cell 1023
R1KPST = $99           ; 1K RAM cell 2 after a 256 B page switch
R1K1   = $9A           ; 1K RAM cell 1
ROMBK  = $9B           ; ROM signature after the RAM excursion
PG0    = $9C           ; 256 B page 0..3 readbacks
PG1    = $9D
PG2    = $9E
PG3    = $9F
POOL   = $A0           ; 1K RAM cell 0 after the page writes (pool-separation)
HOTBY  = $A1           ; byte returned by reading hotspot $FFE5
GH1K   = $A2           ; 1K RAM cell 0 after a load landed on its write port
GHPG   = $A3           ; page RAM cell 0 after a load landed on its write port

; ---------------------------------------------------------------- bank 0 (harness)
; The fixed region (1.5K) is too small for the result screen, so the harness
; (Main + asserts + result screen) lives here and the entry pages bank 0 into the
; lower window. Everything that strobes a hotspot or touches RAM runs from the
; fixed region instead: while $FFE7 is selected the lower window is itself the
; RAM, and this code would vanish from under the CPU.
        SEG BANK0
        ORG $0000
        RORG $F000
Main:
        CLEAN_START            ; (entry has already paged bank 0 into the lower window)
        TEST_BEGIN

        jsr PROBE              ; all strobing + RAM traffic runs from the fixed region

        ASSERT_EQ $90, $C0, $01        ; $FFE0 -> ROM bank 0 in the lower window
        ASSERT_EQ $91, $C1, $02        ; $FFE1 -> bank 1
        ASSERT_EQ $92, $C2, $03        ; $FFE2 -> bank 2
        ASSERT_EQ $93, $C3, $04        ; $FFE3 -> bank 3
        ASSERT_EQ $94, $C4, $05        ; $FFE4 -> bank 4
        ASSERT_EQ $95, $C5, $06        ; $FFE5 -> bank 5
        ASSERT_EQ $96, $C6, $07        ; $FFE6 -> bank 6
        ASSERT_EQ R1K0,   $5C, $08     ; 1K RAM cell 0 write-low / read-high
        ASSERT_EQ R1K1023,$3E, $09     ; 1K RAM cell 1023 (last)
        ASSERT_EQ R1KPST, $71, $0A     ; 1K RAM survived a 256 B page switch
        ASSERT_EQ R1K1,   $6D, $0B     ; 1K RAM cell 1 (offset carried across ports)
        ASSERT_EQ ROMBK,  $C3, $0C     ; re-selecting bank 3 restored its signature
        ASSERT_EQ PG0,    $11, $0D     ; 256 B page 0
        ASSERT_EQ PG1,    $22, $0E     ; page 1
        ASSERT_EQ PG2,    $33, $0F     ; page 2
        ASSERT_EQ PG3,    $44, $10     ; page 3 (all four independent)
        ASSERT_EQ POOL,   $5C, $11     ; page writes did not touch the 1K RAM (separate)
        ASSERT_EQ HOTBY,  $E5, $12     ; read $FFE5 returned the fixed-region byte $E5
        ASSERT_EQ GH1K,   $F0, $13     ; a load of the 1K write port destroyed cell 0
        ASSERT_EQ GHPG,   $F8, $14     ; a load of the page write port destroyed cell 0

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0600
        RORG $F600
        .byte $C0                      ; bank 0 signature
        ds ($0800-$0601), $FF          ; pad bank 0 to its 2K boundary

; a pure-data ROM bank: non-uniform header + signature at offset $600
        MAC DATABANK           ; {1}=file base, {2}=signature byte
        ORG {1}
        RORG $F000
        .byte $E7, {2}                 ; header bytes (dodge a phantom-F6SC fingerprint)
        ds ($600-2), $00               ; gap to the signature offset
        .byte {2}                      ; signature at in-window offset $600
        ds ($800-$600-1), $FF          ; pad to the 2K boundary
        ENDM

; ------------------------------------------------------------- banks 1..6 (ROM)
        SEG BANK1
        DATABANK $0800, $C1
        SEG BANK2
        DATABANK $1000, $C2
        SEG BANK3
        DATABANK $1800, $C3
        SEG BANK4
        DATABANK $2000, $C4
        SEG BANK5
        DATABANK $2800, $C5
        SEG BANK6
        DATABANK $3000, $C6

; ----------------------------------------------------- bank 7 (fixed top region)
; Bank 7 is 2K; its top 1.5K ($FA00-$FFFF) is permanently mapped and holds the
; reset entry, the probe, the hotspot data bytes, and the vectors. Its bottom
; 0.5K is never visible (bank 7 is not selectable into the lower window). Probe
; opcodes are all fetched from here, so they survive every page; code stays clear
; of the hotspots $FFE0-$FFEB.
        SEG BANK7
        ORG $3800
        RORG $F800
        ds $200, $FF                   ; bank 7 bottom 0.5K: never mapped

        ORG $3A00
        RORG $FA00
ENTRY:
        ldx #0
        sta $FFE0,x            ; page ROM bank 0 into the lower window
        jmp Main               ; run the harness from the lower window

; PROBE — bank walk, both cart RAMs, pool separation, hotspot-read. Uses the
; detector's own E7 forms (8D E7 FF, AD E5 FF); bank selects are indexed stores.
PROBE:
        ldx #0
.bw:
        sta $FFE0,x           ; select ROM bank X into the lower window (write strobe)
        lda SIG               ; $F600
        sta BWBASE,x          ; -> $90..$96
        inx
        cpx #7
        bne .bw
        ; 1K RAM via $FFE7 (write $F000-$F3FF / read $F400-$F7FF)
        sta $FFE7             ; 8D E7 FF — 1K RAM into the lower window
        lda #$5C
        sta $F000            ; cell 0 (write low)
        lda #$6D
        sta $F001            ; cell 1
        lda #$3E
        sta $F3FF            ; cell 1023
        lda $F400            ; cell 0 (read high)
        sta R1K0
        lda $F7FF            ; cell 1023
        sta R1K1023
        lda $F401            ; cell 1
        sta R1K1
        ; 1K RAM persists while the 256 B page window is switched
        lda #$71
        sta $F002            ; cell 2 = $71
        sta $FFE8            ; select page 0 (changes the page window, not the lower one)
        lda $F402            ; cell 2 -> still $71
        sta R1KPST
        ; re-select a ROM bank: its signature returns (RAM excursion left ROM intact)
        ldx #3
        sta $FFE0,x          ; bank 3 into the lower window
        lda SIG
        sta ROMBK            ; expect $C3
        ; 256 B pages: a distinct byte into each (write $F800 / read $F900)
        sta $FFE8
        lda #$11
        sta $F800
        sta $FFE9
        lda #$22
        sta $F800
        sta $FFEA
        lda #$33
        sta $F800
        sta $FFEB
        lda #$44
        sta $F800
        sta $FFE8
        lda $F900
        sta PG0              ; expect $11
        sta $FFE9
        lda $F900
        sta PG1              ; $22
        sta $FFEA
        lda $F900
        sta PG2              ; $33
        sta $FFEB
        lda $F900
        sta PG3              ; $44
        ; pool separation: the 1K RAM cell 0 is untouched by the page writes
        sta $FFE7            ; 1K RAM into the lower window
        lda $F400            ; cell 0 -> still $5C
        sta POOL
        ; hotspot read: selects bank 5 and returns the fixed byte stored at $FFE5
        lda HOT5             ; AD E5 FF
        sta HOTBY            ; expect $E5
        ; --- a load of a write port destroys the cell, in BOTH RAMs ---
        ; Last in the probe: these clobber cell 0 of each RAM, which $08/$11 and
        ; $0D-$10 read. The board has no read/write line and decodes direction from
        ; the address alone, so it takes each load for a store and latches the bus.
        ; Nothing drives it, so the lines keep the last byte driven — the operand
        ; high byte of the load.
        sta $FFE7            ; 1K RAM into the lower window
        lda $F000            ; AD 00 F0 : LOAD the 1K write port -> ghost store
        lda $F400            ; cell 0 back through the read port
        sta GH1K             ; expect $F0
        sta $FFEB            ; page 3 into the page window
        lda $F800            ; AD 00 F8 : LOAD the page write port -> ghost store
        lda $F900            ; page cell 0 back through the read port
        sta GHPG             ; expect $F8
        ; restore bank 0 into the lower window so the rts lands on real code
        ldx #0
        sta $FFE0,x
        rts

; hotspot data bytes: driven when a hotspot is read. Only $FFE5 ($E5) is asserted.
        ORG $3FE0
        RORG $FFE0
        .byte $E0,$E1,$E2,$E3,$E4,$E5,$E6   ; $FFE0-$FFE6 bank selects ($FFE5 = $E5)
        .byte $E7,$E8,$E9,$EA,$EB           ; $FFE7 RAM, $FFE8-$FFEB page selects
        .byte $FF                           ; $FFEC filler

        ORG $3FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
