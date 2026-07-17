; io-mirrors — the RIOT's I/O registers and the TIA's read registers each answer
; at many addresses, because the console decodes only a few of the address lines.
;
; The 6507 CPU has 13 address lines, A0-A12. The board picks which chip answers
; a bus access from just three of them: A12=1 selects the cartridge; below that,
; A7 splits the TIA (the video/audio chip) from the RIOT (RAM/timer/I/O), and A9
; splits the RIOT's RAM from its I/O and timer registers. The lines a device
; does not decode are "don't-care": flipping one changes the address but reaches
; the very same register, so every register appears at many aliased addresses.
;
; RIOT I/O and timer are selected by A12=0, A7=1, A9=1, and live at $280 and up.
; Inside that block only the low address bits pick the register, so A8, A10 and
; A11 are don't-care: $280, $380, $680 and $A80 are all one and the same
; register. The TIA is selected by A12=0, A7=0; its read registers decode only
; A0-A3, so A4, A5 and A6 are don't-care and $00 aliases $40.
;
; The test writes a known value to a register through its base address, then
; reads it back through each mirror and checks it matches. A console that
; decoded the whole address bus would find nothing at the mirror and mismatch.
;
;   CODE $01 = SWCHA output latch: base $280 didn't read back the written value
;              (setup check — the latch itself is broken)
;        $02 = SWCHA seen through $380 (A8 flipped) didn't match the base
;        $03 = SWCHA seen through $680 (A10 flipped) didn't match the base
;        $04 = SWACNT (direction reg, a different offset) through $381 (A8) didn't match
;        $05 = TIA read reg CXM0P seen through $40 (A6 flipped) didn't match $00
;        $06 = SWCHA seen through $A80 (A11 flipped) didn't match the base
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

        ; --- RIOT I/O port mirrors (strong: a known latched value) ---
        ; Drive port A entirely as output so a written value reads straight back
        ; from the output latch (no controller input in the read path).
        lda #$FF
        sta SWACNT                      ; port A: every pin an output
        lda #$5A
        sta SWCHA                       ; output latch = $5A, driven onto the pins
        ASSERT_EQ SWCHA,  $5A, $01      ; base $280: read the latch back (setup)
        ASSERT_EQ $0380,  $5A, $02      ; $380 = A8 flipped -> same register
        ASSERT_EQ $0680,  $5A, $03      ; $680 = A10 flipped -> same register
        ASSERT_EQ $0A80,  $5A, $06      ; $A80 = A11 flipped -> same register

        ; --- RIOT I/O read mirror at a different register offset ---
        ; Prove the aliasing holds across the whole I/O block, not just SWCHA.
        ; SWACNT (the port-A direction register at offset 1, base $281) is
        ; readable and we just set it to $FF, so its value is deterministic
        ; (unlike the console switches, whose state is driven from outside).
        ASSERT_EQ $0381,  $FF, $04      ; $381 = A8 flipped -> SWACNT ($281), expect $FF

        ; --- TIA read-register mirror (A6 don't-care) ---
        ; Clear collisions so CXM0P's two driven bits (7,6) are defined (0),
        ; then read it through $00 and its $40 alias. Only bits 7-6 come from
        ; the collision latch; bits 5-0 read the floating data bus, so mask
        ; before comparing. This is a light check (both read 0 post-clear) — a
        ; stronger TIA-decode check, driving a real collision through a mirror
        ; address, is a separate test.
        sta CXCLR                       ; strobe: clear the collision latches
        lda CXM0P                       ; read CXM0P at base $00
        and #$C0                        ; keep only the two collision bits
        tax                             ; X = expected (base value, masked)
        lda $40                         ; read the same register via $40 (A6 flipped)
        and #$C0                        ; mask the same way
        ldy #$05                        ; fail code $05
        jsr assert_eq                   ; assert the mirror == the base

        ; Note: reads of write-only registers / open-bus (floating-bus) return
        ; the last value on the data bus. That value depends on prior bus
        ; activity, so it is not asserted here — floating-bus is covered separately.

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
