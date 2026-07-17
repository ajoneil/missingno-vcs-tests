; io-ports — with every port A pin an output, the port reads back exactly what
; was written to it.
;
; The RIOT (the 6532 chip that holds the console's RAM, timer, and I/O) has two
; 8-bit parallel ports, A and B; on the Atari these carry the joystick lines and
; the console switches. Each port has two registers. SWACNT is port A's data-
; direction register: a 1 bit makes the matching pin an OUTPUT, a 0 bit an
; INPUT. SWCHA is port A's data register: writing it stores all eight bits into
; the port's output latch, and reading it returns the eight PIN levels. A pin
; that is an output takes its level from its output-latch bit; a pin that is an
; input takes its level from the outside world (an idle Atari pin floats high).
;
; So with SWACNT=$FF — every pin an output — nothing from the outside world is
; in the read path: whatever is written to SWCHA is driven onto all eight pins
; and must read straight back unchanged. The test writes four patterns and reads
; each one back. $55 and $AA are complementary checkerboards that drive every pin
; high in one and low in the other; $FF and $00 drive all pins one way at once.
;
;   CODE $01 = wrote $55, read back something else
;        $02 = wrote $AA, read back something else
;        $03 = wrote $FF, read back something else
;        $04 = wrote $00, read back something else
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

        lda #$FF
        sta SWACNT                      ; port A: every pin an output

        lda #$55
        sta SWCHA                       ; drive pins = 0101_0101
        ASSERT_EQ SWCHA, $55, $01       ; read the pins back: expect $55
        lda #$AA
        sta SWCHA                       ; drive pins = 1010_1010
        ASSERT_EQ SWCHA, $AA, $02       ; read back: expect $AA
        lda #$FF
        sta SWCHA                       ; drive every pin high
        ASSERT_EQ SWCHA, $FF, $03       ; read back: expect $FF
        lda #$00
        sta SWCHA                       ; drive every pin low
        ASSERT_EQ SWCHA, $00, $04       ; read back: expect $00

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
