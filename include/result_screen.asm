; result_screen.asm — shared assert helper + pass/fail result screen.
;
; Included once per test ROM (after the test body). Provides:
;   assert_eq   - comparison helper used by the ASSERT_EQ macro
;   pass_result - entry: RESULT already PASS; solid green screen forever
;   pass_result_observed - entry: RESULT already PASS; green screen with a hex
;                 readout of OBSERVED (white), for characterisation tests whose
;                 recorded-but-unasserted bits must be legible on real hardware
;   fail_result - entry: mark RESULT FAIL; red screen with a hex readout of
;                 CODE (white), OBSERVED (yellow), EXPECTED (cyan) so a failure
;                 is diagnosable on real hardware, where RAM is invisible.
;
; The digits are drawn with the playfield: the HIGH hex nibble in PF1 (natural
; bit order) and the LOW nibble in PF2 (the TIA serialises PF2 low bit first,
; so its glyph rows are stored bit-reversed — see hexfont.asm).
;
; Both screens render a full field of the assembled region's height, and pick
; their colours per region, so the PAL/SECAM binaries look right on their own
; hardware — see region.h for the line counts and the COL_* palette.

        include "region.h"      ; line counts + COL_PASS/FAIL/CODE/OBSERVED/EXPECTED

; Every TIA store below goes through the $40-$7F mirror (`+MIR`). The TIA picks
; its register from A0-A5 and ignores A6, so $49 is COLUBK exactly as $09 is. A6
; is NOT ignored by the Tigervision-family boards: 3F and its relatives watch for
; an access with A6 and A7 both low and take the byte on the bus as a bank number,
; so a store to raw $09 pages a bank as a side effect of setting a colour. Real
; Tigervision code keeps every TIA access on these mirrors for that reason, and
; this screen is linked into those ROMs too. No other board cares which mirror is
; used, so all of them use it and the screen stays mapper-agnostic.
MIR = $40                       ; TIA register mirror: same register, A6 high


; assert_eq: A = observed, X = expected, Y = code.
assert_eq:
        sta OBSERVED
        stx EXPECTED
        sty CODE
        cmp EXPECTED
        beq .ae_ok
        jmp fail_result
.ae_ok:
        rts

; assert_lt: A < X (unsigned)? records A/X/Y, returns if so, else fail_result.
assert_lt:
        sta OBSERVED
        stx EXPECTED
        sty CODE
        cmp EXPECTED            ; C clear if A < X
        bcc .lt_ok
        jmp fail_result
.lt_ok:
        rts

; assert_ge: A >= X (unsigned)?
assert_ge:
        sta OBSERVED
        stx EXPECTED
        sty CODE
        cmp EXPECTED            ; C set if A >= X
        bcs .ge_ok
        jmp fail_result
.ge_ok:
        rts

; ---------------------------------------------------------------------------
pass_result:
        jsr rs_clear_gfx        ; kill any sprites the test left enabled
        lda #COL_PASS           ; green (region-appropriate)
        sta RS_BGCOL
        sta WSYNC+MIR
pass_frame:
        lda #2
        sta VSYNC+MIR
        sta WSYNC+MIR
        sta WSYNC+MIR
        sta WSYNC+MIR
        lda #0
        sta VSYNC+MIR
        lda #2
        sta VBLANK+MIR
        ldx #VBLANK_LINES
.pvb:   sta WSYNC+MIR
        dex
        bne .pvb
        lda #0
        sta VBLANK+MIR
        lda RS_BGCOL
        sta COLUBK+MIR
        ldx #VISIBLE_LINES
.pvis:  sta WSYNC+MIR
        dex
        bne .pvis
        lda #2
        sta VBLANK+MIR
        ldx #OVERSCAN_LINES
.pos:   sta WSYNC+MIR
        dex
        bne .pos
        jmp pass_frame

; ---------------------------------------------------------------------------
; Opt-in (define RS_PASS_OBSERVED before the include): tests that only jump to
; pass_result don't pay these bytes — some ROMs are within a screen of full.
        IFCONST RS_PASS_OBSERVED
pass_result_observed:
        jsr rs_clear_gfx        ; kill any sprites the test left enabled
pobs_frame:
        lda #2
        sta VSYNC+MIR
        sta WSYNC+MIR
        sta WSYNC+MIR
        sta WSYNC+MIR
        lda #0
        sta VSYNC+MIR
        lda #2
        sta VBLANK+MIR
        ldx #VBLANK_LINES
.ovb:   sta WSYNC+MIR
        dex
        bne .ovb
        lda #0
        sta VBLANK+MIR
        ; visible: green background, OBSERVED as white playfield digits
        lda #COL_PASS           ; green (region-appropriate)
        sta COLUBK+MIR
        lda #0
        sta CTRLPF+MIR
        sta PF0+MIR
        sta PF1+MIR
        sta PF2+MIR
        ldx #40                 ; top margin
        jsr rs_blank
        lda #COL_CODE           ; white / SECAM luma-7
        sta COLUPF+MIR
        lda OBSERVED
        jsr draw_byte
        ldx #VISIBLE_LINES-64   ; bottom fill (40+24 = 64 above)
        jsr rs_blank
        lda #2
        sta VBLANK+MIR
        ldx #OVERSCAN_LINES
.oos:   sta WSYNC+MIR
        dex
        bne .oos
        jmp pobs_frame
        ENDIF   ; RS_PASS_OBSERVED

; ---------------------------------------------------------------------------
fail_result:
        jsr rs_clear_gfx        ; kill any sprites the test left enabled
        lda #FAIL_MAGIC
        sta RESULT
fail_frame:
        lda #2
        sta VSYNC+MIR
        sta WSYNC+MIR
        sta WSYNC+MIR
        sta WSYNC+MIR
        lda #0
        sta VSYNC+MIR
        lda #2
        sta VBLANK+MIR
        ldx #VBLANK_LINES
.fvb:   sta WSYNC+MIR
        dex
        bne .fvb
        lda #0
        sta VBLANK+MIR
        ; visible: red background, playfield digits (no reflect -> digits repeat)
        lda #COL_FAIL           ; red (region-appropriate)
        sta COLUBK+MIR
        lda #0
        sta CTRLPF+MIR
        sta PF0+MIR
        sta PF1+MIR
        sta PF2+MIR
        ldx #12                 ; top margin
        jsr rs_blank
        lda #COL_CODE           ; white / SECAM luma-7
        sta COLUPF+MIR
        lda CODE
        jsr draw_byte
        ldx #8
        jsr rs_blank
        lda #COL_OBSERVED       ; yellow / SECAM luma-6
        sta COLUPF+MIR
        lda OBSERVED
        jsr draw_byte
        ldx #8
        jsr rs_blank
        lda #COL_EXPECTED       ; cyan / SECAM luma-5
        sta COLUPF+MIR
        lda EXPECTED
        jsr draw_byte
        ldx #VISIBLE_LINES-100  ; bottom fill (12+24+8+24+8+24 = 100 above)
        jsr rs_blank
        lda #2
        sta VBLANK+MIR
        ldx #OVERSCAN_LINES
.fos:   sta WSYNC+MIR
        dex
        bne .fos
        jmp fail_frame

; rs_clear_gfx: disable everything a test can leave painting or sounding —
; movable objects (players, missiles, ball), the playfield (a test that
; writes PF0-PF2, e.g. via stack pushes aliased onto TIA, would bar the pass
; screen), score/reflect modes, and both audio channels.
rs_clear_gfx:
        lda #0
        sta GRP0+MIR
        sta GRP1+MIR
        sta ENAM0+MIR
        sta ENAM1+MIR
        sta ENABL+MIR
        sta PF0+MIR
        sta PF1+MIR
        sta PF2+MIR
        sta CTRLPF+MIR
        sta AUDV0+MIR
        sta AUDV1+MIR
        rts

; rs_blank: X blank scanlines, playfield forced off.
rs_blank:
.rb:    sta WSYNC+MIR
        lda #0
        sta PF1+MIR
        sta PF2+MIR
        dex
        bne .rb
        rts

; draw_byte: A = byte -> two hex digits over 24 scanlines (8 rows x3 scale).
;   HIGH nibble via PF1 (font_pf1), LOW nibble via PF2 (font_pf2, reversed).
draw_byte:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr set_p1              ; RS_P1 = font_pf1 + hi*8
        pla
        and #$0F
        jsr set_p2              ; RS_P2 = font_pf2 + lo*8
        ldy #0
.db_row:
        ldx #3                  ; vertical scale
.db_rep:
        sta WSYNC+MIR
        lda (RS_P1),y
        sta PF1+MIR
        lda (RS_P2),y
        sta PF2+MIR
        dex
        bne .db_rep
        iny
        cpy #8
        bne .db_row
        rts

set_p1:                         ; A = nibble -> RS_P1 = font_pf1 + A*8
        asl
        asl
        asl
        clc
        adc #<font_pf1
        sta RS_P1
        lda #>font_pf1
        adc #0
        sta RS_P1+1
        rts

set_p2:                         ; A = nibble -> RS_P2 = font_pf2 + A*8
        asl
        asl
        asl
        clc
        adc #<font_pf2
        sta RS_P2
        lda #>font_pf2
        adc #0
        sta RS_P2+1
        rts

        include "hexfont.asm"
