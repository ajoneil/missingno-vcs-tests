; wsync-line-end — a WSYNC strobed AT the line boundary does not spill.
;
; WSYNC pulls RDY low until the line ends. Strobed at the very end of a line
; a race appears: a write landing on the line's FINAL CPU cycle
; (cycle 76) is absorbed at the wrap — the CPU resumes at the next line's
; start exactly as if it had halted, costing nothing extra — while a write
; landing one cycle later (cycle 1 of the new line, reached by overshooting
; the boundary) parks the CPU to THAT line's end, a full 76 cycles more. A
; WSYNC latch that survives the wrap would halt the cycle-76 case a whole
; line; one that absorbs early-next-line writes would exit a line early.
;
; Eight measurements sweep a bare `sta WSYNC` across write cycles 73..80, with
; the RIOT timer as the beam ruler (it counts through the halt); each records
; the beam time from a fixed post-WSYNC bracket to the first instruction after
; the op. Cycles 73..76 all resume at the next line start (equal times);
; cycles 77..80 park the overshot line (exactly +76 on the same bracket).
;
;   CODE $01 = the ruler mis-measured: a one-line wait and a two-line wait
;              did not differ by exactly 76 cycles
;        $02-$04 = write cycle 74/75/76 took a different time than cycle 73
;              (a cycle-76 write must cost nothing extra — no spill)
;        $05-$08 = write cycle 77/78/79/80 not exactly 76 cycles beyond the
;              cycle-73 case (the overshot line must park to its end)
;
; Self-test: verdict in RESULT ($80); region-independent (a line is 76 CPU
; cycles in both regions).

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

S       = $90                   ; S..S+7: INTIM samples for write cycles 73..80
DIFF    = $98

; One measurement: align, arm the ruler, delay so the bare WSYNC's write
; lands on cycle {1}+9, sample the timer through whatever halt results.
; Bracket: lda(2)+sta TIM1T(4, absolute) = timer armed at cycle 6; SLEEP {1};
; write at cycle {1}+9; lda INTIM reads 4 cycles after execution resumes.
    MAC MEASURE
        sta WSYNC
        lda #220
        sta TIM1T
        SLEEP {1}
        sta WSYNC               ; the op under test
        lda INTIM
        sta S+{2}
    ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ; --- ruler: one line vs two lines differ by exactly 76 cycles
        sta WSYNC               ; align to a line start
        lda #220
        sta TIM1T               ; timer = 220, ticking once per CPU cycle
        sta WSYNC               ; wait one scanline
        lda INTIM
        sta DIFF                ; one-line reading (scratch)
        sta WSYNC               ; align again
        lda #220
        sta TIM1T               ; timer = 220 again
        sta WSYNC               ; wait...
        sta WSYNC               ; ...one more scanline
        lda INTIM               ; two-line reading
        sec                     ; carry in for the two's-complement subtract
        eor #$FF                ; A = 255 - two_line
        adc DIFF                ; A = one_line - two_line (the one extra line)
        sta DIFF
        ASSERT_EQ DIFF, 76, $01 ; assert that extra scanline is exactly 76 cycles

        ; --- the sweep: write cycles 73..80 (SLEEP 64..71)
        MEASURE 64, 0           ; write cycle 73: halts to line end
        MEASURE 65, 1           ; 74
        MEASURE 66, 2           ; 75
        MEASURE 67, 3           ; 76: the final cycle — absorbed, no spill
        MEASURE 68, 4           ; 77: cycle 1 of the overshot line — parks it
        MEASURE 69, 5           ; 78
        MEASURE 70, 6           ; 79
        MEASURE 71, 7           ; 80

        ldx #1                  ; S+1..S+3 must equal S+0 (same resume point)
.same:
        lda S+0
        sec
        sbc S,x
        sta DIFF
        txa
        clc
        adc #$01                ; codes $02..$04
        tay
        lda DIFF
        bne .fail0
        inx
        cpx #4
        bne .same

        ldx #4                  ; S+4..S+7 must be exactly 76 below S+0
.spill:
        lda S+0
        sec
        sbc S,x
        sta DIFF
        txa
        clc
        adc #$01                ; codes $05..$08
        tay
        lda DIFF
        cmp #76
        bne .fail76
        inx
        cpx #8
        bne .spill

        PASS_TEST

.fail0:
        lda DIFF
        ldx #$00
        jsr assert_eq           ; observed=DIFF expected=0, code in Y
.fail76:
        lda DIFF
        ldx #76
        jsr assert_eq           ; observed=DIFF expected=76, code in Y

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
