; copy-adjacency — player 0, placed the way a game places it, collides with a
; duplicate copy of player 1 at exactly the columns their lit pixels share.
;
; The TIA has no frame memory: it draws each line live as the TV beam sweeps,
; one colour clock per pixel, with the first 68 clocks of every line blanked
; (the beam is off-screen). A player sprite has no position register either —
; a counter free-runs across the line, writing RESP0 or RESP1 restarts it
; wherever the beam is, and the sprite is drawn at that spot on every later
; line. NUSIZ can make the same sprite draw again 16, 32 or 64 clocks along:
; a duplicate copy, whose pixels are as real as any other. The P0-P1
; collision latch (bit 7 of CXPPMM) is set the moment both players light the
; same clock, and never while they merely sit side by side.
;
; Two more things decide the final columns. HMOVE nudges a sprite by the
; signed amount in its motion register (HMP0: -8..+7, positive = left), and
; must move nothing once those registers are cleared.
;
; And a reset's first pixel obeys one rule everywhere: it appears at the
; later of "5 clocks after the strobe" and "3 clocks after blanking ends".
; The CPU can only write on every third clock, and against 68-clock blanking
; that grid always misses the lone clock where those two arms differ by a
; single pixel. But HMOVE stretches blanking to 76 clocks, shifting the grid:
; clock 75 is writable, and a reset there beats the blanking arm by exactly
; one pixel. Pitfall! places its sprites this way every frame; a model one
; pixel off anywhere reports a touch that never happened.
;
; Seven sweeps walk player 0 across player 1's second copy one clock per
; trial, recording the collision latch as hit/miss profiles: an edge sweep
; brackets exact adjacency, three stripe sweeps pin every HMP0 offset, and
; three blanked-reset sweeps pin the landing rule under, at and past the
; stretched-blanking edge. Geometry with each sweep below.
;
;   CODE $01/$02 = edge sweep profile lo/hi wrong
;        $03/$04 = left stripe sweep lo/hi wrong
;        $05/$06 = centre stripe sweep lo/hi wrong
;        $07/$08 = right stripe sweep lo/hi wrong
;        $09/$0A = in-blank reset lo/hi wrong
;        $0B/$0C = blank-edge reset lo/hi wrong
;        $0D/$0E = just-visible reset lo/hi wrong
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PRO     = $90                   ; 7 x 16-bit profile (lo,hi per sweep)
IDX     = $9E                   ; trial index 0..15
PTR     = $A0                   ; -> current sweep's profile pair (2 bytes)

; One 16-trial sweep. {1} = NOP count on the player-0 strobe line (15/16/17
; selects base 45/51/57); {2} = the sweep's profile pair; {3}/{4}/{5} shape
; the player-1 strobe line: lead it with HMOVE ({3}), then {4} NOPs and an
; optional 3-cycle pad ({5}) ahead of RESP1. Every strobe is inline, a fixed
; straight-line run off a fresh WSYNC — a computed jump or indexed store
; would shift its sub-cycle phase (see reset-phase). Only the HMP0 value
; varies per trial, and it is loaded between the two strobe lines so the
; player-1 line's HMOVE always runs with cleared motion registers.
    MAC DOSWEEP
        lda #<{2}
        sta PTR
        ldx #0
.trial:
        stx IDX
        sta WSYNC               ; player 1 line: strobe completes cycle {3}*3+{4}*2+{5}*3+3
        IF {3}
        sta HMOVE               ; cleared registers: no motion, blanking runs to clock 76
        ENDIF
        REPEAT {4}
        nop
        REPEND
        IF {5}
        bit RESULT              ; 3-cycle pad (reads $00, harmless)
        ENDIF
        sta RESP1
        lda HmTable,x
        sta HMP0                ; this trial's nudge (HMP1 stays cleared)
        sta WSYNC               ; player 0: completes cycle 2*{1}+6 -> the base
        REPEAT {1}
        nop
        REPEND
        bit RESULT
        sta RESP0
        jsr apply_and_read
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
        sta COLUPF
        sta CTRLPF
        sta PF0
        sta PF1
        sta PF2
        sta NUSIZ0              ; player 0: one copy, normal width
        sta GRP0
        sta GRP1
        sta REFP0
        sta REFP1
        sta VDELP0
        sta VDELP1
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
        sta PRO+12
        sta PRO+13
        sta PTR+1               ; profiles live in the zero page
        lda #$02
        sta NUSIZ1              ; player 1: two copies, medium spacing (+32)
        lda #$0E
        sta COLUP0              ; cosmetic; the collision matrix ignores colour
        sta COLUP1
        TEST_BEGIN

        jsr vertical_sync
        jsr vblank_lines        ; beam on; the sweeps run in the visible field

        ; Player 1 sits at NUSIZ1=$02: copies based at columns 18 and 50.
        ; Every trial re-strobes both players with inline WSYNC-anchored
        ; strobes (a shared reset latency cancels, so the profiles pin only
        ; relative geometry), applies the trial's HMP0 offset d with one
        ; HMOVE (trial k: d = k-8, landing player 0 at p = base - d), lets
        ; the picture settle over cleared-register HMOVE lines, and records
        ; the latch as bit k of the sweep's 16-bit profile (lo = trials 0-7).

        ; ---- edge sweep ---------------------------------------------------
        ; A 2px probe against a solid copy 2 (lit 50-57). GRP0=$18 lights
        ; p+3/p+4 and reads the same mirrored, so REFP0 on must not move it.
        ; From base 51 the spans overlap iff p = 46..54: trials 5..13 latch,
        ; and the flanking misses sit one clock either side of adjacency.
        lda #$18
        sta GRP0                ; lit pixels p+3, p+4 (palindromic)
        lda #$08
        sta REFP0               ; reflection on: must not move a palindrome
        lda #$FF
        sta GRP1                ; solid copies: copy 2 lit 50..57
edge_sweep:
        DOSWEEP 16, PRO, 0, 12, 0

        ; ---- stripe sweeps ------------------------------------------------
        ; A 1px probe against an alternating copy 2 (GRP1=$AA: lit at 50,52,
        ; 54,56). A trial latches only when the probe lands exactly on a lit
        ; stripe, so any one-clock error flips trials; bases 45/51/57 put
        ; every HMP0 offset on the striped face in at least one sweep.
        lda #$80
        sta GRP0                ; one lit pixel at p
        lda #$00
        sta REFP0
        lda #$AA
        sta GRP1                ; copy 2 lit 50,52,54,56
stripe_left:
        DOSWEEP 15, PRO+2, 0, 12, 0
stripe_centre:
        DOSWEEP 16, PRO+4, 0, 12, 0
stripe_right:
        DOSWEEP 17, PRO+6, 0, 12, 0

        ; ---- blanked-reset sweeps -----------------------------------------
        ; Player 1 re-strobed on an HMOVE-led line with the write ending at
        ; clock 72 (under the stretched blanking), 75 (the writable knife
        ; edge - Pitfall's own strobe) and 78 (past it). A 1px probe hunts
        ; the now single-pixel copy 2: the rule lands it at columns 43, 44
        ; and 47, so exactly trials 10, 9 and 6 hit.
        lda #$80
        sta GRP1                ; single-pixel copies: copy 2 lit at its base
blank_in:
        DOSWEEP 15, PRO+8, 1, 9, 0     ; strobe completes cycle 24: in-blank
blank_edge:
        DOSWEEP 15, PRO+10, 1, 8, 1    ; cycle 25: the blanking edge (Pitfall)
blank_out:
        DOSWEEP 15, PRO+12, 1, 10, 0   ; cycle 26: just visible

        ; ---- verdict ------------------------------------------------------
        ASSERT_EQ PRO+0, $E0, $01   ; edge: trials 5..7 hit
        ASSERT_EQ PRO+1, $3F, $02   ; edge: trials 8..13 hit, 14/15 clear
        ASSERT_EQ PRO+2, $0A, $03   ; left stripes: trials 1,3 hit
        ASSERT_EQ PRO+3, $00, $04   ; left stripes: trials 8..15 all clear
        ASSERT_EQ PRO+4, $A8, $05   ; centre stripes: trials 3,5,7 hit
        ASSERT_EQ PRO+5, $02, $06   ; centre stripes: trial 9 hits
        ASSERT_EQ PRO+6, $00, $07   ; right stripes: trials 0..7 all clear
        ASSERT_EQ PRO+7, $AA, $08   ; right stripes: trials 9,11,13,15 hit
        ASSERT_EQ PRO+8,  $00, $09  ; in-blank reset: copy 2 at 43 -> trial 10
        ASSERT_EQ PRO+9,  $04, $0A
        ASSERT_EQ PRO+10, $00, $0B  ; blank-edge reset: copy 2 at 44 -> trial 9
        ASSERT_EQ PRO+11, $02, $0C
        ASSERT_EQ PRO+12, $40, $0D  ; just-visible reset: copy 2 at 47 -> trial 6
        ASSERT_EQ PRO+13, $00, $0E
        PASS_TEST

; Apply the trial's nudge, then read the settled P0-P1 latch: an HMOVE line
; (HMCLR once the motion burst is over), a line whose HBLANK CXCLR drops the
; latches set at placement-time positions, then drawn lines with the
; Pitfall-style no-op HMOVE (its 8-pixel comb sits far left of every column
; used here). The read lands in the next HBLANK, before that line draws.
; Clobbers X — callers keep the trial index in IDX.
apply_and_read:
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
        lda CXPPMM
        and #$80                ; D7 = the P0-P1 latch
        rts

; Fold one trial into the profile at (PTR): set bit IDX on a latch, leave it
; clear on a miss. Entry: A = masked latch ($80/$00), X = trial index.
record:
        cmp #$80
        bne .done
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
