; wsync — a scanline lasts 76 CPU cycles, and WSYNC halts the CPU until the
; next one starts.
;
; Writing any value to WSYNC pulls the CPU's RDY pin low, freezing the program
; mid-stream; the TIA releases RDY when the beam reaches the start of the next
; scanline. A scanline is 228 TIA colour clocks and the CPU clock is the TIA
; clock divided by 3, so consecutive scanline starts are exactly 76 CPU cycles
; apart (NTSC and PAL alike). The RIOT has no RDY pin — its timer keeps
; counting while the CPU is frozen — and TIM1T makes it tick once per CPU
; cycle, so it is the one stopwatch in the machine that runs through a WSYNC.
;
; A frozen CPU can't count cycles, and a raw timer reading would include the
; setup instructions and the unknown phase where the CPU resumes. So the test
; measures twice: start the timer, wait through ONE WSYNC, read it (A); then
; repeat with byte-identical setup but two WSYNCs (B). All overhead cancels in
; the difference, leaving exactly the one extra scanline: A - B must be 76.
;
;   CODE $01 = A - B != 76: a scanline is not 76 CPU cycles — or the timer
;              froze with the CPU, or TIM1T isn't ticking once per cycle
;              (timer-divisors isolates the cadence if this is ambiguous)
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

        ; Measurement A: how far does the timer fall across ONE scanline?
        sta WSYNC               ; wait for a fresh scanline
        lda #$FF
        sta TIM1T               ; timer = $FF, ticking once per CPU cycle
        sta WSYNC               ; freeze until the next scanline starts
        lda INTIM
        sta $90                 ; A = timer after one scanline

        ; Measurement B: identical setup, but across two scanlines
        sta WSYNC               ; wait for a fresh scanline
        lda #$FF
        sta TIM1T               ; timer = $FF again
        sta WSYNC               ; freeze until the next scanline starts...
        sta WSYNC               ; ...and freeze through one more
        lda INTIM
        sta $91                 ; B = timer after two scanlines

        lda $90                 ; A - B: the setup overhead cancels, leaving
        sec                     ; exactly one scanline's worth of timer ticks
        sbc $91
        sta $92
        ASSERT_EQ $92, 76, $01  ; assert (A - B) == 76

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
