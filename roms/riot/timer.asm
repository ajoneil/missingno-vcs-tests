; timer — the RIOT interval timer: underflow raises a flag, and each interval
; register counts down at its own fixed cadence.
;
; The RIOT (the 6532 support chip) contains a one-byte countdown timer that
; runs on its own, independent of the CPU. Software arms it by writing a start
; value to one of four interval registers, and the register chosen also selects
; how many CPU clocks pass between decrements: a write to TIM1T decrements the
; count every clock, TIM8T every 8 clocks, TIM64T every 64, T1024T every 1024.
; A hidden prescaler counts the clocks within each interval; the current count
; is read back at INTIM.
;
; When the count is already 0 and one more decrement comes due, the timer
; underflows: it wraps to $FF, sets bit 7 of the flag register TIMINT, and from
; then on decrements once per clock regardless of the selected interval. Bit 6
; of TIMINT is an unrelated flag (a PA7 port edge), so a test that cares only
; about the timer masks bit 7 on its own.
;
; The timer has no notion of the CPU being stalled — it keeps counting through
; a WSYNC freeze — which makes it the one clock in the machine able to measure
; elapsed time across a halted CPU. A scanline is 76 CPU clocks.
;
; A raw INTIM reading would fold in the arm/setup instructions and the unknown
; prescaler phase at the moment of the write, so each cadence is measured twice
; with byte-identical setup — once letting the count fall across one scanline,
; once across several — and the two readings subtracted. The setup overhead and
; the phase cancel in the difference, leaving exactly the decrement of the extra
; scanlines.
;
;   CODE $01 = the underflow flag (TIMINT bit 7) was still clear after the count
;              had run past 0 — underflow did not raise it
;        $02 = one scanline of TIM1T decrement was not 76 — the once-per-clock
;              cadence is wrong, or the timer froze along with the CPU at WSYNC
;        $03 = eight scanlines of TIM8T decrement was not 76 — the once-per-8
;              cadence is wrong
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

        ; --- underflow raises the timer flag (bit 7 of TIMINT) ---
        ; mask bit 7 only: bit 6 is the PA7 edge flag, a separate concern
        lda #$02
        sta TIM64T              ; arm: count = 2, one decrement per 64 clocks
        ldx #60                 ; ...INTIM=2, /64 -> underflow after ~192 cycles
.uw:    dex                     ; burn ~300 cycles: comfortably past underflow
        bne .uw
        lda TIMINT              ; read the flag register
        and #$80                ; keep the timer flag, drop the PA7 flag
        sta $90
        ASSERT_EQ $90, $80, $01 ; assert the timer flag is set

        ; --- TIM1T: exactly 76 decrements per scanline (once per clock) ---
        sta WSYNC               ; align to a fresh scanline
        lda #$FF
        sta TIM1T               ; arm: count = $FF, one decrement per clock
        sta WSYNC               ; let it fall across ONE scanline
        lda INTIM
        sta $90                 ; A = count after one scanline
        sta WSYNC               ; identical setup again...
        lda #$FF
        sta TIM1T               ; arm: count = $FF
        sta WSYNC               ; ...but let it fall across two scanlines
        sta WSYNC
        lda INTIM
        sta $91                 ; B = count after two scanlines
        lda $90                 ; A - B: setup and phase cancel, leaving exactly
        sec                     ; one scanline's worth of decrement
        sbc $91
        sta $92
        ASSERT_EQ $92, 76, $02  ; assert (A - B) == 76

        ; --- TIM8T: 8 scanlines = 608 clocks = exactly 76 decrements ---
        ; 76 is not a multiple of 8, so per line the count falls by 9 or 10 with
        ; the prescaler phase — not a hardware invariant. Over a whole number of
        ; prescaler periods (8 lines = 76 periods) it is exactly 76, phase-free.
        ; The differential cancels the setup.
        sta WSYNC               ; align to a fresh scanline
        lda #$FF
        sta TIM8T               ; arm: count = $FF, one decrement per 8 clocks
        sta WSYNC               ; let it fall across ONE scanline
        lda INTIM
        sta $90                 ; A = count after 1 line
        sta WSYNC               ; identical setup again...
        lda #$FF
        sta TIM8T               ; arm: count = $FF
        ldx #9
.t8:    sta WSYNC               ; ...and let it fall across NINE scanlines
        dex
        bne .t8
        lda INTIM
        sta $91                 ; B = count after 9 lines
        lda $90                 ; A - B: decrement over the extra 8 lines
        sec
        sbc $91
        sta $93
        ASSERT_EQ $93, 76, $03  ; assert (A - B) == 76  (8*76 clocks / 8 = 76)

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
