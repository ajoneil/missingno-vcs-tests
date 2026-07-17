; rsync — RSYNC resets the horizontal counter (playfield shifts, objects don't).
;
; Strobing RSYNC resets the TIA's main horizontal counter — the one that
; decodes the playfield — and does not reset the players'/missiles' own
; position counters. A mid-line RSYNC therefore slides the whole playfield
; sideways under a missile whose position is unchanged: a missile-vs-playfield
; collision (CXM0FB) that was absent can be created, while missile-vs-player
; collisions (both on independent counters) are untouched. That asymmetry is
; RSYNC's fingerprint.
;
; A 16px playfield block (PF0 = $FF) sits at the far left (right-half
; duplicate at px 80-95); a 1px missile parks at ~px121, in the black gap, so
; with no RSYNC it does not touch the playfield. RSYNC is then strobed
; mid-line, well before the beam reaches the missile: the counter restarts, a
; fresh copy of the left block re-decodes across the missile's column, and the
; collision latches.
;
;   CODE $01 = the parked missile collided the playfield though no RSYNC was strobed
;        $02 = the mid-line RSYNC did not slide the restarted playfield onto the missile
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SCRATCH = $90

; assert CXM0FB bit7 (missile0-playfield) set/clear
        MAC M0PF_IS
        lda CXM0FB
        and #$80
        sta SCRATCH
        ASSERT_EQ SCRATCH, {1}, {2}
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF              ; playfield white
        lda #$00
        sta COLUBK              ; background black
        sta CTRLPF              ; no reflect: right half duplicates the left
        sta NUSIZ0              ; missile 0 one pixel wide, player normal
        sta PF1                 ; middle playfield cells empty...
        sta PF2                 ; ...and right cells empty, so only PF0 draws
        lda #$FF
        sta PF0                 ; 16px block at px0-15 (dup px80-95); px96+ black
        lda #$02
        sta ENAM0               ; enable missile 0

        ; park M0 at ~px121, in the black gap on the right
        sta WSYNC               ; align to a line start (beam at colour clock 0)
        SLEEP 58                ; run out ~58 cycles into the line...
        sta RESM0               ; ...strobe RESM0 there -> missile lands ~px121

        ; --- baseline: no RSYNC, missile in the gap -> no playfield collision ---
        sta CXCLR               ; clear all collision latches
        jsr render_frame        ; one ordinary field
        M0PF_IS $00, $01        ; assert CXM0FB bit7 clear: missile missed the block

        ; --- RSYNC each line, mid-line, before the beam reaches the missile ---
        sta CXCLR               ; clear the latches again
        jsr render_rsync        ; one field with a mid-line RSYNC per line
        M0PF_IS $80, $02        ; assert CXM0FB bit7 set: restarted block hit it

        PASS_TEST

; normal field
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

; field with a mid-line RSYNC on every visible line (~colour clock 108 / px40),
; ahead of the missile at px121 so the restarted playfield decodes across it
render_rsync:
        jsr vertical_sync
        jsr vblank_lines
        ldx #VISIBLE_LINES
.rr:
        sta WSYNC               ; align to the line start
        SLEEP 33                ; run to ~colour clock 108 (px40)...
        sta RSYNC               ; ...and restart the horizontal counter there
        dex
        bne .rr
        jsr overscan_lines
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
