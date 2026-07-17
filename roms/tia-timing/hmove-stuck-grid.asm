; hmove-stuck-grid — the stuck-HMOVE pulse train is fixed to the scanline, not
; to the timing of the HMOVE write that started it.
;
; The TIA positions its five movable objects (two players, two missiles, one
; ball) by horizontal motion. Each object owns a 4-bit signed motion register
; (HMM0 for missile 0 here); writing the HMOVE strobe starts a sequence that
; injects extra "motion clock" pulses into every object's position counter,
; sliding it left. A 4-bit ripple counter counts down from 15. On a fixed
; sub-grid of the line, each still-moving object collects one extra pulse; the
; object's motion latch clears when the ripple reaches the value its HM
; register encodes. Normally the run delivers a bounded nudge and stops.
;
; A rewrite of the HM register mid-sequence, to a value whose clear point the
; ripple has already swept past, leaves that latch stuck (see
; hmove-stuck-latch). The TIA then keeps stuffing one extra pulse per 4 colour
; clocks on every later scanline — the Cosmic Ark starfield — until a release
; value ($80) is written. A stuck missile drifts 17 px left per line (the
; 68-clock horizontal blank holds 17 pulse slots). Where its single dot falls
; within the 4-clock pulse cycle — its residue, an offset of 0-3 — decides how
; the dot renders: residue 3 widens the dot to 2 px, residue 2 swallows it
; entirely, residues 0 and 1 draw it normally. The drift therefore carries a
; 4-line beat of widened / missing / normal / normal rows, and the beat's
; phase reveals where the pulse grid sits.
;
; This test jams the latch twice with the HMOVE write landing on a DIFFERENT
; CPU cycle — write cycle 4 in the top half, write cycle 5 in the bottom — and
; everything else identical. There are two candidate anchorings, established by
; the residue mapping above at the write-cycle-3 strobe where they coincide:
;
;   fixed to the write  — the pulses start a set delay after the HMOVE write, so
;                         the grid residue would slide 3 CLK per cycle of delay:
;                         the beat would land on different rows in each half
;                         (widened rows at residue 2 in the top half, residue 1
;                         in the bottom)
;   fixed to the line   — the pulses ride the horizontal counter's own two-phase
;                         clock, so the grid sits at the same residue always and
;                         both halves reproduce hmove-stuck-latch's beat exactly
;
; Both halves show the same beat: the grid is fixed to the line
; (hardware-measured: real PAL console, 2026-07-16). The jam-line displacements
; (-6 px at write cycle 4, -5 px at write cycle 5, against -7 px at write
; cycle 3 in hmove-stuck-latch) place the first stuffed pulse at the first
; fixed grid slot ~7-8 CLK after the HMOVE write ends. On release the frozen
; column sits 5 px left of the last drift position, as in hmove-stuck-latch.
; One frozen row shows per half — the top half's on its release row, the
; bottom half's at the top of the next frame.
;
; Verdict: the captured frame vs hmove-stuck-grid_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; black field
        lda #$0E
        sta COLUP0              ; white missile
        lda #$02
        sta ENAM0               ; missile 0 on, default width 1 CLK

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; ---------- top half: jam with HMOVE at write cycle 4 ----------
        sta WSYNC
        lda #$70
        sta HMM0                ; arm HMM0=$70 (+7 left)
        SLEEP 47
        sta RESM0               ; park at x=101

        sta WSYNC
        sta.w HMOVE             ; absolute mode -> HMOVE write on cycle 4
        lda #$00
        SLEEP 10
        sta HMM0                ; rewrite HMM0=$00 at cycle 19: latch stuck

        ldy #93                 ; 93 drift rows: the widen/miss/normal beat
.da:
        sta WSYNC
        dey
        bne .da

        sta WSYNC
        lda #$80
        sta HMM0                ; $80 rewrite: release the top-half latch

        ; ---------- bottom half: jam with HMOVE at write cycle 5 ----------
        sta WSYNC
        lda #$70
        sta HMM0                ; arm HMM0=$70 again
        SLEEP 47
        sta RESM0               ; re-park at x=101

        sta WSYNC
        nop
        sta HMOVE               ; nop + zp store -> HMOVE write on cycle 5
        lda #$00
        SLEEP 9
        sta HMM0                ; rewrite HMM0=$00 at cycle 19 again: stuck

        ldy #93
.db:
        sta WSYNC
        dey
        bne .db

        sta WSYNC
        lda #$80
        sta HMM0                ; $80 rewrite: release before the frame ends

        IFCONST FIELD_50HZ
        lda #$00
        sta ENAM0
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        lda #$02
        sta ENAM0
        ENDIF

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
