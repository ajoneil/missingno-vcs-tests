; colors — a TIA colour byte encodes hue in its high nibble and luminance in
; bits 3..1, with bit 0 unused, giving 128 distinct colours.
;
; Every TIA colour register — COLUP0 and COLUP1 for the two players, COLUPF for
; the playfield, COLUBK for the background — holds one 8-bit colour byte laid
; out HHHH LLL0: bits 7..4 select one of 16 hues and bits 3..1 select one of 8
; luminance steps. Bit 0 is not wired to the colour decode, so an odd byte
; paints exactly the same colour as the even byte one below it: 16 hues x 8 luma
; steps = 128 distinct colours, reached by the 128 even codes. The console has
; no framebuffer — the beam paints whatever colour the relevant register holds
; as it passes each pixel — so writing COLUBK once and letting a whole scanline
; draw fills that line with one flat colour.
;
; The test writes COLUBK = 0, 2, 4, ... 254 down the first 128 visible lines,
; one colour per line, then holds black for the rest of the frame:
;
;   lines 0-127   the 128-colour palette ramp: line n is colour code 2n, so the
;                 hue changes every 8 lines and the luminance climbs 0..7 within
;                 each hue block; code 0 on line 0 is black (indistinguishable
;                 from the blanking above it)
;   below         flat black to the bottom of the frame
;                 (64 lines on NTSC, 100 on PAL)
;
; A wrong code->colour mapping, a mis-stepped luma ramp, or a decode that fails
; to ignore bit 0 shows up as banding or duplicated/misordered stripes.
;
; Verdict: the captured frame vs colors_<region>.png. (Each pixel is a TIA
; colour code rendered through the region's canonical palette.)

        processor 6502
        include "vcs.h"
        include "macro.h"

        org $F000

Reset:
        CLEAN_START

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; top 128 visible lines: COLUBK = 0,2,4,...,254 (every TIA colour once)
        ldx #$00                ; x = first colour code, 0
        ldy #128                ; y = lines of ramp left to draw
.ramp:
        stx COLUBK              ; paint this line in colour code x
        sta WSYNC               ; hold the colour to the line's end
        inx
        inx                     ; next even code (skip the unused bit-0 twin)
        dey
        bne .ramp

        ; remaining visible lines: black (64 on NTSC, 100 on PAL)
        lda #$00
        sta COLUBK              ; background back to black
        ldx #VISIBLE_LINES-128
.rest:
        sta WSYNC
        dex
        bne .rest

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
