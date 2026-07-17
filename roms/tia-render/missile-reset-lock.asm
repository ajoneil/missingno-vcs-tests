; missile-reset-lock — locking a missile to its player hides it; releasing it
; drops the missile back at a fixed, size-dependent offset from the player.
;
; The TIA (Television Interface Adaptor, the console's video chip) draws two
; players and their two companion missiles. Writing bit 1 of RESMP0 (RESet
; Missile 0 to Player 0) locks missile M0 to player P0 — while the bit is set
; the missile is forced to the player's horizontal position and its output is
; suppressed, so it disappears from the picture. This is how a game makes a
; missile emerge from its ship without computing a position: lock it to the
; ship, then release it when the shot is fired.
;
; Clearing bit 1 releases the missile. It does not reappear at the player's
; leftmost pixel, nor at the player's geometric centre — it lands at a fixed
; offset to the right of the player's first pixel that depends on the player's
; NUSIZ (Number-SIZe) width: +4 colour clocks (visible pixels) for a normal
; (1x) player, +6 for a double-width (2x) player, +10 for a quad-width (4x)
; player. A quad player is 32px wide, so its geometric centre would be +16; the
; release lands at +10. Hardware-measured: real PAL console, 2026-07-16.
;
; Each offset is measured from that size's own first pixel, because a double-
; or quad-width player starts drawing one colour clock later than a normal one.
;
; The offset is measured directly. A 1-pixel missile M1 is the ruler: it is
; parked to the right of the player and walked left one colour clock per step.
; Every step reads two collision latches — M0-vs-M1 (CXPPMM bit 6) and M1-vs-P0
; (CXM1P bit 7) — so one sweep locates both the released missile and the
; player's first pixel, and the offset is the distance between them in steps.
; Only one step can touch a 1-pixel missile, so a sweep that sees it any other
; number of times means the missile never landed where it should have.
;
;   CODE $01 = 1x sweep saw M0 other than exactly once
;        $02 = 1x release offset wrong — expected $04
;        $03 = 2x sweep saw M0 other than exactly once
;        $04 = 2x release offset wrong — expected $06
;        $05 = 4x sweep saw M0 other than exactly once
;        $06 = 4x release offset wrong — expected $0A
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

OFFS    = $90                   ; 3 bytes: measured release offset, one per size
MCNT    = $93                   ; 3 bytes: sweep steps that saw M0 (must be 1)
PHIT    = $96                   ; last sweep step that saw the player
MHIT    = $97                   ; sweep step that saw M0
IDX     = $98                   ; sweep step 0..STEPS-1
MODEI   = $99                   ; size index 0..2 (into Modes)
STEPS   = 24                    ; enough to walk the ruler past +10 and onto P0

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUP0
        lda #$80
        sta GRP0                ; light only the player's first graphics slot
        lda #$00
        sta NUSIZ1              ; M1 is the 1px ruler; no P1 copies
        lda #$02
        sta ENAM0
        sta ENAM1

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ldx #0
.modeloop:
        stx MODEI
        lda Modes,x
        sta NUSIZ0              ; player size under test (M0 width stays 1)
        sta HMCLR               ; only the ruler may move under HMOVE

        ; Park P0, then the ruler to its right on the same line. The two nops
        ; put the ruler 19px right of the player's first pixel, so any offset
        ; from 0 to 18 is measured rather than merely missing — a wrong landing
        ; is reported as a number, not as "M0 never seen".
        sta WSYNC
        SLEEP 39
        sta RESP0
        nop
        nop
        sta RESM1
        lda #$10
        sta HMM1                ; $10 = one colour clock left per HMOVE

        lda #$02
        sta RESMP0              ; lock M0 to P0: hidden, tracking the player
        sta WSYNC
        sta WSYNC               ; hold the lock over a full line of P0 drawing
        lda #$00
        sta RESMP0              ; release M0 at this size's re-centre offset
        sta PHIT
        sta MHIT
        ldx MODEI
        sta MCNT,x

        ldx #0
.sweep:
        stx IDX
        sta WSYNC
        sta HMOVE               ; ruler one pixel further left
        sta CXCLR               ; clear before this step's line draws
        sta WSYNC               ; the stepped line has now drawn and latched
        lda CXM1P
        and #$80
        beq .no_p0
        ; GRP0 = $80 lights one graphics slot, and a stretched slot covers 2px
        ; (2x) or 4px (4x), so several steps in a row can hit the player. The
        ; ruler walks leftwards, so the last hit is the player's first pixel.
        lda IDX
        sta PHIT
.no_p0:
        lda CXPPMM
        and #$40                ; ruler over the released M0
        beq .nextstep
        lda IDX
        sta MHIT
        ldx MODEI
        inc MCNT,x
.nextstep:
        ldx IDX
        inx
        cpx #STEPS
        bne .sweep

        ; Both landmarks come off the same ruler in the same sweep, so the
        ; ruler's own starting position cancels in the subtraction: the result
        ; depends only on HMOVE stepping one pixel at a time, never on where
        ; the RESP0 or RESM1 strobes above happen to land.
        lda PHIT
        sec
        sbc MHIT
        ldx MODEI
        sta OFFS,x

        inx
        cpx #3
        bne .modeloop

        ASSERT_EQ MCNT+0, $01, $01
        ASSERT_EQ OFFS+0, $04, $02   ; 1x: player first pixel +4
        ASSERT_EQ MCNT+1, $01, $03
        ASSERT_EQ OFFS+1, $06, $04   ; 2x: +6
        ASSERT_EQ MCNT+2, $01, $05
        ASSERT_EQ OFFS+2, $0A, $06   ; 4x: +10
        PASS_TEST

Modes:
        .byte $00,$05,$07       ; 1x, double, quad (missile width 1 in all)

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
