; hmove-stuck-stretch — under a stuck HMOVE pulse train a double-width player's
; pattern deforms on every fourth drift row; a quad-width player slides whole.
;
; A player serialises its 8-bit shape register (GRP0) left to right, one bit per
; pixel at normal size. The NUSIZ0 register's stretch modes clock that shape at
; half rate (double, 16 px total) or quarter rate (quad, 32 px), so each set bit
; paints a 2- or 4-pixel-wide cell. Under a stuck HMOVE latch (see
; hmove-stuck-latch) the TIA stuffs one extra motion pulse per 4 colour clocks
; across horizontal blank into the player's position counter on every line,
; drifting it 17 px left per line.
;
; The picture: an asymmetric pattern (GRP0=$B4, %10110100 — set pixels 0,2,3,5
; counting MSB-left, so any clipped or repeated cell shows) staircases left
; 17 px/line, wrapping — doubled on the top half of the frame, quadrupled on
; the bottom. Doubled, every fourth row deforms — the rows whose left edge
; lands one column right of a multiple of 4, a single residue of the 4-clock
; pulse grid (see hmove-stuck-grid): the first lit cell narrows to 1 px and the
; last widens to 3 px, growing one pixel leftward. The other three row types
; slide intact, and quadrupled every row slides intact (hardware-measured: real
; PAL console, 2026-07-16). The top visible row is the quad half's frozen
; release anchor left over from the previous frame. An implementation that
; moves the drifting player whole at both sizes draws the 23 deformed rows
; intact.
;
; Verdict: the captured frame vs hmove-stuck-stretch_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

HALF    = $80                   ; current half 0..1

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; black field
        lda #$0E
        sta COLUP0              ; white player
        lda #$B4
        sta GRP0                ; asymmetric pattern (MSB-left: px 0,2,3,5)

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0
.halfloop:
        stx HALF

        ; line 1: set the half's size and arm HMP0=$70 (timing-irrelevant)
        sta WSYNC
        lda NusizTab,x
        sta NUSIZ0
        lda #$70
        sta HMP0

        ; line 2: park P0 (write cycle 55) — the pattern spans x=[103..119)
        ; doubled / x=[103..135) quadrupled; the stretched draw-start sits +1 CLK
        ; from the 1x landing (see object-priority)
        sta WSYNC
        SLEEP 52
        sta RESP0               ; write cycle 55

        ; line 3: jam the latch — HMOVE at write cycle 3, HMP0=$00 at cycle 19
        sta WSYNC
        sta HMOVE               ; HMOVE write on cycle 3
        lda #$00
        SLEEP 11
        sta HMP0                ; rewrite HMP0=$00 at cycle 19: latch stuck

        ; lines 4..95: 92 rows of drifting stretched pattern
        ldy #92
.drift:
        sta WSYNC
        dey
        bne .drift

        ; line 96: release — $80's clear step is the ripple's resting state, so
        ; the halves stay independent; both sizes freeze 5 px left of the last
        ; drift position
        sta WSYNC
        lda #$80
        sta HMP0

        ldx HALF
        inx
        cpx #2
        bne .halfloop

        IFCONST FIELD_50HZ
        lda #$00
        sta GRP0
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        lda #$B4
        sta GRP0
        ENDIF

        jsr overscan_lines
        jmp MainLoop

NusizTab:
        .byte $05,$07           ; double (16px), quad (32px)

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
