; object-priority — when TIA objects overlap, the default front-to-back draw
; order is player 0 / missile 0, then player 1 / missile 1, then playfield /
; ball, then the background.
;
; The TIA draws five movable objects — two players, two missiles, one ball —
; over a playfield pattern and a background colour. Where two of them cover the
; same pixel, a fixed priority ladder picks which colour reaches the screen:
; player 0 / missile 0 in front, then player 1 / missile 1, then the playfield /
; ball, then the background. The ladder is purely a drawing rule — it never
; affects collision detection, which latches the overlap regardless of who is
; drawn on top — so the ordering shows up only as colour, and this is a
; screenshot test. (Setting bit 2 of the CTRLPF control register instead lifts
; the playfield and ball to the front of everything — that flip is the
; pf-priority test.)
;
; The playfield draws 4px green stripes on a 16px period. The two players
; are quad-width (32px footprint) with GRP $88 — two 4px lit segments
; 16px apart — so the quad stretch itself is asserted while every lit
; span stays 4px. The players land so the segments cross a stripe and
; each other; every rung of the ladder is on screen. Every visible line
; shows:
;
;   x   0-  3  green   playfield stripe alone (also 16-19, 32-35)
;   x  46- 47  red     player 0 over the background
;   x  48- 49  red     player 0 over a playfield stripe — front of the ladder
;   x  50- 51  green   the rest of that stripe, past player 0's segment
;   x  61      blue    player 1 over the background
;   x  62- 63  red     player 0 over player 1
;   x  64      red     player 0 over player 1 over a stripe — the full stack
;   x  65      red     player 0 over that stripe (player 1 ends at 64)
;   x  66- 67  green   the rest of that stripe
;   x  77- 79  blue    player 1 over the background
;   x  80      blue    player 1 over a playfield stripe
;   x  81- 83  green   the rest of that stripe
;   x  96- 99  green   playfield stripes alone again (also 112-115, 128-131,
;                      144-147); black background everywhere else
;
; A different ladder recolours specific bands: if player 1 won the overlap,
; 62-64 would turn blue; if the playfield came forward, 48-49 / 64-65 / 80
; would stay green under the players. The four surfaces stay mutually
; distinct on every standard: by hue on NTSC/PAL (green / red-orange /
; blue), and on SECAM — which decodes only the luminance bits — by sitting
; on four distinct luma steps (playfield 4, player 0 3, player 1 1,
; background 0).
;
; The band edges also pin object positioning: a stretched (double- or quad-
; width) player begins drawing one colour clock later than a 1x player would
; from the same reset. That extra clock is why player 0's first pixel is x=46
; rather than x=45.
;
; Verdict: the captured frame vs object-priority_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"

        org $F000

Reset:
        CLEAN_START

        lda #COL_FIELD
        sta COLUPF              ; playfield green (luma 4 on every standard)
        lda #$46
        sta COLUP0              ; player 0 red (NTSC) / orange (PAL), SECAM luma 3
        lda #$92
        sta COLUP1              ; player 1 blue, SECAM luma 1
        lda #$07
        sta NUSIZ0              ; player 0 quad width: 8 bits x 4px = 32px
        sta NUSIZ1              ; player 1 quad width, same
        lda #$88
        sta GRP0                ; bits 7,3: two 4px segments 16px apart
        sta GRP1                ; when quad-stretched
        ; playfield stripes, 4px on a 16px period: one bit set per PF nibble
        ; group so a stripe opens each 16-px cell (the right half repeats the
        ; left with REF clear), landing at x = 0, 16, 32, ... , 144
        lda #$10
        sta PF0                 ; bit 4 -> x 0-3
        lda #$88
        sta PF1                 ; bits 7,3 -> x 16-19, 32-35
        lda #$11
        sta PF2                 ; bits 0,4 -> x 48-51, 64-67

        ; two quad players strobed 5 CPU cycles apart so they overlap:
        ; player 0 lands first, player 1 lands 15 colour clocks to its right
        sta WSYNC               ; align to a fresh scanline
        SLEEP 33                ; wait into the visible line...
        sta RESP0               ; reset P0 -> lit segments x 46-49, 62-65
        sta WSYNC               ; next scanline
        SLEEP 38                ; ...5 cycles = 15 colour clocks later
        sta RESP1               ; reset P1 -> lit segments x 61-64, 77-80

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #VISIBLE_LINES
.visible:
        sta WSYNC
        dex
        bne .visible

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
