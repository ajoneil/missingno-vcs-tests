; floating-bus — reading an address no chip drives returns the last byte left
; on the data bus.
;
; The console's eight data lines have no pull-up resistors, so the bus has no
; fixed value of its own: after every access the lines keep, as stored charge,
; the last byte that was driven onto them. When the CPU reads an address that no
; chip answers, nothing drives the bus and the read returns that retained byte.
; For a zero-page read (`lda $nn`) the last thing the CPU placed on the bus is
; the instruction's own operand byte $nn, fetched the cycle before — so a
; floating read hands back the address's low byte.
;
; The TIA (the video/sound chip) decodes reads from its low address bits, and
; the codes ending in $E or $F map to no read register at all. Reading `lda $2E`
; or `lda $3E` therefore floats the bus and returns $2E / $3E — each read's own
; operand. Games lean on this for cheap randomness.
;
; The test reads the two undriven TIA codes and checks each returns its own
; operand; because $2E and $3E differ, a pass proves the byte tracks the operand
; rather than being a fixed constant. A normal RAM read is the control: it
; returns the stored value, not the operand — catching an implementation that
; hands back a constant, the address, or the operand for every read.
;
;   CODE $01 = driven RAM read wrong: a real, driven read returned something
;              other than the stored byte (the control)
;        $02 = floating read of $2E did not return the last bus byte ($2E)
;        $03 = floating read of $3E did not return the last bus byte ($3E)
;              ($02 and $03 differing proves the bus tracks the operand)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

CTRL    = $95                   ; a driven RAM cell for the control read
S1      = $90                   ; driven read result
S2      = $91                   ; floating read of $2E
S3      = $92                   ; floating read of $3E

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ; control: a real, driven read returns the STORED byte, not the operand
        lda #$99
        sta CTRL                ; ram[$15] = $99   (driven via $0095)
        lda CTRL                ; read back: RAM drives the bus
        sta S1                  ; S1 = $99 (stored), not $95 (the operand)

        ; floating: TIA codes ending $E/$F have no read register, so the bus is
        ; left undriven and keeps this lda's own zero-page operand
        lda $2E                 ; undriven -> returns operand $2E
        sta S2                  ; S2 = $2E
        lda $3E                 ; undriven -> returns operand $3E
        sta S3                  ; S3 = $3E

        ASSERT_EQ S1, $99, $01  ; driven read must equal the stored byte
        ASSERT_EQ S2, $2E, $02  ; floating read must equal its operand $2E
        ASSERT_EQ S3, $3E, $03  ; floating read must equal its operand $3E
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
