; nusiz-draw — a NUSIZ0 write finished during horizontal blank resizes player 0
; on that same line.
;
; NUSIZ0 controls player 0's size and copy layout: it selects among one, two, or
; three copies of the sprite, at close/medium/wide spacings, plus double- and
; quad-width single copies — eight layouts in all. The TIA redraws the player
; from scratch every scanline, reading the current NUSIZ0 setting as the beam
; lays that line down. A write that completes during horizontal blank — the
; off-screen span at the start of each scanline, before the visible 160 pixels —
; therefore lands before the player is drawn, so the new size takes effect on
; the very line the write opens. The cycle at which the size latches, relative to
; the start of the visible line, is what decides which line a new layout first
; appears on: because the write lands early in horizontal blank with slack to
; spare, only a latch pushed clear across the HBLANK/visible boundary moves a
; band by a whole line.
;
; A single solid player (GRP0 = $FF, so every copy is a filled rectangle) is
; positioned once with a RESP0 strobe in horizontal blank — its base copy lands
; at x=3 — then NUSIZ0 steps through all eight layouts down the screen. The
; visible field is split into eight equal bands of 24 lines, and each band's new
; size is written in that band's first horizontal blank. The reference image is a
; staircase of white blocks on black, one band per layout:
;
;   band 0  layout 0  one copy            x=3-10
;   band 1  layout 1  two copies close    x=3-10, 19-26
;   band 2  layout 2  two copies medium   x=3-10, 35-42
;   band 3  layout 3  three copies close  x=3-10, 19-26, 35-42
;   band 4  layout 4  two copies wide     x=3-10, 67-74
;   band 5  layout 5  double width 16px   x=4-19
;   band 6  layout 6  three copies medium x=3-10, 35-42, 67-74
;   band 7  layout 7  quad width 32px     x=4-35
;
; (The double- and quad-width copies begin drawing one colour clock later than a
; normal-width copy, so bands 5 and 7 start at x=4 rather than x=3.) The seven
; band boundaries carry the test: each is a clean horizontal edge where one
; layout gives way to the next, and a boundary one line early or late means the
; size latch was mistimed. (A 50 Hz field is taller than 192 lines, so band 7's
; quad runs on to the bottom of the picture.)
;
; Verdict: the captured frame vs nusiz-draw_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = 192/8                 ; 24 visible lines per NUSIZ layout (8*24 = 192)

        org $F000

Reset:
        CLEAN_START

        lda #$0E
        sta COLUP0              ; player white
        lda #$FF
        sta GRP0                ; solid 8-bit block, so a copy is a filled rectangle
        lda #$00
        sta COLUBK              ; background black

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; --- band 0: layout 0, and fix P0's column once (in HBLANK) ---
        sta WSYNC               ; band 0's first line
        lda #$00
        sta NUSIZ0              ; layout 0: one copy
        SLEEP 13
        sta RESP0               ; base column x=3; leaves room for the quad/3-copy modes
        ldy #BAND-1
.b0:
        sta WSYNC               ; hold layout 0 for the rest of the band
        dey
        bne .b0

        ; --- bands 1..7: step NUSIZ0, one write per band, in the first HBLANK ---
        ldx #1
.bandloop:
        sta WSYNC               ; band X's first line
        stx NUSIZ0              ; latch layout X in HBLANK — the timing under test
        ldy #BAND-1
.bl:
        sta WSYNC               ; hold this layout for the rest of the band
        dey
        bne .bl
        inx
        cpx #8
        bne .bandloop

        ; 50 Hz fields run past 192 lines: these extra scanlines keep the beam on
        ; (VBLANK still cleared), so band 7's quad simply draws on to the bottom
        IFCONST FIELD_50HZ
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        ENDIF

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
