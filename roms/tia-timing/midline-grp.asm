; midline-grp — rewriting GRP0 while the beam is inside the player changes the
; player's remaining pixels, because the sprite is serialised from the register
; live, not latched at its left edge.
;
; The TIA (Television Interface Adaptor, the VCS video-and-audio chip) draws
; player 0 from GRP0, an 8-bit graphics register. As the beam crosses the player
; the chip clocks those 8 bits out one at a time (each bit 1, 2 or 4 pixels wide
; per the size field of NUSIZ0); it reads GRP0 live at each step rather than
; latching it when the player begins. So a store to GRP0 mid-player replaces
; every bit not yet drawn with the new value, in real time. This is the register
; path games use to reuse one player object as several sprites on a line. It is
; deliberately separate from the buffered path — VDELP0, which swaps in a
; previously written copy of the graphics at the start of a line — that exists
; to avoid tearing a single object across a mid-object write.
;
; A quad-width player (NUSIZ0 = $07: each GRP0 bit 4 pixels, 32 pixels total) is
; positioned with a RESP0 strobe so its bar begins at pixel 28. Every line loads
; GRP0 = $FF solid during horizontal blank, then stores GRP0 = $00 at a beam
; position that moves one step earlier each line:
;
;   x 0-27     black    left of the player
;   x 28..cut  white    the player, up to the swept white|black cut
;   cut..59    black    the rest of the bar, blanked by the mid-draw GRP0 = $00
;
; The cut marches leftward through the 28-59 bar and the reference image is that
; diagonal. Every column of the bar is probed, so a serialiser that samples GRP0
; a pixel early or late, or on the wrong clock, kinks the diagonal; one that
; latched GRP0 at the player's left edge would ignore the second store and draw
; a solid bar.
;
; Verdict: the captured frame vs midline-grp_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

LINECT  = $82                   ; $80/$81 are RESULT/CODE — scratch starts $82
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
STEPS   = 6                     ; sweep steps ~= the 32px quad player's width

        org $F000

Reset:
        CLEAN_START

        lda #$0E
        sta COLUP0             ; player white; white on black keeps the cut legible
        lda #$00
        sta COLUBK
        lda #$07
        sta NUSIZ0             ; quad player: 32px bar, each GRP0 bit = 4px

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; fix the player's column once on this setup line, which draws blank
        ; (GRP0 is still 0) and so counts as the first of the visible lines
        sta WSYNC
        SLEEP 27                ; strobe lands the bar's left edge at pixel 28
        sta RESP0

        ldx #0                 ; X = sweep index 0..STEPS-1
        lda #VISIBLE_LINES-1    ; the RESP0 line above is the other visible line
        sta LINECT
.visible:
        sta WSYNC
        lda #$FF
        sta GRP0               ; whole bar solid (write in HBLANK, before the draw)
        ; VEC = Sled + X -> skip X nops, so the cut store lands X*6px earlier
        txa
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)              ; jump X nops into the sled
Sled:
        REPEAT STEPS
        nop                    ; burn 2 cycles (6 px) per remaining nop
        REPEND
        lda #$00
        sta GRP0               ; blank the rest of the bar at the swept beam column
        inx
        cpx #STEPS
        bcc .nowrap
        ldx #0                 ; wrap -> a repeating diagonal
.nowrap:
        dec LINECT
        bne .visible

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
