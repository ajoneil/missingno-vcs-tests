; timer-divisors — the RIOT timer's once-per-64-clocks cadence and the rules
; that clear the underflow flag.
;
; The RIOT (the 6532 support chip) holds a one-byte countdown timer. Writing a
; start value to an interval register both arms the timer and picks how fast it
; falls: a write to TIM64T makes the count decrement once every 64 CPU clocks.
; The current count is read at INTIM. When the count runs past 0 the timer
; underflows — it wraps to $FF and sets bit 7 of the flag register TIMINT.
;
; Two clearing rules tell the two read registers apart. Reading TIMINT (the
; flag register) reports the flags but leaves the timer's underflow flag set —
; it clears only the separate PA7 edge flag in bit 6. Reading INTIM (the count)
; is what clears the underflow flag, and the same read also ends the
; post-underflow once-per-clock free-run and re-arms the selected interval.
;
; The decrement is measured differentially — once across one scanline, once
; across many — so the setup instructions and the prescaler phase cancel in the
; difference, leaving the decrement of the extra scanlines alone.
;
;   CODE $01 = sixteen scanlines of TIM64T decrement was not 19 — the
;              once-per-64 cadence is wrong
;        $02 = the underflow flag was clear right after the count ran past 0 —
;              underflow did not raise it
;        $03 = a read of TIMINT cleared the underflow flag — it must not; only
;              an INTIM read clears it
;        $04 = a read of INTIM did not clear the underflow flag
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

        ; --- TIM64T cadence: 16 scanlines = 1216 clocks = exactly 19 ---
        ; 76 is not a multiple of 64, so per line the count falls by 1 or 2 with
        ; the prescaler phase — not an invariant. Over a whole number of
        ; prescaler periods (16 lines = 19 periods) it is exactly 19. The
        ; differential (1 line vs 17 lines) cancels the setup offset.
        sta WSYNC                       ; align to a fresh scanline
        lda #$FF
        sta TIM64T                      ; arm: count = $FF, one decrement per 64
        sta WSYNC                       ; let it fall across ONE scanline
        lda INTIM
        sta $90                         ; A: count after 1 line
        sta WSYNC                       ; identical setup again...
        lda #$FF
        sta TIM64T                      ; arm: count = $FF
        ldx #17
.t64:   sta WSYNC                       ; ...let it fall across SEVENTEEN lines
        dex
        bne .t64
        lda INTIM
        sta $91                         ; B: count after 17 lines
        lda $90                         ; A - B: decrement over the extra 16 lines
        sec
        sbc $91
        sta $92
        ASSERT_EQ $92, 19, $01          ; assert (A - B) == 19  (16*76/64 = 19)

        ; --- clearing rules: underflow sets the flag; only INTIM clears it ---
        lda #1
        sta TIM64T                      ; arm: count = 1, /64 -> underflow ~128 clocks
        ldx #40
.fw:    dex                             ; burn ~200 cycles: past underflow
        bne .fw

        lda TIMINT                      ; read the flag register (must not clear it)
        and #$80
        sta $90
        ASSERT_EQ $90, $80, $02         ; assert the flag is set after underflow

        lda TIMINT                      ; read TIMINT again — flag must still be set
        and #$80                        ; (a TIMINT read clears only the PA7 flag)
        sta $90
        ASSERT_EQ $90, $80, $03

        lda INTIM                       ; read INTIM — this clears the timer flag
        lda TIMINT                      ; and the flag register now shows it gone
        and #$80
        sta $90
        ASSERT_EQ $90, $00, $04         ; assert the flag is clear

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
