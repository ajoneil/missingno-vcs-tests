; io-output — port A's output register holds every written bit intact, even the
; bits whose pins are inputs, and survives direction changes untouched.
;
; The RIOT (the 6532 chip carrying the console's RAM, timer, and I/O) drives
; port A through two registers. SWACNT is the data-direction register: a 1 bit
; makes that pin an OUTPUT, a 0 bit an INPUT. SWCHA is the port itself. Behind
; SWCHA sits a full 8-bit output register that latches all eight bits of every
; write, regardless of the current directions — direction only decides which of
; those latched bits actually reach the outside pins. A read of SWCHA returns
; the PIN levels: an output pin reads its own output-register bit, while an
; input pin reads the outside world (an idle Atari pin floats high, so input
; pins read as 1).
;
; So a bit written while its pin is an INPUT is not lost — it sits in the output
; register the whole time, hidden from reads, and appears the instant that pin
; is flipped to OUTPUT. Direction changes never disturb the stored bits. A model
; that only remembers bits while their pins are outputs, or that lets an input
; pin's level leak into the stored register, loses the written value — which
; breaks titles that drive port A as outputs, such as keypad controllers.
;
; The test needs an idle port: nothing driving it from outside, so input pins
; read high. On real hardware, run with no controller input active.
;
;   CODE $01 = all pins input, output reg holds $55: reading pins should give
;              $FF (the stored $55 is hidden), got something else
;        $02 = low nibble now output: the $5 stored while input should surface,
;              reading $F5 (high nibble still floating high), got something else
;        $03 = wrote $AA while low nibble is output: expect to read $FA
;        $04 = all pins output: the whole output register shows, incl. the high
;              nibble stored back when it was still an input, expect $AA
;        $05 = all pins input again: back to the floating-high pins, expect $FF
;        $06 = all pins output once more: the stored value rode through the
;              direction round-trip unchanged, expect $AA
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

        lda #$00
        sta SWACNT                      ; port A: every pin an input
        lda #$55
        sta SWCHA                       ; output reg = $55 (hidden: no pin is output)
        ASSERT_EQ SWCHA, $FF, $01       ; read the pins: all float high -> $FF

        lda #$0F
        sta SWACNT                      ; low nibble -> output, high nibble input
        ASSERT_EQ SWCHA, $F5, $02       ; low nibble now shows stored $5, high floats -> $F5

        lda #$AA
        sta SWCHA                       ; output reg = $AA (all 8 bits, still part-output)
        ASSERT_EQ SWCHA, $FA, $03       ; low nibble drives $A, high floats -> $FA

        lda #$FF
        sta SWACNT                      ; every pin an output
        ASSERT_EQ SWCHA, $AA, $04       ; whole output reg surfaces, incl. high nibble from $03

        lda #$00
        sta SWACNT                      ; every pin an input again
        ASSERT_EQ SWCHA, $FF, $05       ; pins float high once more -> $FF

        lda #$FF
        sta SWACNT                      ; and back to all-output: no write to SWCHA between
        ASSERT_EQ SWCHA, $AA, $06       ; stored $AA survived the direction round-trip

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
