; rmw-wsync — RDY halts the 6507 on READ cycles only, never on writes.
;
; Writing any value to WSYNC ("wait for sync") pulls the CPU's RDY pin low. RDY
; is the 6507's hold input: the CPU samples it as it begins each bus cycle, and
; while RDY is low it freezes — but only at a READ. On a read the CPU stalls in
; place until RDY rises again; a write cycle always completes regardless. The
; TIA releases RDY when the beam reaches the start of the next scanline, so a
; store to WSYNC parks the program at its next read (the following opcode fetch)
; until the line ends.
;
; A read-modify-write to WSYNC turns the read-only rule into something you can
; measure. `inc WSYNC` writes twice: the dummy write (the old value) strobes
; WSYNC and pulls RDY low, but the very next cycle is the real write, and RDY
; does not stop writes — it runs at once, strobing WSYNC a second time on the
; same line. Only the opcode fetch after it, a read, is held to the end of the
; line. Net cost: exactly ONE scanline, the same as a plain `sta WSYNC`. Halting
; on the write instead would defer the real write to the next line, where it
; strobes WSYNC again and burns a SECOND line.
;
; The RIOT timer is the ruler: it has no RDY pin and keeps counting straight
; through the halt, ticking down once per CPU cycle. The test times one WSYNC,
; two WSYNCs and one INC WSYNC. One minus two must be exactly 76 CPU cycles —
; a scanline's 228 colour clocks divided by 3 — proving the ruler resolves a
; single line. INC WSYNC must then read the same as one WSYNC: one line, not two.
;
;   CODE $01 = 1-line vs 2-line readings not 76 cycles apart: the ruler does
;              not resolve one scanline
;        $02 = INC WSYNC did not cost exactly one line (RDY halted a write
;              and pushed it to the next line, or neither write strobed WSYNC)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

MEAS1   = $90                   ; timer reading after ONE WSYNC
MEAS2   = $91                   ; timer reading after two WSYNCs
MEASI   = $92                   ; timer reading after INC WSYNC
DIFF    = $93

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ; --- ONE WSYNC: 1-line reference ---
        sta WSYNC               ; align to a line start
        lda #200
        sta TIM1T               ; timer = 200, ticking -1 per CPU cycle; runs through the halt
        sta WSYNC               ; halt to the end of this line
        lda INTIM               ; read the timer after one line...
        sta MEAS1               ; ...MEAS1

        ; --- two WSYNCs: 2-line reference (byte-identical bracket) ---
        sta WSYNC               ; align to a line start
        lda #200
        sta TIM1T               ; timer = 200 again
        sta WSYNC               ; halt to end of line...
        sta WSYNC               ; ...and halt through one more
        lda INTIM               ; read the timer after two lines...
        sta MEAS2               ; ...MEAS2 = MEAS1 - 76

        ; --- INC WSYNC: must cost ONE line (RDY halts the fetch, not the writes) ---
        sta WSYNC               ; align to a line start
        lda #200
        sta TIM1T               ; timer = 200 again
        inc WSYNC               ; read + dummy write (strobe) + real write (strobe): one line
        lda INTIM               ; read the timer after the inc...
        sta MEASI               ; ...MEASI

        ; the ruler resolves exactly one scanline: MEAS1 - MEAS2 must be 76
        lda MEAS1
        sec
        sbc MEAS2
        sta DIFF
        ASSERT_EQ DIFF, 76, $01

        ; INC WSYNC cost ONE line, not two: MEAS1 - MEASI must be 0
        lda MEAS1
        sec
        sbc MEASI
        sta DIFF
        ASSERT_EQ DIFF, $00, $02

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
