; midline-color — a write to a colour register takes effect at the colour
; clock the CPU performs it, so it recolours a scanline from that point on.
;
; The TIA (the Atari's video/sound chip) has no framebuffer: it generates each
; pixel live as the beam sweeps, reading the colour registers at that instant.
; A store to COLUBK (the background-colour register) partway across a visible
; line therefore changes the colour from the beam position of the store onward,
; splitting the line into two colours at that exact column. The CPU and the
; beam run locked together — one CPU cycle per three colour clocks — so the
; split column is fixed by which CPU cycle does the store.
;
; The test keeps the background black and, at a column swept 6 pixels
; earlier every line, stores green (COL_FIELD) and then black again three
; CPU cycles later — a 9px green background pulse whose BOTH edges are
; mid-line write timings. The pulse walks leftward line by line, so the
; picture is a repeating diagonal green ribbon on black, and every column
; in the swept band is probed: a write that lands a colour clock early or
; late kinks the ribbon's straight edges.
;
; Expected picture (x measured from the left edge, 0-159 across the visible
; width):
;   first swept line   green pulse at x 91-99          rightmost sweep stop
;   each line below    pulse 6px further left          one sweep step
;   12th swept line    pulse at x 25-33                leftmost sweep stop
;   next line          pulse back at x 91-99           the sweep wraps
; The 12-line period tiles down the whole frame. A broken mid-line write
; bends one or both edges of the otherwise-straight diagonal ribbon.
;
; The sweep runs into overscan by design, which truncates the final swept line
; partway: that content in the reference image is genuine, not an artifact.
;
; Verdict: the captured frame vs midline-color_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

LINECT  = $82                   ; $80/$81 are RESULT/CODE — scratch starts $82
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
STEPS   = 12                    ; sweep positions; longest line = 50 + 2*STEPS = 74
                                ; cyc (incl. the closing WSYNC) — must stay < 76 or
                                ; a line overruns and eats the next scanline

        org $F000

Reset:
        CLEAN_START

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0                  ; X = sweep index 0..STEPS-1
        ldy #$00                ; Y holds black for the pulse's closing edge
        lda #VISIBLE_LINES
        sta LINECT
.visible:
        sta WSYNC
        sty COLUBK              ; black from the left edge (write in HBLANK)
        ; Variable delay without self-modifying code (the 2600 runs its program
        ; from ROM, which cannot rewrite itself): a RAM pointer indexes a
        ; `jmp (VEC)` into a sled of NOPs in ROM. VEC = Sled + X, so line X
        ; jumps X nops in and executes that many fewer of them. The WSYNC above
        ; resynchronises every line, so only the store's column moves.
        txa
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        lda #COL_FIELD          ; pulse colour, loaded before the sled so the
                                ; stores land back to back after it
        jmp (VEC)               ; jump X nops into the sled
Sled:
        REPEAT STEPS
        nop                     ; burn 2 cycles (6 px) per remaining nop
        REPEND
        sta COLUBK              ; green at the swept beam position...
        sty COLUBK              ; ...and black 3 cycles = 9px later
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
