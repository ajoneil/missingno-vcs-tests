; hmove-stuck-straddle — a motion nudge that merges into a player about to
; draw, at the line's LAST nudge slot, is taken or refused by the player's
; pattern scan exactly as at any mid-line slot; the rows here walk the
; scan's start across that slot one clock at a time.
;
; The TIA (the console's video chip) draws each scanline live, one pixel per
; "colour clock". Writing HMOVE nudges the movable objects sideways during a
; short burst after the write; a mid-burst rewrite of HMP0 dodges the
; burst's stop step and jams its "more movement" latch (the mechanism:
; hmove-stuck-latch). From then on, with no further HMOVE, the TIA nudges
; the player once every fourth colour clock, on a grid fixed to the line.
;
; Where a nudge lands decides what it does. In horizontal blank the player's
; own pixel clock is stopped, so each nudge is a real push — the seventeen
; blank-time nudges per line add up to a steady 17 px/line leftward drift.
; In the visible span a nudge coincides with a tick of the player's own
; pixel clock, and the two merge into one stretched pulse carrying TWO
; advances. Whether the second advance reaches the player's pattern scan
; follows the scan's own state (real PAL console, 2026-07-28 capture, and
; the same rule on the collision latches: collision/merge-delivery): a scan
; still delivering its FIRST pattern bit takes it at any phase — the
; pattern lands a clock early and its first bit shows twice; a scan ONE
; step from showing that bit consumes it — the bit is never skipped, so
; the pattern draws as if plainly ticked; a mid-shape scan takes it only
; at the one phase its own stepping derives from.
;
; The line's last nudge slot, colour clock 225, sits at the wrap seam —
; one stepped pixel after it, the player's clock stops until the next
; line. The drift brings the player's start to that slot again and again,
; one clock earlier per visit, so single rows realise start-to-slot gaps
; of 1, 2 and 3 clocks — the three first-bit states above, pinned against
; the seam where any special line-end behaviour would show. None does:
; the mid-line rule reproduces the captured frame row for row.
;
; ROW MAP (PAL reference rows, counted from the field top; NTSC rows are 8
; less; the seam-visit series steps the left edge +1 column per 47 rows;
; lit sets include the wrap remnants that land on the row below):
;   row  81  delivery 3 before the slot  {0,2,157,158,159}  first bit out
;            at 157: the merge advances — third bit at 158 and again at 159
;   row 128  delivery 2 before the slot  {0,1,2,3,158}  one step short:
;            the merge is consumed — first bit at 158, nothing follows
;   row 175  delivery 1 before the slot  {1,2,4,158,159}  both advances
;            land in the delivery lead: first bit at 158 AND 159
;   row 241  = row 81's cell again (50 Hz fields only)
;
; Verdict: the captured frame vs hmove-stuck-straddle_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; VISIBLE_LINES: the drift spans the region's field

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background: black field
        lda #$0E
        sta COLUP0              ; player 0: white, maximum luminance contrast
        lda #$B4
        sta GRP0                ; bitmap %10110100 (MSB-left: lit at px 0,2,3,5)
        ; $B4 makes every seam verdict a lit/dark flip — the pattern must
        ; open %101: a consumed merge shows the lit first bit against the
        ; dark second (rows 128/175), an advancing one the lit third bit
        ; where the dark second would have been (rows 81/241); equal
        ; neighbouring bits would draw taken and refused alike. It is also
        ; the pattern every console measurement of this seam used, so these
        ; rows read against those measurements row-for-row.

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; line 1: park P0 spanning x=102..109 and arm the motion register
        ; HMP0=$70 (park and drift identical to hmove-stuck-player, keeping
        ; this ROM's rows aligned with the 2026-07-16 console measurements)
        sta WSYNC
        lda #$70
        sta HMP0
        SLEEP 47
        sta RESP0               ; strobe at write cycle 55 -> P0 left edge at x=102

        ; line 2: jam the latch — HMOVE at write cycle 3, HMP0=$00 at cycle 19
        sta WSYNC
        sta HMOVE               ; write cycle 3: start the ripple sequence
        lda #$00
        SLEEP 11
        sta HMP0                ; write cycle 19: clear step long past -> stuck

        ; the drifting pattern, 17 px/line left, wrapping, to the field's end:
        ; unlike hmove-stuck-player there is no NTSC-shape padding — the walk
        ; repeats its cells after 160 rows, so a 50 Hz field's extra lines
        ; show the open-edge cell a second time (row 241 = row 81)
        ldy #(VISIBLE_LINES-3)
.drift:
        sta WSYNC
        dey
        bne .drift

        ; last line: $80 frees the latch (its clear step is the resting state);
        ; the next frame's RESP0 re-park makes every frame identical
        sta WSYNC
        lda #$80
        sta HMP0

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
