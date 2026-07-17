; stack-aliases-tia — stack pushes with the pointer in $00-$7F write TIA registers.
;
; The other face of page 1 (its RAM face is cpu/stack-aliases-ram). The 2600
; decodes A12=0, A7=0 as the TIA — the video/sound chip — so the low half of
; the stack page, $0100-$017F, is itself the TIA write space seen through the ignored
; A8. A push while the stack pointer sits at $7F or below therefore lands on a
; TIA register: address $011x strobes the register at $1x. Every CLEAN_START
; ROM already relies on this — its stack wipe walks down through page 1 and
; strobes RSYNC as it passes $0143/$0103.
;
; The test enables missiles through this mirror and reads the result back
; through the TIA's collision latches. Two missiles are parked over a solid
; playfield bar but left disabled. ENAM0/ENAM1 (bit 1 = "enable missile 0/1")
; are the registers at $1D/$1E; a missile only collides with the playfield once
; enabled, so CXM0FB/CXM1FB — the missile-0/1-versus-playfield collision latches
; — read back exactly which missiles a mirrored write switched on.
;
; Two probes:
;   1. Decode: with the stack pointer at $1D, PHA of $02 writes $011D = ENAM0.
;      Missile 0 must turn on (bit 1 set) and NOTHING else — ENAM1 stays off.
;   2. Rapid fire: a JSR pushes its return address high-byte-then-low-byte on
;      consecutive CPU cycles, 3 colour clocks apart. Sited so that address is
;      $F202, the pushes are $F2 -> $011E = ENAM1 then $02 -> $011D = ENAM0 —
;      both bytes have bit 1 set, so one instruction switches both missiles on.
;
;   CODE $01 = baseline: M0-PF latched with missile 0 disabled (must be clear)
;        $02 = baseline: M1-PF latched with missile 1 disabled (must be clear)
;        $03 = pha to $011D did not enable missile 0 (mirror decode missing)
;        $04 = the pha also enabled missile 1 (write splatted past ENAM0)
;        $05 = re-baseline before the JSR probe: missile 0 must be off again
;        $06 = JSR push (PCL, 2nd write) did not enable missile 0
;        $07 = JSR push (PCH, 1st write) did not enable missile 1
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

S       = $90                   ; S..S+6: masked collision samples

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$FF
        sta PF1                 ; solid bar, px 16-47 (and its right-half repeat)
        lda #$0E
        sta COLUPF              ; playfield colour (white); missiles collide with it

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; park both missiles inside the PF1 bar (still disabled)
        sta WSYNC
        SLEEP 25
        sta RESM0               ; strobe reset-missile-0 position: M0 at x=20
        sta WSYNC
        SLEEP 27
        sta RESM1               ; strobe reset-missile-1 position: M1 at x=26

        ; --- baseline: nothing enabled, so nothing collides ---
        sta CXCLR               ; clear all collision latches
        sta WSYNC
        sta WSYNC               ; let two lines paint over the missiles
        lda CXM0FB
        and #$80                ; D7 = missile 0 vs playfield
        sta S+0                 ; expect $00
        lda CXM1FB
        and #$80                ; D7 = missile 1 vs playfield
        sta S+1                 ; expect $00

        ; --- probe 1: pha with SP=$1D writes $011D = ENAM0 ---
        ldx #$1D
        txs                     ; stack pointer into the TIA mirror
        lda #$02
        pha                     ; ENAM0 = $02 via the page-1 TIA mirror
        ldx #$FF
        txs                     ; stack sane again before anything else
        sta CXCLR
        sta WSYNC
        sta WSYNC
        lda CXM0FB
        and #$80
        sta S+2                 ; expect $80: M0 on via the mirror
        lda CXM1FB
        and #$80
        sta S+3                 ; expect $00: the push hit ENAM0 only

        ; --- probe 2: JSR at $F200 pushes $F2/$02 into ENAM1/ENAM0 ---
        lda #$00
        sta ENAM0               ; direct write: back to both-off
        sta CXCLR
        sta WSYNC
        sta WSYNC
        lda CXM0FB
        and #$80
        sta S+4                 ; expect $00: clean slate for the JSR probe
        ldx #$1E
        txs                     ; pushes will land at $011E, then $011D
        jmp JsrSite

JsrBack:
        sta CXCLR
        sta WSYNC
        sta WSYNC
        lda CXM0FB
        and #$80
        sta S+5                 ; expect $80: PCL=$02 enabled M0
        lda CXM1FB
        and #$80
        sta S+6                 ; expect $80: PCH=$F2 enabled M1

        ASSERT_EQ S+0, $00, $01
        ASSERT_EQ S+1, $00, $02
        ASSERT_EQ S+2, $80, $03
        ASSERT_EQ S+3, $00, $04
        ASSERT_EQ S+4, $00, $05
        ASSERT_EQ S+5, $80, $06
        ASSERT_EQ S+6, $80, $07
        PASS_TEST

FixSp:
        ldx #$FF                ; the "subroutine": no rts (SP was in the TIA);
        txs                     ; restore SP and jump back instead
        jmp JsrBack

        ; the JSR must sit at exactly $F200 so its pushed return address $F202
        ; has bit 1 set in both bytes ($F2/$02) — each push is an ENAMx enable
        org $F200
JsrSite:
        jsr FixSp               ; pushes $F2 -> $011E (ENAM1), $02 -> $011D (ENAM0)

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
