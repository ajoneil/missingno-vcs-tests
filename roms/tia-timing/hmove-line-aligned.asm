; hmove-line-aligned — HMOVE applies the same motion on whichever line boundary
; it is strobed.
;
; HMOVE is the object-motion strobe of the TIA (the chip that generates the video):
; fired immediately after a scanline starts, it shifts each movable object by
; the amount in its motion register (HMM0/HMM1 for the two missiles here). A
; scanline is a fixed 76 CPU cycles and every line begins identically, so a
; strobe issued one line later — or N lines later, N*76 cycles — sits at exactly
; the same phase within its own line and must produce exactly the same shift.
; HMOVE is line-aligned: only the offset from the line start matters, not which
; line. (This test uses only WSYNC-aligned strobes; the mis-timed mid-line case
; is covered by hmove-late.)
;
; The test reads its answer from the missile-missile collision latch: CXPPMM
; bit 6 reads 1 once missile 0 and missile 1 have overlapped anywhere in the
; frame, and stays set until CXCLR clears it. Two 1-pixel missiles strobed to
; the same column overlap and collide. Giving M0 a +7 move (HMM0=$70) with one
; HMOVE pulls it off M1 and the collision stops. Giving M1 the same +7 with an
; HMOVE strobed on a later line must move it the identical distance and land it
; back on M0, restoring the collision; a phase-dependent HMOVE would leave the
; two moves unequal and the missiles apart.
;
;   CODE $01 = co-located baseline did not collide
;        $02 = after moving M0 +7, still colliding (M0 didn't move)
;        $03 = after moving M1 +7 on a later line, not colliding (motion not
;              equivalent across line boundaries)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SCRATCH = $90

; assert M0-M1 collision (CXPPMM bit6) set/clear
        MAC M0M1_IS
        lda CXPPMM
        and #$40
        sta SCRATCH
        ASSERT_EQ SCRATCH, {1}, {2}
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$42
        sta COLUP0
        lda #$C4
        sta COLUP1
        lda #$02
        sta ENAM0
        sta ENAM1              ; M0, M1 width 1

        ; co-locate M0 and M1 (same strobe delay)
        sta WSYNC
        SLEEP 35
        sta RESM0
        sta WSYNC
        SLEEP 35
        sta RESM1

        ; --- baseline: co-located -> collide ---
        lda #$00
        sta HMM0
        sta HMM1
        sta CXCLR
        jsr render_frame
        M0M1_IS $40, $01

        ; --- move M0 +7 (one WSYNC-aligned HMOVE); M1 stays ---
        lda #$70
        sta HMM0
        lda #$00
        sta HMM1
        sta WSYNC
        sta HMOVE
        sta CXCLR
        jsr render_frame
        M0M1_IS $00, $02

        ; --- move M1 +7 on a LATER line; M0 stays. If line-aligned HMOVE is
        ;     phase-independent, M1 moves the same +7 and re-meets M0 ---
        lda #$00
        sta HMM0
        lda #$70
        sta HMM1
        sta WSYNC               ; extra aligned lines before the strobe (N*76)
        sta WSYNC
        sta WSYNC
        sta HMOVE
        sta CXCLR
        jsr render_frame
        M0M1_IS $40, $03

        PASS_TEST

render_frame:
        jsr vertical_sync
        jsr vblank_lines
        ldx #VISIBLE_LINES
.rf:
        sta WSYNC
        dex
        bne .rf
        jsr overscan_lines
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
