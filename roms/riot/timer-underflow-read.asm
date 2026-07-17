; timer-underflow-read — reading the interval timer on the exact cycle it
; underflows does not clear the timer flag.
;
; The RIOT chip carries an interval timer. Software writes a start count to one
; of the timer registers, and the write also picks the tick rate: TIM1T counts
; down once per CPU cycle, TIM64T once every 64. The register INTIM reads back
; the current count. When the count falls past zero the timer UNDERFLOWS: it
; reloads to $FF and raises the timer flag — bit 7 of the interrupt register
; TIMINT — so a program that was busy at the moment can still tell it happened.
;
; Reading INTIM normally clears that flag. The single exception is the CPU cycle
; on which the underflow itself occurs: a read landing exactly there returns $FF
; (the value just reloaded) but leaves the flag set. A read one cycle to either
; side behaves normally — the cycle before, the flag is not yet raised; the
; cycle after, the read clears it as usual.
;
; The underflow cycle is not hardcoded. The test sweeps the start count so each
; step delays the underflow by one CPU cycle against a read whose own timing
; never moves; exactly one step lines the read up with the underflow, and a read
; returning $FF identifies that step. The flag is sampled straight afterwards.
;
;   CODE $01 = the underflow-cycle INTIM read wrongly cleared the timer flag
;        $02 = the sweep never hit the underflow cycle (no read saw $FF); widen
;              the padding or sweep range — a harness fault, not a hardware verdict
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

        lda #0
        sta $94                         ; gotFF  = 0  (set once a read sees $FF)
        sta $95                         ; ffFlag = 0  (TIMINT bit7 from that read)

        ldx #64                         ; V = 64; swept down to 1, adding one cycle
.sweep:                                 ;   of underflow skew per step
        stx TIM1T                       ; arm: count = V at the ÷1 rate; the write
                                        ;   itself clears the timer flag
        ; Fixed padding so the read below lands on the underflow for exactly one V
        ; in the sweep. The offset need not be known: the sweep walks the read past
        ; the underflow one cycle per step, and the $02 guard confirms it got there.
        nop
        nop
        nop
        nop
        nop
        nop
        lda INTIM                       ; READ UNDER TEST — may land on underflow
        sta $92                         ; obsIntim = INTIM
        lda TIMINT
        and #$80
        sta $93                         ; obsFlag  = TIMINT bit7, read just after
        lda $92
        cmp #$FF                        ; check this read for the reload value $FF
                                        ;   only the underflow cycle can: after the
                                        ;   reload the timer free-runs down one per
                                        ;   cycle, so it will not read $FF again for
                                        ;   256 cycles — far past this read window
        bne .next                       ;   no  -> not the underflow cycle
        lda #1
        sta $94                         ; yes -> gotFF = 1
        lda $93
        sta $95                         ;        ffFlag = the captured flag bit
.next:
        dex
        bne .sweep                      ; next V

        ; The sweep must have reached the underflow cycle (some read saw $FF),
        ; else the padding or range needs widening — a harness fault, not a verdict.
        ASSERT_EQ $94, 1, $02           ; gotFF  == 1

        ; The behaviour under test: the read that landed on the underflow returned
        ; $FF but must not have cleared the flag, so TIMINT bit7 is still set.
        ASSERT_EQ $95, $80, $01         ; ffFlag == $80 (flag survived the read)

        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
