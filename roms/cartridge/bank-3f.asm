; bank-3f — the Tigervision 3F board (8K): pages its lower half from the value
; on the data bus, watching writes to the TIA rather than hotspot addresses.
;
; The 6507 gives the cartridge a 4K window at $F000-$FFFF (any access with A12
; high). The 3F board splits it in two:
;   - Upper 2K, $F800-$FFFF: permanently the last 2K of the image; it never
;     moves. The program, the reset vectors, and all switching code live here,
;     so switching the lower bank never disturbs the code that is running.
;   - Lower 2K, $F000-$F7FF: a window onto one of the image's 2K banks, chosen
;     at run time.
; An 8K image is four 2K banks. Bank 3 is the same image that fills the upper
; 2K, and it can be paged into the lower window like any other bank.
;
; The select mechanism is unusual. The board carries one '173 latch (a data
; register), and the cart port has no read/write line, so the latch cannot tell
; a store from a load. It watches addresses and bus edges instead:
;   1. An access with A6 and A7 both low (the $0000-$003F range) arms the latch.
;   2. If A12 rises on the very next bus cycle, the latch clocks, capturing
;      whatever the data bus holds at that instant.
;
; The data bus is capacitive: at the A12 rise it still holds the previous
; cycle's byte. This gives two cases:
;   - After `sta $3F`, that leftover byte is the value just stored. So the
;     written value is the bank number — that is the entire select mechanism.
;   - After a read of $3F (an unused TIA address, so nothing drives the bus),
;     the leftover byte is the stale open-bus value — the operand $3F itself —
;     so a read below $40 also pages, to $3F masked by the bank count.
; This is why Tigervision code avoids $00-$3F entirely and reaches the TIA only
; through its $40-$7F mirrors (repeats of the same registers, with A6=1, which
; never arms the latch), reads included.
;
; Two shapes therefore arm the latch by accident:
;   - A plain read of $3F: it arms, and the next cycle is an opcode fetch (A12
;     rises), so the latch captures the open-bus residue $3F -> bank 3.
;   - The phantom-read store: a page-crossing indexed store dummy-reads the
;     un-carried address before the real write. If that dummy read falls below
;     $40 it arms the latch, the real write leaves the stored value on the bus,
;     and the next opcode fetch clocks it in. The store pages the bank exactly as
;     if it had written to $3F.
;
;   CODE $01 = write value $00 to $3F did not page bank 0 into the lower window
;        $02 = write value $01 to $3F did not page bank 1
;        $03 = write value $02 to $3F did not page bank 2
;        $04 = write value $03 to $3F did not page bank 3 (the fixed image)
;        $05 = the value selects, not the address: writing $02 to $05 (a
;              different sub-$40 address) did not page bank 2
;        $06 = value masking: writing $07 to a 4-bank image did not resolve to
;              bank 3 (value taken modulo the bank count)
;        $07 = a read of $3F did not page the bank to the open-bus residue
;              ($3F & bank mask = bank 3)
;        $08 = phantom-read hazard: the page-crossing store (dummy read $003F,
;              real write $013F) did not page the bank to the stored value
;
; Cells $07/$08 assert the bus-level trigger above (any access below $40 arms;
; the A12 rise clocks it) — the latch wiring traced from a real Tigervision
; board. Some implementations instead model a write-only convention and leave
; the bank parked on a read of $3F; games run under either, since Tigervision
; code keeps every TIA access, reads included, on the $40-$7F mirrors. The
; test itself is untested on hardware.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: 3F

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SIGADDR = $F7F0                 ; lower-window read address of the per-bank signature
                                ; (in-bank offset $7F0; upper image sees bank 3's at $FFF0)

; probe result cells (scratch is $90+; harness owns $80-$89)
SIG0   = $90                    ; bank 0 signature after selecting it
SIG1   = $91
SIG2   = $92
SIG3   = $93
SIGV   = $94                    ; signature after a value-select via a different address
SIGRD  = $95                    ; signature after a read of $3F (open-bus residue selects)
SIGPH  = $96                    ; signature after the phantom-read hazard store
SIGMASK= $97                    ; signature after writing an over-range value ($07)

; ------------------------------------------------------- banks 0-2 (lower-window data)
; Pure data: no code ever runs from the lower window. Each bank opens with two
; non-uniform 128-byte halves so it never fingerprints as a phantom Superchip
; (a bank whose first 128 bytes equal the next 128 can be misdetected as SC
; RAM), then $FF filler up to the signature at offset $7F0.
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
        DATABANK $0000, $30             ; bank 0 signature $30
        SEG BANK1
        DATABANK $0800, $31             ; bank 1 signature $31
        SEG BANK2
        DATABANK $1000, $32             ; bank 2 signature $32

; ------------------------------------------------ bank 3 = fixed upper 2K + all code
        SEG BANK3
        ORG $1800
        RORG $F800
ENTRY:
Main:
        CLEAN_START
        TEST_BEGIN

        ; --- bank walk: the written value selects the lower bank ---
        ; The power-on lower bank is undefined, so every check below selects its
        ; own bank first; no assertion reads the lower window before a select.
        lda #$00
        sta $3F                         ; select bank 0 (value 0)
        lda SIGADDR
        sta SIG0
        lda #$01
        sta $3F                         ; A9 01 85 3F : select bank 1 (value 1)
        lda SIGADDR
        sta SIG1
        lda #$02
        sta $3F                         ; A9 02 85 3F : select bank 2 (value 2)
        lda SIGADDR
        sta SIG2
        lda #$03
        sta $3F                         ; select bank 3 (the fixed image, in the low window)
        lda SIGADDR
        sta SIG3

        ASSERT_EQ SIG0, $30, $01
        ASSERT_EQ SIG1, $31, $02
        ASSERT_EQ SIG2, $32, $03
        ASSERT_EQ SIG3, $33, $04

        ; --- the value selects, not the address: write $02 to $05, not $3F ---
        lda #$00
        sta $3F                         ; park bank 0 first (so a no-op would read $30)
        lda #$02
        sta $05                         ; write value $02 to a different sub-$40 address
        lda SIGADDR
        sta SIGV
        ASSERT_EQ SIGV, $32, $05        ; value $02 paged bank 2 regardless of address

        ; --- value masking: an over-range value folds modulo the bank count ---
        ; (probed before the contested read cells so every model reaches it)
        lda #$07
        sta $3F                         ; value 7 on a 4-bank image -> bank 7 & 3 = bank 3
        lda SIGADDR
        sta SIGMASK
        ASSERT_EQ SIGMASK, $33, $06

        ; --- a read below $40 arms the latch too: open-bus residue selects ---
        lda #$02
        sta $3F                         ; park bank 2 (a no-switch result would read $32)
        lda $3F                         ; A5 3F: read $003F — arms; the next opcode fetch
                                        ;   clocks in the open-bus residue $3F -> bank 3
        lda SIGADDR
        sta SIGRD
        ASSERT_EQ SIGRD, $33, $07       ; paged to bank 3 ($3F & 3), not still bank 2

        ; --- phantom-read hazard: the store's own value gets clocked in ---
        lda #$01
        sta $3F                         ; park bank 1 (a no-switch result would read $31)
        lda #$03                        ; the value the hazard store will leave on the bus
        ldx #$4F
        sta.w $00F0,x                   ; 9D F0 00 : dummy read $003F arms; write $013F
                                        ;   (A6/A7 still low) keeps it armed with A on the
                                        ;   bus; the next fetch clocks it -> bank 3.
                                        ;   $013F is a TIA mirror of unused $3F: nothing
                                        ;   real is poked
        lda SIGADDR
        sta SIGPH
        ASSERT_EQ SIGPH, $33, $08       ; paged to the stored value ($03), not still bank 1

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $1800+$7F0                  ; bank 3's signature, seen at $F7F0 in the low
        RORG $FFF0                      ; window and at $FFF0 in the fixed upper image
        .byte $33

        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
