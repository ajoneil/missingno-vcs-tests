; all-pairs — the TIA holds a separate collision latch for every one of the 15
; source pairs, each readable on its own register bit.
;
; The TIA (Television Interface Adaptor) draws each scanline from six pixel
; sources: two players (P0, P1), two missiles (M0, M1), the ball (BL), and the
; playfield (PF). For every unordered pair of these six there is one collision
; latch — a set-only flip-flop that sets the moment both members are lit on the
; same pixel and holds until CXCLR (a strobe: any write clears all of them at
; once). Six sources make 15 pairs, read back two per register in the top two
; data bits (bit 7 and bit 6) of eight registers:
;   (bit 7, bit 6)
;   CXM0P  = (M0-P1, M0-P0)   CXM1P  = (M1-P0, M1-P1)
;   CXP0FB = (P0-PF, P0-BL)   CXP1FB = (P1-PF, P1-BL)
;   CXM0FB = (M0-PF, M0-BL)   CXM1FB = (M1-PF, M1-BL)
;   CXBLPF = (BL-PF, --   )   CXPPMM = (P0-P1, M0-M1)
;
; The test runs two phases, each rendering a full field so every overlap has a
; chance to latch.
;
; Phase 1 — force every pair to set. All five movable objects are stacked at one
; column over a solid playfield, so all six sources are lit together and every
; one of the 15 latches must set: each register's used bits must all read 1.
;
; Phase 2 — prove no latch is wired to the wrong pair. The playfield is cleared
; and the objects are split into two groups that never cross: group A (P0, M0,
; BL) on the left, group B (P1, M1) on the right. A latch may now set only from
; its own two objects overlapping, so each register must read one exact bit
; pattern — a latch wired to the wrong pair, or a phantom playfield collision,
; reads a different one. With no lit playfield every object-vs-PF bit must also
; read clear.
;
;   CODE $01-$08 = phase 1: the named register (CXM0P..CXPPMM, in order) did
;                  not have all its expected bits set
;        $09 = CXM0P wrong (expect M0-P0 set, M0-P1 clear)
;        $0A = CXM1P wrong (expect M1-P1 set, M1-P0 clear)
;        $0B = CXP0FB wrong (expect P0-BL set, P0-PF clear)
;        $0C = CXP1FB wrong (expect both clear)
;        $0D = CXM0FB wrong (expect M0-BL set, M0-PF clear)
;        $0E = CXM1FB wrong (expect both clear)
;        $0F = CXBLPF wrong (expect BL-PF clear)
;        $10 = CXPPMM wrong (expect P0-P1 and M0-M1 both clear)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SCRATCH = $90

; assert (reg & mask) == mask  (the named bits are all set)
        MAC BITS_SET
        lda {1}
        and #{2}
        sta SCRATCH
        ASSERT_EQ SCRATCH, {2}, {3}
        ENDM

; assert (reg & mask) == expected  (exact defined-bit pattern)
        MAC COLL_EQ
        lda {1}
        and #{2}
        sta SCRATCH
        ASSERT_EQ SCRATCH, {3}, {4}
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF
        ; Widen every object. Each object type latches its reset strobe a fixed,
        ; slightly different number of clocks late, so identically-timed strobes
        ; still land the objects a few pixels apart; at these widths they overlap
        ; regardless. (Pinning those offsets is collision/latency-swallow's job.)
        lda #$37
        sta NUSIZ0              ; P0 quad width + M0 width 8
        sta NUSIZ1              ; P1 quad width + M1 width 8
        lda #$30
        sta CTRLPF             ; BL width 8
        lda #$FF
        sta GRP0
        sta GRP1                ; solid players
        lda #$02
        sta ENAM0
        sta ENAM1
        sta ENABL              ; enable missiles + ball
        lda #$FF
        sta PF0
        sta PF1
        sta PF2                 ; solid playfield

        ; stack all five objects at the same column: identical WSYNC + SLEEP 30
        ; delay before each strobe, so each lands at the same beam position
        sta WSYNC
        SLEEP 30
        sta RESP0               ; P0 position latched
        sta WSYNC
        SLEEP 30
        sta RESP1               ; P1 at the same column
        sta WSYNC
        SLEEP 30
        sta RESM0               ; M0    "     "     "
        sta WSYNC
        SLEEP 30
        sta RESM1               ; M1    "     "     "
        sta WSYNC
        SLEEP 30
        sta RESBL               ; BL    "     "     "

        sta CXCLR               ; clear latches before the measured frame
        jsr render_frame        ; sweep a full field; all six sources overlap

        ; every register's used bits must read 1 (mask $C0, or $80 for CXBLPF)
        BITS_SET CXM0P,  $C0, $01
        BITS_SET CXM1P,  $C0, $02
        BITS_SET CXP0FB, $C0, $03
        BITS_SET CXP1FB, $C0, $04
        BITS_SET CXM0FB, $C0, $05
        BITS_SET CXM1FB, $C0, $06
        BITS_SET CXBLPF, $80, $07
        BITS_SET CXPPMM, $C0, $08

        ; --- negative control: two DISJOINT groups, no playfield, so each pair's
        ; bit is set only if its own two objects overlap. A bit that aliased
        ; another pair would read the wrong value here. Group A (P0,M0,BL) at the
        ; left; group B (P1,M1) far right; nothing crosses the gap. ---
        lda #$00
        sta PF0
        sta PF1
        sta PF2                 ; no playfield: all object-PF bits must clear

        sta WSYNC
        SLEEP 20
        sta RESP0               ; group A ~px 12 (left)
        sta WSYNC
        SLEEP 20
        sta RESM0               ; group A, same column as P0
        sta WSYNC
        SLEEP 20
        sta RESBL               ; group A, same column
        sta WSYNC
        SLEEP 52
        sta RESP1               ; group B ~px 108 (right)
        sta WSYNC
        SLEEP 52
        sta RESM1               ; group B, same column as P1

        sta CXCLR               ; clear latches before the measured frame
        jsr render_frame        ; sweep a full field; only in-group pairs overlap

        COLL_EQ CXM0P,  $C0, $40, $09   ; M0-P0 set (A), M0-P1 clear (cross)
        COLL_EQ CXM1P,  $C0, $40, $0A   ; M1-P1 set (B), M1-P0 clear (cross)
        COLL_EQ CXP0FB, $C0, $40, $0B   ; P0-BL set (A), P0-PF clear (no PF)
        COLL_EQ CXP1FB, $C0, $00, $0C   ; P1-BL clear (cross), P1-PF clear
        COLL_EQ CXM0FB, $C0, $40, $0D   ; M0-BL set (A), M0-PF clear
        COLL_EQ CXM1FB, $C0, $00, $0E   ; M1-BL clear (cross), M1-PF clear
        COLL_EQ CXBLPF, $80, $00, $0F   ; BL-PF clear (no PF)
        COLL_EQ CXPPMM, $C0, $00, $10   ; P0-P1, M0-M1 both clear (cross-group)

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
