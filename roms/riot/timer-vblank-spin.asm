; timer-vblank-spin — the interval timer's countdown, observed at 1-cycle
; resolution through the spin-loop games use to time vertical blank.
;
; The RIOT chip carries an interval timer. Software writes a start count to a
; timer register, the write picks the tick rate, and the register INTIM reads
; back the current count. Here the timer is armed through TIM64T, which counts
; down once every 64 CPU cycles. The usual way a game paces the off-screen parts
; of a frame — vertical blank and overscan, the lines where the electron beam is
; not drawing picture — is to arm the timer, do its work, then spin on
; `lda INTIM / bne` until the count reaches zero. The CPU cycle on which that
; loop finally falls through is what decides which scanline the blank period ends
; on, so the timer's exact countdown edge is visible from software.
;
; The count reaches zero somewhere inside the 64-cycle window of a prescaler
; step, and the 9-cycle spin loop samples INTIM only once per pass — so where the
; fall-through lands depends on how the loop's sampling phase sits against the
; prescaler. The test arms the timer identically each time and sweeps that
; sampling phase in coarse steps, counting the loop iterations to zero at each.
;
; The eight counts are fully deterministic. As the phase slides they hold near 47
; and step up by one exactly where the prescaler edge crosses a loop boundary:
; 46 at the first phase, 47 across the next five, then 48 at the last two. A
; countdown edge landing one CPU cycle early or late would move where that step
; happens and change the profile.
;
;   CODE $01..$08 = the iteration count at phase step 0..7 did not match
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
COUNT   = $90                   ; 8-byte per-phase iteration profile ($90..$97)
IDX     = $98                   ; phase-sweep index
STEPS   = 8
TVAL    = 8                     ; timer start count: 8 steps at the ÷64 rate

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ldx #0
.sweep:
        stx IDX                         ; phase step being measured

        lda #TVAL
        sta TIM64T                      ; arm: resets the 64-cycle prescaler to a
                                        ;   known phase, count = TVAL
        txa                             ; waste 2*(STEPS-IDX) cycles before the loop:
        clc                             ;   jump IDX bytes into the NOP sled, so the
        adc #<Sled                      ;   first INTIM read slides across the
        sta VEC                         ;   prescaler two cycles per step
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)                       ; -> Sled+IDX: runs (STEPS-IDX) NOPs
Sled:
        REPEAT STEPS
        nop
        REPEND

        ldx #0                          ; count = 0
.wait:
        inx                             ; count++
        lda INTIM
        bne .wait                       ; loop until INTIM first reads 0

        txa                             ; profile[IDX] = count
        ldx IDX
        sta COUNT,x

        ldx IDX
        inx
        cpx #STEPS
        bne .sweep                      ; next phase step

        ASSERT_EQ COUNT+0, $2E, $01     ; the 46->47->48 staircase as the phase
        ASSERT_EQ COUNT+1, $2F, $02     ;   slides two cycles per step
        ASSERT_EQ COUNT+2, $2F, $03
        ASSERT_EQ COUNT+3, $2F, $04
        ASSERT_EQ COUNT+4, $2F, $05
        ASSERT_EQ COUNT+5, $2F, $06
        ASSERT_EQ COUNT+6, $30, $07
        ASSERT_EQ COUNT+7, $30, $08
        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
