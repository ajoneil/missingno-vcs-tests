; bank-3e — Tigervision's 3F bank-switch scheme with a RAM path added: the lower
; half of the cartridge window can show a ROM bank or a bank of cartridge RAM.
;
; 3E is a homebrew scheme by Armin Vogl (Kroko), a RAM-bearing extension of
; Tigervision's 3F. Calling it a board overstates it: no pressed 3E cartridge was
; ever made, and it existed only as flash-cart firmware (Krokodile, Cuttle Cart 2,
; Harmony/Melody) until batari built discrete boards in 2025-26. No spec document
; states its decode, so two readings exist, disagreeing over how much of TIA space
; selects a bank:
;   flash-cart reading  only $3E and $3F select. Krokodile and Harmony work this
;                       way, and Boulder Dash needs it.
;   batari's boards     Tigervision-style: any access with A12, A11, A7 and A6 low
;                       selects, A0 choosing RAM or ROM, so all of $00-$3F and its
;                       mirrors are hotspots. Boulder Dash does not run on these —
;                       it makes stray accesses below $40.
; This ROM asserts only what both readings agree on: the two select addresses, and
; A12 (below). It never touches $00-$3D, so it cannot tell them apart, and the
; cells below say nothing about the mirrors.
;
; The cartridge drives the bus only for accesses with address line A12 high: the
; 4K window $F000-$FFFF. Like 3F, the board splits that window into two 2K halves:
;   upper 2K  $F800-$FFFF : fixed — always the last 2K of the ROM image, never
;                           moves. The program, reset vectors, and switching code
;                           live here, so paging never moves the running code.
;   lower 2K  $F000-$F7FF : the half that pages.
;
; The hotspots are NOT in that window. Driving the bus and watching it are
; different things: the cart edge carries A0-A12 and no chip select, so the board
; sees every access the CPU makes, and the two it watches for sit down in TIA
; space with A12 LOW (a hotspot is an address the board watches; touching it
; switches banks). A zero-page store reaches them, and the value written is the
; bank number:
;   write value N to $3F  ->  ROM bank N (of the 2K ROM banks) in the lower half
;   write value N to $3E  ->  RAM bank N (of the 1K RAM banks) in the lower half
; The TIA decodes those addresses too and takes the write as well — both chips see
; every one of these accesses. It is harmless only because the TIA's registers
; stop at $2C, so $3E and $3F poke nothing real. That is why the scheme picked
; them.
; Writing $3F again returns ROM; RAM you paged out keeps its contents (it is real
; static RAM on the cart, not a view of ROM).
;
; The RAM is reached through two ports. The cartridge edge has no read/write
; signal, so the board splits the RAM into a read half and a write half and tells
; the direction from which half you touch. 3E puts the read half low:
;   read  port  $F000-$F3FF : a load here drives the addressed RAM byte onto the bus
;   write port  $F400-$F7FF : a store here latches the data bus into RAM
; Cell n is the same RAM cell either way: read it at $F000+n, write it at $F400+n.
;
;   CODE $01 = write value $00 to $3F did not page ROM bank 0 into the window
;        $02 = write value $01 to $3F did not page ROM bank 1
;        $03 = write value $02 to $3F did not page ROM bank 2
;        $04 = write $3E paged RAM bank 0 in, but a byte written through the
;              write port ($F400) did not read back through the read port ($F000)
;              — the read-low RAM path is broken
;        $05 = offset alignment: cell 1023 (write $F7FF / read $F3FF) did not read
;              back — the read/write offsets drift across the port split
;        $06 = a second RAM bank (a different $3E value) is not distinct memory —
;              bank 1's cell 0 did not hold its own value independent of bank 0
;        $07 = a $3F ROM excursion did not leave the RAM intact — re-selecting the
;              RAM bank found the pattern gone (RAM must persist while paged out)
;        $08 = RAM-bank selection is not independent of ROM-bank selection —
;              after ROM bank 2 / RAM bank 1 / ROM bank 2, the ROM signature was
;              wrong
;        $09 = a read of $F03F paged the window. That address is $103F on the bus:
;              the $3F select's low 12 bits, but with A12 HIGH, so it is an
;              ordinary data read inside the window and selects nothing
;        $0A = a write to $F03E paged the window — likewise $103E, A12 high, an
;              ordinary write to ROM. Its value $00 would name RAM bank 0 if the
;              board ignored A12
;        $0B = a load of the write port ($F400) did not destroy cell 0 — see the
;              ghost-write note below
;
; Ghost-write note ($0B): the port split is decoded from the address alone, so the
; board cannot tell a load of a write-port address from a store to one. It takes
; the load for a store and latches the bus, destroying the cell. The byte is the
; residue: nothing drives the bus, so the lines keep the last one driven — the
; operand high byte $F4 here. A real PAL console confirmed that undriven loads
; keep the last bus byte (a rival model would read the effective address's low
; byte, $00); the destruction itself is untested here, for want of a 3E board.
;
; Only the direct form can bite this layout. The other way in is a page-crossing
; indexed read, whose un-carried address stays in the base's page — so it can only
; reach the write port on a board that puts the write half LOW inside the page the
; read half occupies. 3E puts the two halves in separate pages and reads low, so no
; index can wrap into $F400-$F7FF; ram-superchip, whose 128-byte ports share page
; $F0 write-low, carries that cell instead.
;
; A12 note ($09/$0A): every implementation named above decodes A12 and requires it
; low — batari's included, whose select range stops at $73F precisely because A11
; and A12 are both decoded. So an access inside the window selects nothing, and the
; two readings agree here even though they agree nowhere else in TIA space. The
; probes also run from the fixed upper half, where A12 is already high: it neither
; arrives low nor rises, so a board gating on A12's level and one clocking on its
; rise both stay put, and these cells do not rest on which. Consensus, not silicon:
; there is no 3E hardware older than 2025 to measure.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: 3E

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SIGADDR = $F7F0                 ; lower-window per-bank signature (in-bank offset $7F0)
RAM_RD0 = $F000                 ; RAM read port, cell 0
RAM_RDF = $F3FF                 ; RAM read port, cell 1023 (last)
RAM_WR0 = $F400                 ; RAM write port, cell 0
RAM_WRF = $F7FF                 ; RAM write port, cell 1023 (last)

; probe result cells (harness owns $80-$89; scratch lives at $90+)
SIG0   = $90                    ; ROM bank 0 signature after selecting it
SIG1   = $91                    ; ROM bank 1
SIG2   = $92                    ; ROM bank 2
RB0C0  = $93                    ; RAM bank 0 cell 0 read back (read-low)
RB0CF  = $94                    ; RAM bank 0 cell 1023 read back (offset alignment)
RB1C0  = $95                    ; RAM bank 1 cell 0 read back (distinct bank)
RPERS  = $96                    ; RAM bank 0 cell 0 after a ROM excursion (persistence)
RINDEP = $97                    ; ROM signature after interleaving ROM/RAM selects
A12RD  = $98                    ; ROM signature after reading $F03F (A12 high)
A12WR  = $99                    ; ROM signature after writing $F03E (A12 high)
GHOST  = $9A                    ; RAM cell 0 after a load landed on its write port

; ------------------------------------------------------- banks 0-2 (lower-window data)
; Pure data: no code ever runs from the lower window. Each bank opens with two
; non-uniform 128-byte halves so it never fingerprints as a phantom Superchip
; (a bank whose first 128 bytes equal the next 128 misdetects as SC RAM), then
; $FF filler up to the signature at offset $7F0.
        MAC DATABANK                    ; {1} = file base, {2} = signature byte
        ORG {1}
        RORG $F000
        ds 128, $A0                     ; non-uniform first 256 bytes: dodge phantom-SC
        ds 128, $B0
        ds ($7F0-256), $FF
        .byte {2}                       ; signature at $F7F0
        ds $0F, $FF                     ; pad to the 2K boundary
        ENDM

        SEG BANK0
        DATABANK $0000, $30             ; ROM bank 0 signature $30
        SEG BANK1
        DATABANK $0800, $31             ; ROM bank 1 signature $31
        SEG BANK2
        DATABANK $1000, $32             ; ROM bank 2 signature $32

; ------------------------------------------------ bank 3 = fixed upper 2K + all code
        SEG BANK3
        ORG $1800
        RORG $F800
ENTRY:
Main:
        CLEAN_START
        TEST_BEGIN

        ; --- ROM bank walk: the written value selects the lower ROM bank ---
        ; Every select here is a plain write — the one trigger shape every model
        ; of the board agrees on — so nothing below rests on the contested
        ; bus-level trigger (bank-3f covers that).
        lda #$00
        sta $3F                         ; select ROM bank 0 (value 0)
        lda SIGADDR
        sta SIG0
        lda #$01
        sta $3F                         ; A9 01 85 3F : select ROM bank 1
        lda SIGADDR
        sta SIG1
        lda #$02
        sta $3F                         ; A9 02 85 3F : select ROM bank 2
        lda SIGADDR
        sta SIG2

        ASSERT_EQ SIG0, $30, $01
        ASSERT_EQ SIG1, $31, $02
        ASSERT_EQ SIG2, $32, $03

        ; --- write $3E pages RAM in: read-low RAM survives write->read ---
        ; Power-on RAM is undefined, so every cell is written before it is read.
        ; Nothing below loads a write-port address: doing so destroys the cell
        ; (cell $0B asserts that deliberately, and runs last for the same reason).
        lda #$00
        sta $3E                         ; 85 3E : select RAM bank 0 into the window
        lda #$00                        ; A9 00 : board-detection byte tail (inert load)
        lda #$A5
        sta RAM_WR0                     ; write cell 0 through the write port ($F400)
        lda RAM_RD0                     ; read  cell 0 through the read port  ($F000)
        sta RB0C0
        ASSERT_EQ RB0C0, $A5, $04

        ; --- offset alignment across the port split: the far cell ---
        lda #$5A
        sta RAM_WRF                     ; write cell 1023 ($F7FF)
        lda RAM_RDF                     ; read  cell 1023 ($F3FF)
        sta RB0CF
        ASSERT_EQ RB0CF, $5A, $05

        ; --- a second RAM bank via a different $3E value is distinct memory ---
        lda #$01
        sta $3E                         ; select RAM bank 1
        lda #$C3
        sta RAM_WR0                     ; bank 1 cell 0 = $C3 (bank 0 cell 0 is $A5)
        lda RAM_RD0
        sta RB1C0
        ASSERT_EQ RB1C0, $C3, $06       ; bank 1 holds its own value, not bank 0's

        ; --- $3F returns ROM; the RAM persists while paged out ---
        lda #$02
        sta $3F                         ; ROM bank 2 into the window (RAM paged out)
        lda #$00
        sta $3E                         ; RAM bank 0 back into the window
        lda RAM_RD0                     ; cell 0 -> still $A5 (survived the excursion)
        sta RPERS
        ASSERT_EQ RPERS, $A5, $07

        ; --- RAM selection is independent of ROM selection ---
        lda #$02
        sta $3F                         ; ROM bank 2
        lda #$01
        sta $3E                         ; RAM bank 1 (lower window is now RAM)
        lda #$02
        sta $3F                         ; ROM bank 2 again
        lda SIGADDR                     ; the ROM signature is intact
        sta RINDEP
        ASSERT_EQ RINDEP, $32, $08

        ; --- the hotspots need A12 low: an in-window access must not page ---
        ; $F03E is $103E on the bus — the same low 12 bits as the $3E hotspot, but
        ; A12 high. The board decodes A12, so this is an ordinary write to ROM and
        ; does nothing. A12 is already high here (this code runs in the window), so
        ; it neither arrives low nor rises: a board that gates on A12's level and
        ; one that clocks on its rise both stay put. Nothing below rests on which.
        lda #$02
        sta $3F                         ; ROM bank 2 into the window
        lda $F03F                       ; read $103F in the window: not a hotspot
        lda SIGADDR
        sta A12RD                       ; expect $32 — still bank 2
        ASSERT_EQ A12RD, $32, $09

        lda #$02
        sta $3F                         ; ROM bank 2 again (recover if $09 paged)
        lda #$00
        sta $F03E                       ; write $103E in the window: not a hotspot.
                                        ;   value $00 would name RAM bank 0 if the
                                        ;   board ignored A12
        lda SIGADDR
        sta A12WR                       ; expect $32 — still bank 2, still ROM
        ASSERT_EQ A12WR, $32, $0A

        ; --- a load of a write-port address destroys the cell ---
        ; Runs last: it clobbers RAM cell 0, which $04 and $07 rely on. The board
        ; decodes direction from the address alone — the cart edge has no read/write
        ; line — so it takes this load for a store and latches the data bus. Nothing
        ; drives the bus (the write port has no output), so the lines keep the last
        ; byte driven, which the fetch order makes the operand high byte $F4.
        lda #$00
        sta $3E                         ; RAM bank 0 into the window
        lda #$A5
        sta RAM_WR0                     ; cell 0 = $A5 (write port $F400)
        lda RAM_WR0                     ; AD 00 F4 : LOAD the write port -> ghost store
        lda RAM_RD0                     ; cell 0 back through the read port ($F000)
        sta GHOST
        ASSERT_EQ GHOST, $F4, $0B       ; cell 0 holds the residue, not $A5

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $1800+$7F0                  ; bank 3's signature. The board can page bank 3
        RORG $FFF0                      ; into the low window (bank-3f proves that cell);
                                        ; this test only reads it here, at $FFF0 in the
                                        ; fixed upper image
        .byte $33

        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
