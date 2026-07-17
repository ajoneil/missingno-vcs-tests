; onset-sweep — a collision registers wherever an object's LIT pixels overlap
; another's, and nowhere else: the run of hits matches the overlap exactly.
;
; The TIA (Television Interface Adaptor) tests every pair of its movable objects
; for a collision at each colour clock of a scanline, setting a latch bit
; whenever both objects of a pair emit a lit pixel in the same column. Because
; detection is per drawn pixel, stepping one object across another sets the
; pair's latch the instant their lit pixels first share a column (the onset) and
; stops once they part again (the offset). The run of stepping positions that
; register a hit is therefore contiguous and exactly as wide as the overlap,
; flanked by positions that miss.
;
; This test sweeps a one-pixel missile M0 across a solid quad-width player P0 in
; 16 coarse steps and records, at each stepping position, whether the M0-P0 latch
; fired (bit 6 of the read-only collision register CXM0P) — a 16-bit hit/miss
; profile, one bit per position. P0 stays fixed; M0 is re-strobed (a strobe is a
; write whose value is ignored) to a new column each step. The hits form one
; contiguous run, as wide as the overlap, bracketed by a miss at each end. A
; bounding-box or off-by-one model shifts or widens the run into one of those
; bracketing misses. (Pixel-exact edges are hmove-edge's job; no HMOVE here.)
;
;   CODE $01 = low 8 positions of the profile wrong
;        $02 = high 8 positions of the profile wrong
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
PROFILE = $90                   ; 2-byte collision bitfield ($90 lo, $91 hi)
IDX     = $92                   ; sweep index 0..STEPS-1
STEPS   = 16

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$FF
        sta GRP0                ; solid player: all 8 bits lit -> full 32px span
        lda #$07
        sta NUSIZ0              ; P0 quad size (32px); M0 width 1
        lda #$0E
        sta COLUP0              ; player colour (cosmetic; collision ignores it)
        lda #$02
        sta ENAM0              ; enable the probe missile

        ; one field of vertical sync, then leave the beam on for the sweep. Each
        ; position only needs a couple of drawn lines to latch, so the whole
        ; sweep and its verdict land within the first frames after power-on.
        jsr vertical_sync
        jsr vblank_lines        ; VBLANK now 0 — beam on

        ; P0 fixed near mid-screen (reference span the missile sweeps across)
        sta WSYNC
        SLEEP 30
        sta RESP0

        lda #$00
        sta PROFILE
        sta PROFILE+1

        ldx #0
.sweep:
        stx IDX                 ; remember this step index (X is clobbered below)
        ; position M0 at a swept beam column: jump IDX bytes into the nop-sled
        sta WSYNC               ; fresh scanline: fixed phase for the strobe
        txa                     ; VEC = Sled + IDX -> skip IDX of the STEPS nops
        clc
        adc #<Sled
        sta VEC
        lda #>Sled
        adc #0
        sta VEC+1
        jmp (VEC)               ; land in the sled; fewer nops -> earlier strobe
Sled:
        REPEAT STEPS
        nop                     ; each executed nop delays RESM0 by 2 cyc = 6px
        REPEND
        sta RESM0              ; strobe: M0 lands at the swept position

        sta CXCLR              ; clear the position line's own transient overlap
        jsr latch              ; a couple of clean beam-on lines at the new pos
        lda CXM0P
        and #$40               ; isolate bit 6: the M0-P0 latch
        beq .miss               ; not set -> missile fell outside P0's span

        ; hit: set bit IDX in the 16-bit PROFILE (lo = pos 0..7, hi = pos 8..15)
        lda IDX
        and #$07                ; bit position within its byte
        tay
        lda Bit,y               ; A = 1 << (IDX mod 8)
        ldx IDX
        cpx #8
        bcc .lo                 ; IDX < 8 -> low byte
        ora PROFILE+1           ; IDX >= 8 -> set bit in high byte
        sta PROFILE+1
        jmp .next
.lo:
        ora PROFILE             ; set bit in low byte
        sta PROFILE
        jmp .next
.miss:
        nop                     ; leave this position's bit clear
.next:
        ldx IDX
        inx
        cpx #STEPS
        bne .sweep              ; next of the 16 steps

        ; Step -> column (visible-pixel x): step k lands M0 at x = 104 - 6k. The
        ; quad P0 spans x = [37..69), so steps 6..11 (x = 68 down to 38) land
        ; inside and hit, while steps 5 and 12 (x = 74 / 32) bracket the run with
        ; misses — a contiguous onset/offset profile, hardware-exact.
        ASSERT_EQ PROFILE,   $C0, $01   ; low 8 positions: only bits 6,7 set (steps 6,7)
        ASSERT_EQ PROFILE+1, $0F, $02   ; high 8 positions: only bits 0..3 (steps 8..11)
        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; Two beam-on lines: enough for the (statically-positioned) objects to overlap
; and latch. Clobbers X — callers keep the sweep index in IDX.
latch:
        ldx #2
.ll:
        sta WSYNC
        dex
        bne .ll
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
