; blanked-reset — a missile or ball reset strobed under HMOVE's stretched
; blanking lands where the blanking rule puts it; one writable clock later
; the reset outruns that rule by a single pixel.
;
; The TIA has no frame memory: it draws each line live as the TV beam
; sweeps, one colour clock per pixel, with the first 68 clocks of every line
; blanked (the beam is off-screen). A missile or the ball has no position
; register — a counter free-runs across the line, and writing RESM0 or RESBL
; restarts it wherever the beam is. The object's first pixel then obeys one
; rule everywhere: it appears at the later of "4 clocks after the strobe"
; and "2 clocks after blanking ends". (Players are not exercised here: a
; single-width player mid-scan lands 5 clocks after the strobe, but one
; clock later at double or quad width — and, measured in
; merge-delivery-replant, when the strobe abuts the blank edge: write
; end 69 -> column 7, not the 6 a five-and-three arm pair predicts.)
;
; The CPU can only write on every third clock, and against 68-clock blanking
; that grid always misses the lone clock where those two arms differ by a
; single pixel — so a model that gives every blanked reset one fixed landing
; survives every ordinary line. But HMOVE stretches blanking to 76 clocks,
; shifting the grid: clock 75 is writable, and a reset there beats the
; blanking arm by exactly one pixel.
;
; The test strobes each object on HMOVE-led lines with the write ending
; under the blanking, on that knife edge, and just past it, then reads the
; object-vs-player collision latch while a one-pixel player 0 steps across
; the landing zone: exactly one trial per sweep hits, at the landing the
; rule predicts. Geometry in the comments below.
;
;   CODE $01/$02, $03/$04, $05/$06 = missile 0 at clock 72/75/78: profile
;                                    lo/hi wrong (M0-P0 latch, CXM0P bit 6)
;        $07/$08, $09/$0A, $0B/$0C = ball at clock 72/75/78: profile lo/hi
;                                    wrong (P0-BL latch, CXP0FB bit 6)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PRO     = $90                   ; 6 x 16-bit profile (lo,hi per cell)
IDX     = $9C                   ; trial index 0..15
PTR     = $9E                   ; -> current cell's profile pair (2 bytes)

; One 16-trial cell. {1} = the object's reset strobe; {2}/{3} = NOP count and
; optional 3-cycle pad sizing the strobe line (9/8+pad/10 finish the write at
; clock 72/75/78); {4} = the cell's profile pair; {5}/{6} = the collision
; register and mask to read. Every strobe is inline, a fixed straight-line
; run off a fresh WSYNC — a computed jump or indexed store would shift its
; sub-cycle phase (see reset-phase). Only the HMP0 value varies per trial,
; and it is loaded between the strobe lines so the object line's HMOVE
; always runs with cleared motion registers.
    MAC DOCELL
        lda #<{4}
        sta PTR
        ldx #0
.trial:
        stx IDX
        sta WSYNC               ; object line: HMOVE-led, blanking runs to clock 76
        sta HMOVE
        REPEAT {2}
        nop
        REPEND
        IF {3}
        bit RESULT              ; 3-cycle pad (reads $00, harmless)
        ENDIF
        sta {1}
        lda HmTable,x
        sta HMP0                ; this trial's probe nudge
        sta WSYNC               ; probe line: completes cycle 26 -> base 15
        REPEAT 10
        nop
        REPEND
        bit RESULT
        sta RESP0
        jsr settle
        ldx IDX
        lda {5}
        and #{6}
        jsr record
        inx
        cpx #16
        bne .trial
    ENDM

        org $F000

Reset:
        ; Not CLEAN_START: a ~2600-cycle clear loop walks every strobe below
        ; onto one global-clock phase and can mask a phase-dependent landing
        ; fault (see reset-phase). Short straight-line init of what is used.
        sei
        cld
        ldx #$FF
        txs
        lda #$00
        sta VBLANK
        sta COLUBK
        sta COLUPF
        sta CTRLPF              ; ball width 1
        sta PF0
        sta PF1
        sta PF2
        sta NUSIZ0              ; missile 0 width 1; player 0 one copy
        sta NUSIZ1
        sta GRP1
        sta REFP0
        sta VDELP0
        sta VDELBL
        sta ENAM0
        sta ENAM1
        sta ENABL
        sta HMCLR               ; all five motion registers cleared
        sta PRO+0
        sta PRO+1
        sta PRO+2
        sta PRO+3
        sta PRO+4
        sta PRO+5
        sta PRO+6
        sta PRO+7
        sta PRO+8
        sta PRO+9
        sta PRO+10
        sta PRO+11
        sta PTR+1               ; profiles live in the zero page
        lda #$80
        sta GRP0                ; the probe: one lit pixel at its base
        lda #$0E
        sta COLUP0              ; cosmetic; the collision matrix ignores colour
        sta COLUPF
        TEST_BEGIN

        jsr vertical_sync
        jsr vblank_lines        ; beam on; the cells run in the visible field

        ; Per trial: the object strobes on an HMOVE-led line (cleared motion
        ; registers: no motion, just stretched blanking), then a 1px player 0
        ; re-strobes to base 15 and takes the trial's HMP0 offset d (trial k:
        ; d = k-8 -> probe column 23-k; the probe's own placement is
        ; copy-adjacency's subject). Rule landings: clock 72 -> max(76,78) =
        ; column 10, 75 -> 79 = 11, 78 -> 82 = 14. Bit k of the profile
        ; records trial k (lo byte = trials 0-7).

        ; ---- missile 0 ----------------------------------------------------
        lda #$02
        sta ENAM0
m0_in:
        DOCELL RESM0, 9, 0, PRO, CXM0P, $40     ; write ends clock 72: in-blank
m0_edge:
        DOCELL RESM0, 8, 1, PRO+2, CXM0P, $40   ; clock 75: the knife edge
m0_out:
        DOCELL RESM0, 10, 0, PRO+4, CXM0P, $40  ; clock 78: just visible
        lda #$00
        sta ENAM0

        ; ---- ball ---------------------------------------------------------
        lda #$02
        sta ENABL
bl_in:
        DOCELL RESBL, 9, 0, PRO+6, CXP0FB, $40
bl_edge:
        DOCELL RESBL, 8, 1, PRO+8, CXP0FB, $40
bl_out:
        DOCELL RESBL, 10, 0, PRO+10, CXP0FB, $40

        ; ---- verdict ------------------------------------------------------
        ASSERT_EQ PRO+0,  $00, $01  ; M0 in-blank: lands column 10 -> trial 13
        ASSERT_EQ PRO+1,  $20, $02
        ASSERT_EQ PRO+2,  $00, $03  ; M0 knife edge: lands column 11 -> trial 12
        ASSERT_EQ PRO+3,  $10, $04
        ASSERT_EQ PRO+4,  $00, $05  ; M0 just visible: lands column 14 -> trial 9
        ASSERT_EQ PRO+5,  $02, $06
        ASSERT_EQ PRO+6,  $00, $07  ; BL in-blank: lands column 10 -> trial 13
        ASSERT_EQ PRO+7,  $20, $08
        ASSERT_EQ PRO+8,  $00, $09  ; BL knife edge: lands column 11 -> trial 12
        ASSERT_EQ PRO+9,  $10, $0A
        ASSERT_EQ PRO+10, $00, $0B  ; BL just visible: lands column 14 -> trial 9
        ASSERT_EQ PRO+11, $02, $0C
        PASS_TEST

; Settle after the strobes: an HMOVE line applies the trial's nudge (HMCLR
; once the motion burst is over), a CXCLR in the next HBLANK scrubs latches
; from placement-time positions, then drawn lines strobe a cleared-register
; HMOVE — which must move nothing. The caller reads its latch in the HBLANK
; after the last line. Clobbers X — callers keep the trial index in IDX.
settle:
        sta WSYNC
        sta HMOVE               ; applies HMP0; completes cycle 3
        REPEAT 18
        nop
        REPEND
        sta HMCLR               ; cycle ~42: the motion burst is long over
        sta WSYNC
        sta CXCLR               ; HBLANK: scrub placement-time latches
        sta HMOVE               ; cleared registers: comb only, no motion
        ldx #3
.settle:
        sta WSYNC
        sta HMOVE
        dex
        bne .settle
        sta WSYNC
        rts

; Fold one trial into the profile at (PTR): set bit IDX when the latch bit
; survived the mask, leave it clear on a miss. A = masked latch, X = index.
record:
        cmp #$00
        beq .done
        txa
        and #$07
        tay
        lda BitTab,y            ; A = 1 << (IDX mod 8)
        ldy #0
        cpx #8
        bcc .set
        iny                     ; trials 8..15 -> high byte
.set:
        ora (PTR),y
        sta (PTR),y
.done:
        rts

BitTab:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

; HMP0 per trial: d = -8..+7 in the signed high nibble, trial k has d = k-8.
HmTable:
        .byte $80,$90,$A0,$B0,$C0,$D0,$E0,$F0
        .byte $00,$10,$20,$30,$40,$50,$60,$70

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
