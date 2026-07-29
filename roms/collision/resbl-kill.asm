; resbl-kill — a RESBL write erases a ball pixel that is committed but not
; yet on screen — including a pixel landing on the very clock the erasure
; acts: the erasure is two clocks wide, not one.
;
; The TIA (the console's video chip) has no frame memory: it draws each
; scanline live as the TV beam sweeps, one pixel per "colour clock". The
; ball has no position register. A counter free-runs across the line, and
; writing RESBL restarts that counter wherever the beam happens to be — from
; then on the ball redraws at that column on every line.
;
; The counter's start signal is not instant. It takes a few clocks to reach
; the pixel output, so there is a brief moment when the ball is committed to
; lighting but still dark. A RESBL write arriving in that moment does two
; things: it plants the counter at the beam — the new position — and, one
; clock before the plant lands, it ERASES ("kills") the committed dark
; pixel, so the old position never lights. A pixel that has already reached
; the screen stays.
;
; Exactly one colour clock sits between "already on screen" and "still
; dark": a pixel landing on the same clock the erasure acts. That pixel is
; ERASED too — the erasure covers its own acting clock. Hardware-measured:
; real PAL console, 2026-07-28.
;
; The ball is the only object that can show this edge. A missile's RESMx
; write suppresses its start decode from write to plant, blanking exactly
; the pixels an erasure could reach; RESBL has no such suppression — the
; write itself starts a fresh ball scan.
;
; The test parks the ball at sixteen columns in turn, one-pixel steps
; sweeping across the erasure clock, then re-strobes RESBL at a fixed
; mid-line write. A width-one missile parked at the same column reads the
; verdict through the collision matrix: latch set = the parked pixel lit.
; A second sweep parks the missile at the strobe's landing column instead,
; proving the replanted ball arrives where it should. Geometry in the
; comments below. On PASS the screen shows the boundary byte as hex digits
; (pass_result_observed), so the erasure's measured edge stays legible on a
; real console without reading RAM.
;
;   CODE $01/$02 = the replanted ball missed its landing column, trials
;                  0-7 / 8-15 (the landing must be column 26)
;        $03    = the erased side read wrong (trials 0-7, expected $20:
;                  every parked pixel past the erasure clock dies, and only
;                  trial 5 lights — the replant landing itself)
;        $04    = the erasure's edge read wrong (trials 8-15, expected $FE:
;                  the pixel ON the erasure clock dies, every pixel before
;                  it survives). OBSERVED $FF = a one-clock erasure sparing
;                  the boundary pixel; lower even values = an erasure
;                  reaching further back still.
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

RS_PASS_OBSERVED = 1            ; pass screen shows the boundary byte

PRO     = $90                   ; 2 x 16-bit profile (lo,hi per cell)
IDX     = $9C                   ; trial index 0..15
PTR     = $9E                   ; -> current cell's profile pair (2 bytes)

; One 16-trial cell, five lines per trial:
;
;   park lines   the probe missile, then the ball, strobed off fresh WSYNCs
;                (write ends clock 87 -> both first-pixel at column 23; in
;                the landing cell the probe's write ends clock 90 -> 26)
;   nudge line   one HMOVE applies the trial's HMBL walk d = k-8 (and HMM0 =
;                d in the kill cell, 0 in the landing cell); HMCLR once the
;                motion burst is over, so the measured line runs with every
;                motion register cleared and NO HMOVE — nothing stuffs,
;                nothing moves: the probe is inert by construction
;   measured     CXCLR in the entering hblank, then the strobe under test:
;                a second RESBL, write ending clock 90. Its kill clock is 91
;                = column 23; its replant delivers at 90+4 = column 26. The
;                parked ball pixel at L = 23-d = 31-k sweeps columns 16..31
;                across both.
;   read line    the ball-vs-missile latch (CXM0FB bit 6) in the leaving
;                hblank — one line's worth of collision, nothing else
;
; {1} = 1 parks the probe with the ball's nudge (at L: "did the old pixel
; light?"), 0 parks it unmoved at the landing ("did the replant deliver?");
; {2} = the cell's profile pair, bit k of the pair records trial k. Every
; strobe is inline, a fixed straight-line run off a fresh WSYNC — a computed
; jump or indexed store would shift its sub-cycle phase (see reset-phase).
; Only the HM nudges vary per trial, loaded between the strobe lines.
    MAC DOCELL
        lda #<{2}
        sta PTR
        ldx #0
.trial:
        stx IDX
        sta WSYNC               ; park the probe missile
        IF {1}
        REPEAT 13               ; write ends clock 87 -> column 23, as the ball
        nop
        REPEND
        ELSE
        REPEAT 12               ; write ends clock 90 -> column 26, the landing
        nop
        REPEND
        bit RESULT              ; 3-cycle pad (reads $00, harmless)
        ENDIF
        sta RESM0
        sta WSYNC               ; park the ball: write ends clock 87 -> column 23
        REPEAT 13
        nop
        REPEND
        sta RESBL
        lda HmTable,x           ; this trial's nudge d = k-8 (left positive)
        sta HMBL
        IF {1}
        sta HMM0                ; probe rides along: both land at L = 23 - d
        ELSE
        lda #$00
        sta HMM0                ; probe stays at the landing column
        ENDIF
        sta WSYNC               ; nudge line: one HMOVE applies the walk
        sta HMOVE
        REPEAT 18
        nop
        REPEND
        sta HMCLR               ; cycle 42: the motion burst is long over
        sta WSYNC               ; measured line: no HMOVE, no motion registers
        sta CXCLR               ; hblank: scrub placement-time latches
        REPEAT 12
        nop
        REPEND
        sta RESBL               ; the strobe under test: write ends clock 90
        sta WSYNC
        lda CXM0FB              ; hblank: the ball-vs-missile latch, this line only
        and #$40
        ldx IDX
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
        sta CTRLPF              ; ball width 1
        sta PF0
        sta PF1
        sta PF2
        sta NUSIZ0              ; missile 0 width 1
        sta NUSIZ1
        sta GRP0
        sta GRP1
        sta ENAM1
        sta VDELBL
        sta HMCLR               ; all five motion registers cleared
        sta PRO+0
        sta PRO+1
        sta PRO+2
        sta PRO+3
        sta PTR+1               ; profiles live in the zero page
        lda #$02
        sta ENAM0               ; probe on
        sta ENABL               ; ball on
        lda #$0E
        sta COLUP0              ; cosmetic; the collision matrix ignores colour
        sta COLUPF
        TEST_BEGIN

        jsr vertical_sync
        jsr vblank_lines        ; beam on; the cells run in the visible field

kill_cell:
        DOCELL 1, PRO           ; probe at L: did the old pixel light?
landing_cell:
        DOCELL 0, PRO+2         ; probe at 26: did the replant deliver?

        ; ---- verdict ------------------------------------------------------
        ; Landing profile first: it pins the construction every kill-profile
        ; reading leans on. The replant delivers at column 26 on every trial
        ; — even those whose old pixel survived — so both bytes read $FF; a
        ; landing anywhere else reads all-clear.
        ASSERT_EQ PRO+2, $FF, $01
        ASSERT_EQ PRO+3, $FF, $02
        ; Kill profile lo: trials 0-7 park L = 31..24, past the kill clock —
        ; those scans are erased, and only trial 5 (L = 26) lights, being the
        ; replant landing itself, not a survivor.
        ASSERT_EQ PRO+0, $20, $03
        ; Kill profile hi, the boundary byte, asserted last so its code is
        ; unambiguous: trials 9-15 park L = 22..16, before the kill clock —
        ; those pixels survive. Trial 8 (bit 0, L = 23) lands ON the kill
        ; clock and dies with the rest: the two-clock erasure, measured on
        ; real hardware 2026-07-28. A one-clock model reads $FF here.
        ASSERT_EQ PRO+1, $FE, $04
        lda PRO+1               ; boundary byte: legible on the pass screen
        sta OBSERVED
        lda #0
        sta CODE
        lda #PASS_MAGIC
        sta RESULT
        jmp pass_result_observed

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

; HMBL per trial: d = -8..+7 in the signed high nibble, trial k has d = k-8.
HmTable:
        .byte $80,$90,$A0,$B0,$C0,$D0,$E0,$F0
        .byte $00,$10,$20,$30,$40,$50,$60,$70

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
