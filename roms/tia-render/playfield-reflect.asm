; playfield-reflect — CTRLPF bit 0 decides how the playfield's right half is
; built from its left half: repeated, or mirror-imaged.
;
; The playfield is drawn as 40 cells of 4 pixels across the 160-pixel line.
; Twenty bits (from PF0/PF1/PF2) describe the left half, pixels 0-79 (cells
; 0-19). The right half, pixels 80-159 (cells 20-39), is not a fourth register
; — it is derived from the same twenty bits, and CTRLPF bit 0 (the reflect bit)
; picks how:
;   clear -> DUPLICATE: the right half repeats the left in the same order, so
;            cell 20 = cell 0, cell 21 = cell 1, ...   (left pattern again)
;   set   -> MIRROR:    the right half plays the left back reversed, so cell 20
;            = cell 19, ... cell 39 = cell 0            (a mirror at the centre)
;
; The test lights only PF0 (its four cells 0-3, pixels 0-15) and leaves PF1/PF2
; dark, giving a single lit block at the far left. Where that block re-appears
; in the right half pins down the mode:
;   duplicate -> the block repeats at cells 20-23, pixels 80-95
;   mirror    -> the block reflects to the far right, cells 36-39, pixels
;                144-159, and pixels 80-95 stay dark
;
; A self-test has no screen to inspect, so it senses the right half with two
; 1-pixel missiles used as fixed probes, reading back the missile-playfield
; collision latches (CXM0FB / CXM1FB bit 7). Missile 0 is parked at ~px 88, in
; the duplicate block's cells 20-23; missile 1 at ~px 151, in the mirror block's
; cells 36-39. One full frame is rendered per mode, and the two latches read out
; the mode directly: exactly one probe should be lit in each.
;
;   CODE $01 = reflect off (duplicate): M0 at px 88 should collide but didn't
;        $02 = reflect off (duplicate): M1 at px 151 should be dark but collided
;        $03 = reflect on  (mirror):    M0 at px 88 should be dark but collided
;        $04 = reflect on  (mirror):    M1 at px 151 should collide but didn't
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SCRATCH = $90

        MAC COLL_IS
        lda {1}
        and #$80
        sta SCRATCH
        ASSERT_EQ SCRATCH, {2}, {3}
        ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF              ; playfield colour (only lit/unlit matters)
        lda #$02
        sta ENAM0              ; enable both 1px probe missiles
        sta ENAM1
        lda #$FF
        sta PF0                 ; light PF0's four cells 0-3; PF1/PF2 stay 0
        lda #$00
        sta PF1
        sta PF2

        ; M0 in the right-half PF0-duplicate region, M1 in the mirror region
        sta WSYNC
        SLEEP 47
        sta RESM0               ; ~px 88  (cells 20-23)
        sta WSYNC
        SLEEP 68
        sta RESM1               ; ~px 151 (cells 36-39, the mirrored-PF0 region)

        ; --- reflect off: right half duplicates -> only M0 (px88) sits on PF ---
        lda #$00
        sta CTRLPF              ; reflect bit clear
        sta CXCLR              ; clear collision latches
        jsr render_frame
        COLL_IS CXM0FB, $80, $01        ; M0 in duplicate block: must collide
        COLL_IS CXM1FB, $00, $02        ; M1 in mirror region: must stay dark

        ; --- reflect on: right half mirrors -> only M1 (px151) sits on PF ---
        lda #$01
        sta CTRLPF              ; reflect bit set
        sta CXCLR              ; clear collision latches
        jsr render_frame
        COLL_IS CXM0FB, $00, $03        ; M0's old block now dark: must not collide
        COLL_IS CXM1FB, $80, $04        ; M1 in mirror block: must collide

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
