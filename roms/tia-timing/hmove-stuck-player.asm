; hmove-stuck-player — a player drifting under a stuck HMOVE latch deforms on
; the lines where a stuffed motion clock lands inside its graphics scan.
;
; hmove-stuck-latch drifts a 1-clock-wide missile under a jammed "more movement"
; latch (a mid-sequence HMxx rewrite dodges its clear step, after which the TIA
; stuffs extra motion clocks into the object on every line with no further HMOVE
; — one per 4 colour clocks across horizontal blank, a steady 17 px/line leftward
; drift). This test drifts a PATTERNED player under the same jam. A player draws
; an 8-pixel bitmap from GRP0; here GRP0 = $B4 (%10110100), which is asymmetric
; — lit pixels sit at offsets 0, 2, 3, 5 from the player's left edge — so any
; skipped or repeated graphics-scan step shows up as a deformed shape.
;
; A stuffed clock that lands while the player's serialiser is walking its 8 bits
; deforms the drawn shape rather than moving the object whole (hardware-measured:
; real PAL console, 2026-07-16). 17 is one more than a multiple of 4, so the
; pattern's alignment against the 4-clock pulse grid repeats every 4 lines: three
; drift lines draw $B4 intact, then one draws a solid 4-pixel block over offsets
; 2..5 of where the pattern's left edge would sit.
;
; The picture: the parked pattern staircases left 17 px/line, wrapping (the one
; deformed row whose block straddles the wrap seam draws on both sides of it,
; columns 0-3 and 158), and an $80 rewrite frees the latch after the last drift
; line, leaving a frozen anchor at the top of the frame — so every frame is
; identical. An implementation that slides the player whole draws the intact
; pattern on every drift line.
;
; Verdict: the captured frame vs hmove-stuck-player_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background: black field
        lda #$0E
        sta COLUP0              ; player 0: white
        lda #$B4
        sta GRP0                ; bitmap %10110100 (MSB-left: lit at px 0,2,3,5)

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; line 1: park P0 spanning x=102..109 and arm the motion register HMP0=$70
        sta WSYNC
        lda #$70
        sta HMP0
        SLEEP 47
        sta RESP0               ; strobe at write cycle 55 -> P0 left edge at x=102
                                ; (lit pixels land at 102, 104, 105, 107)

        ; line 2: jam the latch — HMOVE at write cycle 3, HMP0=$00 at cycle 19
        sta WSYNC
        sta HMOVE               ; write cycle 3: start the ripple sequence
        lda #$00
        SLEEP 11
        sta HMP0                ; write cycle 19: clear step long past -> stuck

        ; lines 3..191: the drifting pattern, 17 px/line left, wrapping
        ldy #189
.drift:
        sta WSYNC
        dey
        bne .drift

        ; line 192: $80 frees the latch (its clear step is the resting state),
        ; freezing the anchor a few colour clocks left of the last drift position
        sta WSYNC
        lda #$80
        sta HMP0

        IFCONST FIELD_50HZ             ; 50 Hz fields have more visible lines: blank the extra
        lda #$00                ; ones so the picture keeps its NTSC shape
        sta GRP0                ; clear the bitmap during the padding lines
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        lda #$B4
        sta GRP0                ; restore the bitmap for the next field
        ENDIF

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
