; latches — a TIA collision latch sets when two objects overlap, holds clear
; while they don't, and clears only on CXCLR.
;
; The TIA (Television Interface Adaptor) is the console's video chip. It draws
; each scanline from six independently-positioned pixel sources: two players
; (P0, P1), two missiles (M0, M1), the ball (BL), and the playfield (PF). At
; every colour clock the chip knows which of the six are lit at the current
; beam position.
;
; For each pair of sources the TIA holds one collision latch: a set-only
; flip-flop. The instant both members of a pair are lit on the same pixel the
; latch sets, and it stays set for the rest of the frame — it records that the
; two objects touched somewhere, not where. A latch never clears itself.
; Writing CXCLR (a strobe: the value is ignored, the write is the event) resets
; every collision latch to zero at once. Each latch is read back in the top bit
; (bit 7) or the next bit (bit 6) of a collision register. This test uses the
; two "object vs playfield/ball" registers and reads bit 7 of each:
;   CXP0FB bit 7 = P0 touched PF
;   CXM0FB bit 7 = M0 touched PF
;
; The test draws a player (P0) and a missile (M0) over a solid (fully lit)
; playfield and renders a whole field: both objects overlap lit PF, so both PF
; latches must set. It then strobes CXCLR and re-reads P0-PF, which must now be
; clear, proving the strobe works. Finally it clears the playfield (fully dark)
; and renders again: with no lit PF underneath, the latches must stay clear — a
; latch that sets here is reporting a collision that never happened.
;
;   CODE $01 = P0 over a solid playfield, but the P0-PF latch never set
;        $02 = after CXCLR the P0-PF latch was still set (clear had no effect)
;        $03 = P0 over an empty playfield, yet the P0-PF latch set (false hit)
;        $04 = M0 over a solid playfield, but the M0-PF latch never set
;        $05 = M0 over an empty playfield, yet the M0-PF latch set (false hit)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SCRATCH = $90

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ; place P0 and M0 near the left, solid 8px player, missile width 1
        sta WSYNC               ; align to a fresh scanline
        SLEEP 20                ; strobe deep in HBLANK -> object near left edge
        sta RESP0               ; P0 position latched here
        sta RESM0               ; M0 co-located with P0 (fine; both vs PF)
        lda #$FF
        sta GRP0                ; solid player: all 8 bits lit
        lda #$02
        sta ENAM0               ; enable missile
        lda #$0E
        sta COLUPF              ; playfield white (colour is immaterial here)

        ; --- P0 / M0 over a SOLID playfield: both must collide with PF ---
        lda #$FF
        sta PF0                 ; playfield lit across the whole line
        sta PF1
        sta PF2
        sta CXCLR               ; clear latches before the measured frame
        jsr render_frame        ; sweep a full field; overlaps latch
        lda CXP0FB
        and #$80                ; isolate P0-PF (bit 7)
        sta SCRATCH
        ASSERT_EQ SCRATCH, $80, $01     ; assert P0-PF set

        ; CXCLR must clear the latch we just set
        sta CXCLR               ; strobe: reset all collision latches
        lda CXP0FB
        and #$80
        sta SCRATCH
        ASSERT_EQ SCRATCH, $00, $02     ; assert P0-PF now clear

        ; --- P0 over an EMPTY playfield: no P0-PF collision ---
        lda #$00
        sta PF0                 ; playfield fully dark
        sta PF1
        sta PF2
        sta CXCLR
        jsr render_frame        ; P0 now draws over background only
        lda CXP0FB
        and #$80
        sta SCRATCH
        ASSERT_EQ SCRATCH, $00, $03     ; assert P0-PF stayed clear

        ; --- M0 over a SOLID playfield: missile must collide with PF ---
        lda #$FF
        sta PF0                 ; playfield lit again
        sta PF1
        sta PF2
        sta CXCLR
        jsr render_frame
        lda CXM0FB
        and #$80                ; isolate M0-PF (bit 7)
        sta SCRATCH
        ASSERT_EQ SCRATCH, $80, $04     ; assert M0-PF set

        ; --- M0 over an EMPTY playfield: no M0-PF collision ---
        lda #$00
        sta PF0                 ; playfield dark again
        sta PF1
        sta PF2
        sta CXCLR
        jsr render_frame
        lda CXM0FB
        and #$80
        sta SCRATCH
        ASSERT_EQ SCRATCH, $00, $05     ; assert M0-PF stayed clear

        PASS_TEST

; Draw one field so the enabled objects are rendered and any overlaps
; latch. Object positions/graphics are set by the caller and free-run each line.
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
