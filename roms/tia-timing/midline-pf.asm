; midline-pf — writing a playfield register mid-scanline changes only the part
; of the picture not yet drawn, because the playfield is serialised as the beam
; sweeps.
;
; The TIA (Television Interface Adaptor, the VCS video-and-audio chip) has no
; frame buffer. The playfield — the coarse background pattern — is 20 on/off
; cells across the left half of a 160-pixel line, each cell 4 pixels wide. The
; cells are supplied by three registers: PF0 (its high nibble, 4 cells, pixels
; 0-15), PF1 (8 cells, pixels 16-47) and PF2 (8 cells, pixels 48-79). With
; CTRLPF's reflect bit clear the right half repeats the same 20 cells in the
; same order (copies at pixels 80-95 / 96-127 / 128-159); with it set the right
; half mirrors them. The chip serialises the cells in real time as the beam
; crosses them, re-reading the registers cell by cell — so storing a new value
; into a PF register while the beam is still inside that register's span changes
; only the cells not yet drawn.
;
; The test holds PF0 and PF1 on a sparse 4px stripe pattern for the whole
; frame and keeps PF2 clear, then at a beam position swept one step earlier
; each line writes PF2 $FF and, three CPU cycles (9px) later, $00 — a pulse
; whose BOTH edges probe the serialiser's cell-by-cell register re-read.
; The captured picture:
;
;   x 0-3, 16-19, 32-35    green    PF0/PF1 stripes, constant all frame
;   x 48-79                diagonal PF2's span: the cells the swept pulse
;                                   window reaches, marching left line by line
;   x 80-83, 96-99,
;     112-115              green    the right-half PF0/PF1 repeats (reflect off)
;   x 128-159              black    PF2's right-half copy — the pulse is
;                                   closed long before the beam gets here
;
; Which PF2 cells light at each sweep step pins the serialiser cadence
; against the CPU write on both the opening and closing edge; an
; implementation that latched the playfield once per line would draw the
; full span or nothing. The steps whose window falls left of the span
; light nothing — those blank lines are genuine, part of the wrap.
;
; The sweep runs one line into overscan by design, which truncates the last
; swept line: that content near the bottom of the reference image is genuine.
;
; Verdict: the captured frame vs midline-pf_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

LINECT  = $82                   ; $80/$81 reserved (RESULT/CODE)
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)
STEPS   = 8                     ; sweep positions; longest line stays < 76 cyc

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; black background
        lda #COL_FIELD
        sta COLUPF              ; green playfield on every standard (COL_FIELD,
                                ; region.h)
        lda #$00
        sta CTRLPF              ; no reflect: right half repeats the left

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        lda #$10
        sta PF0                 ; PF0/PF1 stay on the 4px stripe cadence all
        lda #$88
        sta PF1                 ; frame: lit at x 0-3, 16-19, 32-35 (+ repeats)
        ldx #0                  ; X = sweep index 0..STEPS-1
        ldy #$00                ; Y holds the pulse's closing $00
        lda #VISIBLE_LINES
        sta LINECT
.visible:
        sta WSYNC
        sty PF2                 ; PF2 clear from the left edge (write in HBLANK)
        txa                     ; VEC = Sled + X: skip X nops, so the stores
        clc                     ; land X steps (X*6 px) earlier than X=0
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        lda #$FF                ; pulse value, loaded before the sled so the
                                ; stores land back to back after it
        jmp (VEC)               ; jump X nops into the sled
Sled:
        REPEAT STEPS
        nop                     ; burn 2 cycles (6 px) per remaining nop
        REPEND
        sta PF2                 ; open the PF2 window at the swept position...
        sty PF2                 ; ...and close it 3 cycles = 9px later
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
