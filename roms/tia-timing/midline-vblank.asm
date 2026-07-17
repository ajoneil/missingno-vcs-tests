; midline-vblank — the video-output gate suppresses the picture in real time,
; taking effect at the colour clock the CPU flips it mid-scanline.
;
; The TIA (the Atari's video/sound chip) has a register, VBLANK, whose bit 1
; gates video output: while set, the pixel stream is forced to the blanking
; level (black) regardless of playfield, players, or background. The picture
; underneath is unchanged — only its output is suppressed, a different hardware
; path from a colour-register write or the player serializer. Because the gate
; is sampled per pixel, setting VBLANK partway across a visible line blanks the
; line from that beam position onward.
;
; The test draws sparse green playfield stripes (4px on a 16px period) and
; sweeps a 9px blanked notch across them: VBLANK bit 1 set at a beam
; position one step (6px) earlier each line, cleared three CPU cycles
; later. Where the notch crosses a stripe, those stripe pixels vanish;
; across the sweep the notch's two edges land at every position in the
; stripe cadence, so a gate that responds a colour clock early or late
; changes exactly which pixels survive on which row.
;
; Expected picture (x measured from the left edge, 0-159 across the visible
; width): green stripes at x 0-3, 16-19, ... , 144-147 on black, with a
; diagonal notch of missing stripe pixels marching leftward through the
; swept band and wrapping every 8 lines. Rows whose notch falls in a
; stripe gap are visually complete — that too is part of the expected
; picture, not a missed write. The overscan VBLANK-on write lands mid-line, so
; the last visible row's right end is blanked (its rightmost stripe absent) — a
; genuine truncation, not a dropped pixel.
;
; Verdict: the captured frame vs midline-vblank_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

LINECT  = $82                   ; $80/$81 are RESULT/CODE — scratch starts $82
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
STEPS   = 8                     ; longest line stays < 76 cyc

        org $F000

Reset:
        CLEAN_START

        lda #COL_FIELD
        sta COLUPF             ; green stripes: the content the gate blanks
        lda #$10
        sta PF0                ; the 4px / 16px stripe cadence: lit cells at
        lda #$88               ; x 0-3, 16-19, 32-35, 48-51, 64-67 and their
        sta PF1                ; right-half repeats (reflect off)
        lda #$11
        sta PF2

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0                 ; X = sweep index 0..STEPS-1
        ldy #$00               ; Y holds the gate-off value
        lda #VISIBLE_LINES
        sta LINECT
.visible:
        sta WSYNC
        sty VBLANK             ; output on from the left edge (write in HBLANK)
        ; VEC = Sled + X -> skip X nops, so the notch lands X*6px earlier
        txa
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        lda #$02               ; gate value, loaded before the sled so the
                               ; stores land back to back after it
        jmp (VEC)              ; jump X nops into the sled
Sled:
        REPEAT STEPS
        nop                    ; burn 2 cycles (6 px) per remaining nop
        REPEND
        sta VBLANK             ; gate ON at the swept beam position...
        sty VBLANK             ; ...and off again 3 cycles = 9px later
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
