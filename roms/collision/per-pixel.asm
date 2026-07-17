; per-pixel — the TIA reports a collision only where two objects' LIT pixels
; share a column, and the latch stays set until it is explicitly cleared.
;
; The TIA (Television Interface Adaptor) draws five movable objects — two
; players (P0/P1), two missiles (M0/M1) and one ball (BL) — one colour clock
; at a time as the beam sweeps a scanline. At each clock it knows which of
; those objects is emitting a lit pixel in that column, and for every pair
; that are both lit it sets that pair's collision bit. Detection is therefore
; per drawn pixel, not per bounding box: two objects can occupy the same
; horizontal span yet never collide if their lit pixels never fall on the same
; column. The fifteen object pairs are read back as bits D7/D6 of the read-only
; collision registers CXM0P..CXPPMM. Those bits are OR-accumulated as the frame
; draws and are cleared only by a write to the CXCLR strobe (a strobe is a
; write whose value is ignored), so a collision seen once stays reported after
; the objects have moved apart.
;
; The test places two players at the same column, both quad width, and chooses
; their two graphics bytes (GRP0/GRP1) to decide which pixels each one lights.
; CXPPMM bit 7 is the P0-P1 latch, sampled after rendering a full frame:
;
;   $F0 vs $0F   P0 lights the left 16px, P1 the right 16px: same span but
;                disjoint pixels -> no collision
;   $F0 vs $F0   both light the left 16px: coincident pixels -> collision
;   separate P0  move P0 away without clearing: the latch persists (sticky)
;   CXCLR        clears every latch
;   $AA vs $55   alternating pixels never share a column -> no collision even
;                with full-span overlap; $AA vs $AA shares every lit column
;                -> collision
;
; (Exact overlap boundaries need 1px positioning — hmove-edge's job.) A
; bounding-box implementation collides on the disjoint cases; a non-sticky one
; drops the latch the moment the players separate.
;
;   CODE $01 = disjoint pixels falsely collided
;        $02 = coincident pixels did not collide
;        $03 = collision not sticky after objects separated
;        $04 = CXCLR did not clear
;        $05 = interleaved ($AA/$55) pixels falsely collided
;        $06 = coincident ($AA/$AA) interleaved pixels did not collide
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SCRATCH = $90

; assert CXPPMM bit7 (P0-P1) set/clear
        MAC P0P1_IS
        lda CXPPMM
        and #$80
        sta SCRATCH
        ASSERT_EQ SCRATCH, {1}, {2}
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$42
        sta COLUP0              ; P0 colour (cosmetic; collision ignores it)
        lda #$C4
        sta COLUP1              ; P1 colour
        lda #$07
        sta NUSIZ0              ; P0 quad (each GRP bit = 4px -> 32px sprite)
        sta NUSIZ1              ; P1 quad

        ; co-locate P0 and P1: identical strobe delay -> identical column
        sta WSYNC               ; start of a fresh scanline
        SLEEP 31
        sta RESP0               ; P0 position = this beam column
        sta WSYNC
        SLEEP 31
        sta RESP1               ; P1 position = the same column

        ; --- (a) disjoint lit pixels: left half vs right half ---
        lda #$F0
        sta GRP0                ; P0 lights the left 16px  (bits 7..4)
        lda #$0F
        sta GRP1                ; P1 lights the right 16px (bits 3..0)
        sta CXCLR               ; clear latches, then draw a frame
        jsr render_frame
        P0P1_IS $00, $01        ; expect no P0-P1 collision (pixels never share a column)

        ; --- (a) coincident lit pixels: both light the left half ---
        lda #$F0
        sta GRP0
        sta GRP1                ; P0 and P1 both light the left 16px
        sta CXCLR
        jsr render_frame
        P0P1_IS $80, $02        ; expect a P0-P1 collision (shared lit columns)

        ; --- (b) sticky: separate the objects WITHOUT clearing the latch ---
        sta WSYNC
        SLEEP 55
        sta RESP0               ; move P0 far right, away from P1
        jsr render_frame        ; no new overlap this frame, and no CXCLR
        P0P1_IS $80, $03        ; expect the latch still set (collision is sticky)

        ; --- CXCLR clears the latch ---
        sta CXCLR
        jsr render_frame
        P0P1_IS $00, $04        ; expect cleared

        ; --- finer per-pixel: interleaved bits ($AA vs $55) never coincide,
        ;     so no collision despite the same span; $AA vs $AA coincides ---
        sta WSYNC
        SLEEP 31
        sta RESP0               ; re-colocate P0 with P1
        lda #$AA
        sta GRP0                ; P0 lights alternate pixels 1010...
        lda #$55
        sta GRP1                ; P1 lights the gaps       0101... -> disjoint
        sta CXCLR
        jsr render_frame
        P0P1_IS $00, $05        ; expect no collision (interleaved, never share a column)
        lda #$AA
        sta GRP1                ; now P1 matches P0: every lit column shared
        sta CXCLR
        jsr render_frame
        P0P1_IS $80, $06        ; expect a collision

        PASS_TEST

render_frame:
        jsr vertical_sync
        jsr vblank_lines
        ldx #VISIBLE_LINES
.rf:
        sta WSYNC
        dex
        bne .rf
        jsr overscan_lines
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
