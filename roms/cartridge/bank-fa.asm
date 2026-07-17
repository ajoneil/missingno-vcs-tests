; bank-fa — the FA board (CBS RAM Plus, 12K) holds three 4K banks plus 256 bytes
; of cart RAM, and gates its bankswitch on the data bus.
;
; The cart answers whenever address line A12 is high: a 4K window the CPU sees at
; $F000-$FFFF. Only 4K fits there at once, so the cart keeps three banks and shows
; one at a time. Three addresses near the top of the window are hotspots (an
; address the board watches; touching it switches banks):
;
;   $1FF8  selects bank 0
;   $1FF9  selects bank 1
;   $1FFA  selects bank 2
;
; The cart decodes only 13 address lines, so each hotspot also answers at its
; mirror near the top of the window ($FFF8/$FFF9/$FFFA), where the CPU reaches it.
;
; The FA board is unusual twice over. First, it adds 256 bytes of static RAM
; under the bottom of the window. The cart edge has no read/write line, so the
; RAM is split into two ports:
;
;   $F000-$F0FF  write port  (a bus access latches the data bus into RAM)
;   $F100-$F1FF  read port   (a bus access drives the addressed byte out)
;
; Both ports reach the same 256 cells: storing to $F000+n and loading from
; $F100+n touch cell n. Because RAM occupies $F000-$F1FF, the ROM bytes under it
; are shadowed (hidden) — a read-port load returns RAM, never the image. The RAM
; sits outside the banked ROM, so a bank switch never disturbs it.
;
; Second, the bankswitch is gated by the data bus. Per US Patent 4,485,457 the
; FA decoder switches only when data-bus bit D0 = 1 during the hotspot access:
;   - a write strobe carries the CPU's value, so `lda #$01 : sta $1FF9` switches
;     but `lda #$00 : sta $1FF9` does not;
;   - a read strobe carries the ROM byte the cart drives at that hotspot address,
;     which the image controls: a hotspot whose byte has D0=1 switches, D0=0 does
;     not.
; The test fixes those hotspot bytes so both directions are deterministic: every
; bank holds $01 at its $1FF8, bank 0 holds $00 at its $1FFA, and bank 1 holds
; $00 at its $1FF9 (every other bank holds $01 there).
;
; That last byte pins down which byte the gate reads. The patent has the decoder
; wait for the data so the address can settle first, the data arriving later, so
; the byte it acts on is the one the pre-switch bank is still driving: a read of
; $1FF9 from bank 0 puts bank 0's $01 on the bus, D0=1, and must switch to bank 1
; — even though bank 1's own $1FF9 byte is $00.
;
; Each bank holds a one-byte signature ($B0/$B1/$B2) at a mid-bank address clear
; of the RAM window and hotspots; the signatures are how the test names the bank
; it is looking at.
;
;   CODE $01 = write $1FF8 (D0=1) did not page in bank 0
;        $02 = write $1FF9 (D0=1) did not page in bank 1
;        $03 = write $1FFA (D0=1) did not page in bank 2
;        $04 = write $1FF8 (D0=1) did not return to the home bank
;        $05 = read (bit) $1FF9 did not page in bank 1 (bank 0 drives $01 there,
;              D0=1; bank 1's own byte is $00 and must not be what the gate saw)
;        $06 = read (bit) $1FF8 did not return to the home bank
;        $07 = RAM cell 0 written low did not read back high
;        $08 = RAM cell 1 read back wrong (offset n carried across the port split)
;        $09 = RAM cell 255 (last) did not read back
;        $0A = RAM did not survive a bank switch
;        $0B = read port returned the shadowed ROM byte, not the RAM value
;        $0C = D0 gate: write $1FF9 with D0=0 switched anyway (patent: must not)
;        $0D = D0 gate: read $1FFA (bank 0 byte $00, D0=0) switched (must not)
;        $0E = the board stopped switching after the gated attempts
;
; The D0 gate ($0C, $0D) is contested. Some implementations gate the switch on D0
; as the patent describes; some ignore the data bus and switch on any hotspot
; access; and a gate applied to a write value may not extend to the ROM byte a
; read strobe drives. This test asserts the gate on the authority of US 4,485,457,
; so a model may legitimately fail $0C, $0D, or both. $05 is not part of the
; dispute: a gated and an ungated board both switch there, so only a board that
; read the post-switch byte fails it. The gate is untested on hardware.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: FA

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8               ; touch (D0=1) -> select bank 0  (mirror of $1FF8)
HOTSPOT1 = $FFF9               ; touch (D0=1) -> select bank 1  (mirror of $1FF9)
HOTSPOT2 = $FFFA               ; touch (D0=1) -> select bank 2  (mirror of $1FFA)
SIG      = $FC00               ; per-bank signature (mid-bank, clear of RAM/hotspots)

WRITE0   = $F000               ; RAM write port, cell 0
WRITE1   = $F001
WRITE2   = $F002
WRITE64  = $F040
WRITE255 = $F0FF               ; RAM write port, cell 255 (last)
READ0    = $F100               ; RAM read port, cell 0
READ1    = $F101
READ2    = $F102
READ64   = $F140
READ255  = $F1FF               ; RAM read port, cell 255 (last)

ENTRY    = $F200               ; stub entry (reset target), identical in every bank;
                               ;   above $F000-$F1FF, which is RAM at run time and
                               ;   so can hold no code or vectors
PROBE    = $F206               ; probe routine (jsr target), after the 6-byte entry

; probe result cells (collected across bank switches, read by Main afterwards)
BW0    = $90                   ; write-strobe walk: bank 0/1/2/home signatures
BW1    = $91
BW2    = $92
BWH    = $93
RD9    = $94                   ; read-strobe $1FF9 -> bank 1
RDH    = $95                   ; read-strobe $1FF8 -> home
RAMP   = $96                   ; RAM cell 2 read back after a bank switch
GW     = $97                   ; signature after a D0=0 write strobe (gate)
GR     = $98                   ; signature after a D0=0 read strobe (gate)
GRECOV = $99                   ; signature after a normal switch post-gate
; Main-side RAM readbacks
M0     = $9A
M1     = $9B
M255   = $9C
MSHDW  = $9D

; The shared stub — byte-identical in all three banks at $F200. The probe walks
; the banks with sta-strobes (D0=1 writes), re-selects with bit-strobes (reads,
; whose D0 comes from the hotspot's ROM byte), checks RAM persistence across a
; switch, then attempts two D0=0 (gated) strobes that a correct board ignores.
        MAC STUB
        bit HOTSPOT0            ; ENTRY ($F200): $1FF8 byte=$01 (D0=1) -> force bank 0
        jmp Main                ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F206): bank walk by write strobes, data-bus D0=1
        lda #$01
        sta HOTSPOT0            ; D0=1 write -> bank 0
        nop
        nop
        lda SIG
        sta BW0
        lda #$01
        sta HOTSPOT1            ; -> bank 1 (next fetch is bank 1's identical stub)
        nop
        nop
        lda SIG
        sta BW1
        lda #$01
        sta HOTSPOT2            ; -> bank 2
        nop
        nop
        lda SIG
        sta BW2
        lda #$01
        sta HOTSPOT0            ; -> back to the home bank
        nop
        nop
        lda SIG
        sta BWH
        ; read strobes: the hotspot's ROM byte drives D0 — the byte the pre-switch
        ; bank drives, the only one on the bus when the gate decides
        bit HOTSPOT1            ; read $1FF9: bank 0 drives $01 (D0=1) -> bank 1.
                                ;   bank 1's own $1FF9 byte is $00, so a board that
                                ;   gated on the post-switch byte would stay put
        nop
        nop
        lda SIG
        sta RD9
        bit HOTSPOT0            ; read $1FF8 (byte $01) -> home bank
        nop
        nop
        lda SIG
        sta RDH
        ; RAM persistence across a bank switch (Main already wrote the pattern)
        lda #$18
        sta WRITE2             ; cart RAM cell 2 = $18 (write port)
        lda #$01
        sta HOTSPOT2           ; -> bank 2
        nop
        nop
        lda READ2              ; read port cell 2 -> should still be $18
        sta RAMP
        lda #$01
        sta HOTSPOT0           ; -> home bank
        nop
        nop
        ; D0 gate, write: a D0=0 store to a hotspot must not switch (patent)
        lda #$00
        sta HOTSPOT1           ; D0=0 write -> gated; a gate-less board -> bank 1
        nop
        nop
        lda SIG
        sta GW                 ; expect $B0 (still the home bank)
        lda #$01
        sta HOTSPOT0           ; force home (recover if a board switched)
        nop
        nop
        ; D0 gate, read: bank 0's $1FFA byte is $00 (D0=0), so a read must not
        ; switch. $05 above has already ruled out a board that gates on the
        ; post-switch byte; such a board would land in bank 2 here too and be
        ; indistinguishable from one with no read gate at all.
        bit HOTSPOT2           ; read $1FFA (bank 0 byte $00, D0=0) -> gated
        nop
        nop
        lda SIG
        sta GR                 ; expect $B0 (still the home bank)
        lda #$01
        sta HOTSPOT0           ; force home (recover)
        nop
        nop
        ; recovery: a normal D0=1 switch still works after the gated attempts
        lda #$01
        sta HOTSPOT1           ; -> bank 1
        nop
        nop
        lda SIG
        sta GRECOV             ; expect $B1
        lda #$01
        sta HOTSPOT0           ; -> home bank
        nop
        nop
        rts
        ENDM

; a bank body: RAM-shadow fill + shared stub + signature + hotspot bytes + vectors
;   {1} = file base, {2} = signature byte, {3} = the $1FF9 hotspot byte (gate),
;   {4} = the $1FFA hotspot byte (gate)
        MAC BANK
        ORG {1}
        RORG $F000
        ds 128, $A0            ; RAM shadow ($F000-$F07F): non-uniform halves so the
        ds 128, $B0            ; image never fingerprints as a phantom Superchip
        ds 256, $C0            ; RAM shadow ($F100-$F1FF)
        STUB                   ; entry+probe at $F200 (byte-identical every bank)
        ORG {1}+$C00
        RORG $FC00
        .byte {2}             ; signature
        ORG {1}+$FF8
        RORG $FFF8
        .byte $01             ; $1FF8 hotspot byte: D0=1 (read-strobe forces bank 0)
        .byte {3}             ; $1FF9 hotspot byte: D0 gate cell (bank 1 = $00)
        .byte {4}             ; $1FFA hotspot byte: D0 gate cell (bank 0 = $00)
        .byte $FF             ; $1FFB filler
        RORG $FFFC
        .word ENTRY           ; FA banks the whole 4K, vectors included, so every
        .word ENTRY           ;   bank carries its own reset vectors
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        ds 128, $A0            ; RAM shadow, non-uniform halves (as above)
        ds 128, $B0
        ds 256, $C0
        STUB                   ; ENTRY/PROBE at $F200
Main:
        CLEAN_START
        TEST_BEGIN

        lda #$A5               ; write the RAM pattern through the write port
        sta WRITE0             ; cell 0
        lda #$3C
        sta WRITE1             ; cell 1
        lda #$5A
        sta WRITE255           ; cell 255 (last)
        lda #$6D
        sta WRITE64            ; cell 64 (the read port's shadow ROM byte is $C0, differs)

        lda READ0              ; read them back through the read port (pre-probe)
        sta M0
        lda READ1
        sta M1
        lda READ255
        sta M255
        lda READ64             ; RAM shadows the ROM under the read port
        sta MSHDW

        jsr PROBE              ; walk banks, read strobes, RAM persistence, D0 gate

        ASSERT_EQ BW0,  $B0, $01       ; write $1FF8 (D0=1) -> bank 0
        ASSERT_EQ BW1,  $B1, $02       ; write $1FF9 (D0=1) -> bank 1
        ASSERT_EQ BW2,  $B2, $03       ; write $1FFA (D0=1) -> bank 2
        ASSERT_EQ BWH,  $B0, $04       ; write $1FF8 returned home
        ASSERT_EQ RD9,  $B1, $05       ; read $1FF9 -> bank 1 (gate saw bank 0's $01)
        ASSERT_EQ RDH,  $B0, $06       ; read  $1FF8 returned home
        ASSERT_EQ M0,   $A5, $07       ; RAM cell 0 written low, read high
        ASSERT_EQ M1,   $3C, $08       ; RAM cell 1 (offset carried across the ports)
        ASSERT_EQ M255, $5A, $09       ; RAM cell 255 (last)
        ASSERT_EQ RAMP, $18, $0A       ; RAM survived the bank switch
        ASSERT_EQ MSHDW,$6D, $0B       ; read port returned RAM, not the shadow ($C0)
        ASSERT_EQ GW,   $B0, $0C       ; D0=0 write was gated -> still bank 0
        ASSERT_EQ GR,   $B0, $0D       ; D0=0 read was gated  -> still bank 0
        ASSERT_EQ GRECOV,$B1, $0E      ; a normal switch still works after the gate

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $B0                      ; bank 0 signature
        ORG $0FF8
        RORG $FFF8
        .byte $01                      ; $1FF8 byte: D0=1
        .byte $01                      ; $1FF9 byte: D0=1
        .byte $00                      ; $1FFA byte: D0=0 (the read-gate cell)
        .byte $FF                      ; $1FFB filler
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; -------------------------------------------------------------- banks 1,2 (data)
        SEG BANK1
        BANK $1000, $B1, $00, $01      ; bank 1: $1FF9 byte $00 — the post-switch
                                       ;   byte a $1FF9 read from bank 0 must not see
        SEG BANK2
        BANK $2000, $B2, $01, $01      ; bank 2
