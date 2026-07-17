; calibration — a fixed geometry/photometry target for the hardware capture
; chain. Not a behaviour test: any correct implementation renders it
; identically, and the captured frame is compared against that render to fit
; the capture rig — its geometric transform, the per-row horizontal phase
; wobble, the point-spread function, and the luma/chroma transfer.
;
; Every visible line carries the same 4-on/12-off playfield stripes (period
; 16 TIA px), so the horizontal phase is measurable on EVERY row — the
; capture chain's line PLL settles over the first dozens of lines after
; vertical sync, and rows the phase map cannot see are exactly where
; sub-pixel measurements go wrong. The 25% duty cycle is deliberate: denser
; stripes (4-on/4-off everywhere) push the RF converter past its lock
; threshold, so the target carries the least edge energy that still
; phase-anchors every row. What varies per band is only the stripe colour,
; and a 1-px ball probe:
;
;   19 bands, top to bottom (2 gap lines at a fixed mid colour + a body;
;   12 lines per band on PAL/SECAM, 10 on NTSC):
;
;   band 0        ball probe band                  -- PSF probe
;   bands 1-8     stripes at luma 0,1,..,7 of the region's capture-safe
;                 green hue                        -- luma transfer
;   band 9        ball probe band                  -- PSF probe
;   bands 10-17   stripes at luma 4 of hues 0,2,..,E
;                 -- chroma-into-luma gain (band 10 is the grey reference)
;   band 18       ball probe band                  -- PSF probe
;
; A ball probe band shows the stripes like any other; the ball (1 px, bright)
; is enabled only on the middle body lines and sits inside a stripe GAP, so
; subtracting one of the band's stripes-only lines isolates the ball's
; point-spread on an empty background, phase-anchored by the same row's
; stripes. Ball x positions come from cycle-timed RESBL strobes and are read
; off the reference render, not predicted; they only need to be stable.
;
; Stripes rather than solid fields: a solid bright achromatic surface is pure
; DC luma and RF capture tuners drop lock on it (hardware-measured 2026-07-16),
; while striped content keeps edge energy in the signal on every row. On SECAM
; the hue-ramp bands all decode to the same green -- the geometry and luma
; measurements still stand.
;
; Verdict: the captured frame vs calibration_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"

CAL_HUE = COL_FIELD & $F0       ; the region's capture-safe green hue
GAP_COL = CAL_HUE | $06         ; gap-line stripe colour (mid luma)
NBANDS  = 19
        IFCONST FIELD_50HZ
BODY_LINES = 10                 ; 19 * (10+2) = 228 = VISIBLE_LINES
        ELSE
BODY_LINES = 8                  ; 19 * (8+2) = 190, +2 pad lines below
        ENDIF
PAD_LINES = VISIBLE_LINES - NBANDS * (BODY_LINES + 2)

kind    = $80                   ; current band: 0 stripes, 1/2/3 ball pos

        org $F000

Reset:
        CLEAN_START
        lda #$00
        sta CTRLPF              ; 1-clock ball, repeated (unreflected) playfield
        lda #$10                ; 4-on/12-off stripes, continuous across
        sta PF0                 ; PF0|PF1|PF2 and the repeated right half;
        lda #$88                ; the pattern never changes, only its colour
        sta PF1
        lda #$11
        sta PF2

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldy #0                  ; y = band index
.band:
        ; ---- gap line 1: gap colour + ball off ----
        lda #$00
        sta ENABL
        lda #GAP_COL
        sta COLUPF
        ldx BandKind,y
        stx kind
        lda BandColor,y
        sta WSYNC

        ; ---- gap line 2: ball bands strobe RESBL (a into COLUPF is
        ;      this band's colour, held for body line 1's hblank) ----
        ; a RES* strobe ending on CPU cycle c of the line lands the
        ; object at visible x = 3c - 64, so each path's SLEEP is chosen
        ; from its own dispatch cycles to put the ball MID-GAP (x%16=9-10):
        ; left 10+17+3=30 -> x=26, mid 9+34+3=46 -> x=74,
        ; right 11+53+3=67 -> x=137.  Re-derive if the dispatch changes!
        cpx #0
        beq .nostrobe
        cpx #2
        beq .mid
        bcs .right
        SLEEP 17
        sta RESBL               ; left third (x=26)
        jmp .nostrobe
.mid:
        SLEEP 34
        sta RESBL               ; centre (x=74)
        jmp .nostrobe
.right:
        SLEEP 53
        sta RESBL               ; right third (x=137)
.nostrobe:
        sta WSYNC               ; ---- body line 1 ----
        sta COLUPF

        ldx #BODY_LINES
.bl:
        sta WSYNC
        lda kind
        beq .cont               ; stripe band: nothing to toggle
        cpx #BODY_LINES-2
        bne .noton
        lda #$02
        sta ENABL               ; ball on after 3 stripes-only lines
        bne .cont               ; (a=2: always taken)
.noton:
        cpx #2
        bne .cont
        lda #$00
        sta ENABL               ; ball off for the last 2 lines
.cont:
        dex
        bne .bl
        iny
        cpy #NBANDS
        beq .bands_done         ; (.band is beyond branch range)
        jmp .band
.bands_done:

        ; tail: ball off, gap colour for any pad lines
        lda #$00
        sta ENABL
        lda #GAP_COL
        sta COLUPF
        IF PAD_LINES > 0
        ldx #PAD_LINES
.pad:
        sta WSYNC
        dex
        bne .pad
        ENDIF

        jsr overscan_lines
        jmp MainLoop

BandKind:
        .byte 1                                 ; ball, left
        .byte 0,0,0,0,0,0,0,0                   ; luma ramp
        .byte 2                                 ; ball, centre
        .byte 0,0,0,0,0,0,0,0                   ; hue ramp
        .byte 3                                 ; ball, right

BandColor:
        .byte CAL_HUE|$0E
        .byte CAL_HUE|$00,CAL_HUE|$02,CAL_HUE|$04,CAL_HUE|$06
        .byte CAL_HUE|$08,CAL_HUE|$0A,CAL_HUE|$0C,CAL_HUE|$0E
        .byte CAL_HUE|$0E
        .byte $08,$28,$48,$68,$88,$A8,$C8,$E8
        .byte CAL_HUE|$0E

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
