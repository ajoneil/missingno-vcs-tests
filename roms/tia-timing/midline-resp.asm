; midline-resp — where in a scanline you strobe RESP0 sets player 0's
; horizontal position, so sweeping the strobe walks the player across the
; screen.
;
; The TIA (Television Interface Adaptor, the VCS video-and-audio chip) has no
; position register for its movable objects. Player 0's horizontal location is
; held by a free-running counter that advances with the beam; strobing RESP0
; (any write — the value is ignored) resets that counter, which fixes where the
; player is drawn from then on. The player is redrawn at the latched position on
; every following line until the counter is reset again, so a RESP0 strobe on
; one line first shows up as a drawn pixel on the NEXT line, ahead of that line's
; own strobe.
;
; The test draws a 1-pixel player (GRP0 = $80, one lit graphics bit; NUSIZ0 =
; $00, one copy at normal width) in white on black, and moves the RESP0 strobe
; one step LATER — further right — each line. Because each new strobe lands to
; the right of the position the previous strobe latched, the previous position
; is drawn first, early in the line, before the new strobe repositions for the
; line after; the single pixel therefore marches rightward as a clean diagonal.
; In the reference image the lit column steps from pixel 39 to pixel 99 in
; 6-pixel increments, then wraps; a lone startup pixel at x=105 (the twelfth
; step) sits on the first visible row before the wrap strobe pre-empts it.
; Every landing column is probed, so any error in RESP0's reset latency kinks
; the diagonal.
;
; Verdict: the captured frame vs midline-resp_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

LINECT  = $82                   ; $80/$81 reserved (RESULT/CODE)
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
STEPS   = 12                    ; sweep positions; longest line stays < 76 cyc

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; black background
        lda #$0E
        sta COLUP0              ; white player (bright on both palettes)
        lda #$80
        sta GRP0                ; 1-pixel player (leftmost bit)
        lda #$00
        sta NUSIZ0              ; one copy, normal width

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0                  ; X = sweep index 0..STEPS-1
        lda #VISIBLE_LINES
        sta LINECT
.visible:
        sta WSYNC
        stx VEC                 ; VEC = Sled + (STEPS-1-X): more nops as X grows,
        lda #(STEPS-1)          ; so the strobe sweeps LATER (rightward) each line.
                                ; Sweeping left instead would let each strobe move
                                ; the player before its own pixel was drawn
        sec
        sbc VEC
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)
Sled:
        REPEAT STEPS
        nop                     ; burn 2 cycles (6 px) per remaining nop
        REPEND
        sta RESP0               ; strobe at the swept beam position (value ignored)
        inx
        cpx #STEPS
        bcc .nowrap
        ldx #0                  ; wrap the sweep -> a repeating diagonal
.nowrap:
        dec LINECT
        bne .visible

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
