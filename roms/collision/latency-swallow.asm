; latency-swallow — two unrelated TIA timing quirks, checked in one ROM: how
; long after a reset strobe an object's first pixel lights, and how a jammed
; HMOVE latch can swallow a missile dot entirely.
;
; The TIA (the console's video chip) draws the picture live as the beam sweeps
; a scanline, one colour clock (CLK) per pixel, 160 visible clocks to a line.
; It carries five movable objects — two players (8-bit sprites), two missiles,
; and the ball — plus the playfield, a coarse background pattern. When two of
; them light the same pixel the TIA sets a sticky collision latch for that
; pair, held until a write to CXCLR clears it. Object-versus-playfield hits
; land in bit 7 of the read registers CXP0FB (player 0), CXM0FB (missile 0)
; and CXBLPF (ball).
;
; Two independent stages sit between "the program acts" and "a pixel appears",
; and this ROM measures both:
;
; (A) Reset latency. An object's horizontal position is set by strobing a reset
;     register (RESP0 / RESM0 / RESBL): the object drops wherever the beam is.
;     But its first lit pixel does not appear at the strobe point — it appears a
;     fixed number of colour clocks later, while the reset ripples through the
;     object's counter and serialiser: 5 clocks for a player, 4 for a missile
;     or the ball (the player has one extra pipeline stage). The playfield has
;     no such latency — its pixels are pinned to fixed screen columns straight
;     from the PF0/PF1/PF2 pattern registers — so it makes a stationary ruler
;     to measure the objects against.
;
; (B) The swallowed dot. Fine horizontal motion comes from HMOVE: a write to the
;     HMOVE strobe arms a "more motion" latch for each object and starts a
;     countdown; the latch normally clears when the countdown reaches that
;     object's programmed 4-bit offset, after delivering the right number of
;     extra motion clocks. Rewrite the offset register mid-countdown so the
;     match is dodged and the latch never clears: it then keeps stuffing an
;     extra motion pulse into every line — on a line-fixed grid, one pulse per
;     4 colour clocks — and the missile drifts a fixed step sideways line by
;     line (the Cosmic Ark starfield). Where a stuffed pulse lands on the
;     object's own motion clock the two merge; for one phase of that overlap
;     the missile's 1px dot is swallowed — nothing is serialised at all. The
;     collision tap follows the serial output, so a swallowed dot collides with
;     nothing even while it sits squarely inside a lit region.
;
; The two stages are separate hardware. A model that couples them — shifting
; both by one constant — fails one part or the other.
;
; Part A re-strobes each object across a lit playfield column and records which
; strobe steps collided, as a 6-bit "profile", one bit per step. Each object is
; probed against two such columns, cell A and cell B, which sit at different
; alignments — so the two profiles together pin its first-lit column to a single
; pixel.
;
; Part B jams missile 0's latch and lets the dot drift across a lit playfield
; bar. Each drift line the dot lands at some offset — a "residue" of 0 to 3 —
; within the 4-clock stuffed-pulse grid, and the residue decides what it draws:
; residues 0 and 1 a normal dot, residue 3 a widened 2-clock dot, residue 2
; nothing at all. Each residue is read on its own CXCLR-bracketed line.
;
;   CODE $01/$02 = player  cell A/B profile wrong
;        $03/$04 = missile cell A/B profile wrong
;        $05/$06 = ball    cell A/B profile wrong
;        $11 = parked control latched (a hit where the dot is outside the bar)
;        $12 = residue-0 dot did not latch (an ordinary in-bar dot missed)
;        $13 = residue-1 dot latched (a hit where the dot is outside the bar)
;        $14 = residue-3 dot did not latch (the widened in-bar dot missed)
;        $15 = swallowed residue-2 dot latched (the swallow drew a pixel)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

VEC     = $8A                   ; RAM pointer for the computed jmp (2 bytes)
IDX     = $8C                   ; sweep step 0..5
PNUM    = $8D                   ; next profile slot 0..5
PROF    = $90                   ; 6 profiles: P0 A/B, M0 A/B, BL A/B
S       = $96                   ; S..S+4: part B masked latch samples

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF
        sta COLUP0
        ; NUSIZ0/CTRLPF stay 0: single copies, 1px missile and ball

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; ---- Part A: one 2-cell sweep per object, only that object enabled
        lda #0
        sta PNUM
        lda #$80
        sta GRP0                ; 1px player
        ldy #0                  ; RESP0 / CXP0FB
        jsr sweep_object        ; -> PROF+0 (cell A), PROF+1 (cell B)
        lda #0
        sta GRP0
        lda #$02
        sta ENAM0
        ldy #2                  ; RESM0 / CXM0FB
        jsr sweep_object        ; -> PROF+2, PROF+3
        lda #0
        sta ENAM0
        lda #$02
        sta ENABL
        ldy #4                  ; RESBL / CXBLPF
        jsr sweep_object        ; -> PROF+4, PROF+5
        lda #0
        sta ENABL

        ; field boundary, then part B in a fresh field
        jsr overscan_lines
        jsr vertical_sync
        jsr vblank_lines

        ; ---- Part B: the stuck-drift kernel. M0 parks at x=101, clear of the
        ; bar; jamming the latch (HMOVE at write cycle 3, HMM0 rewritten to $00
        ; at cycle 19, before the countdown can match) then walks the dot 94,
        ; 77, 60, 43, ... (-17 per line, mod 160). The windowed lines, each
        ; CXCLR-bracketed on its own so no neighbouring line leaks in:
        ;   parked control, x=101 outside the bar          -> no collision
        ;   n=2   x=60, residue 0: a normal dot in the bar -> collision
        ;   n=5   x=9,  residue 1: a normal dot outside    -> no collision
        ;   n=11  x=67, residue 3: a widened 2-clock dot   -> collision
        ;   n=12  x=50, residue 2: the swallowed dot       -> no collision
        ; n=12 sits inside the lit bar yet collides with nothing — the swallow,
        ; isolated from an ordinary in-bar hit (n=2) and a widened one (n=11).
        lda #$FF
        sta PF2                 ; bar at x=[48..80) (+ repeat at 128)
        lda #$02
        sta ENAM0

        ; park M0 at x=101 and arm the mover
        sta WSYNC
        lda #$70
        sta HMM0
        SLEEP 47
        sta RESM0

        ; parked control: one clean full line, M0 at 101 (outside both bars)
        sta WSYNC
        sta CXCLR
        sta WSYNC
        lda CXM0FB
        and #$80
        sta S+0                 ; expect $00

        ; jam the latch (drift line n=0 is this line's tail)
        sta WSYNC
        sta HMOVE
        lda #$00
        SLEEP 11
        sta HMM0

        sta WSYNC               ; -> n=1 (77)
        sta WSYNC               ; -> n=2 (60, residue 0, in the bar)
        sta CXCLR               ; hblank of n=2: window covers n=2
        sta WSYNC               ; -> n=3
        lda CXM0FB              ; hblank of n=3: close the n=2 window
        and #$80
        sta S+1                 ; expect $80
        sta WSYNC               ; -> n=4 (26)
        sta WSYNC               ; -> n=5 (9, residue 1, outside the bar)
        sta CXCLR               ; window covers n=5
        sta WSYNC               ; -> n=6
        lda CXM0FB
        and #$80
        sta S+2                 ; expect $00
        sta WSYNC               ; -> n=7 (135)
        sta WSYNC               ; -> n=8 (118)
        sta WSYNC               ; -> n=9 (101)
        sta WSYNC               ; -> n=10 (84)
        sta WSYNC               ; -> n=11 (67, residue 3, 2-CLK dot in bar)
        sta CXCLR               ; window covers n=11
        sta WSYNC               ; -> n=12 (50, residue 2, swallowed in bar)
        lda CXM0FB              ; close the n=11 window...
        and #$80
        sta S+3                 ; expect $80
        sta CXCLR               ; ...and open n=12's in the same hblank
        sta WSYNC               ; -> n=13
        lda CXM0FB
        and #$80
        sta S+4                 ; expect $00: the swallowed dot collides with nothing

        sta WSYNC
        lda #$80
        sta HMM0                ; release the latch

        ; ---- verdict
        ASSERT_EQ PROF+0, $06, $01      ; player  cell A
        ASSERT_EQ PROF+1, $08, $02      ; player  cell B
        ASSERT_EQ PROF+2, $04, $03      ; missile cell A
        ASSERT_EQ PROF+3, $08, $04      ; missile cell B
        ASSERT_EQ PROF+4, $04, $05      ; ball    cell A
        ASSERT_EQ PROF+5, $08, $06      ; ball    cell B
        ASSERT_EQ S+0, $00, $11
        ASSERT_EQ S+1, $80, $12
        ASSERT_EQ S+2, $00, $13
        ASSERT_EQ S+3, $80, $14
        ASSERT_EQ S+4, $00, $15
        PASS_TEST

; ---- Part A machinery ------------------------------------------------------

; sweep_object: Y = register offset (0 = P0, 2 = M0, 4 = BL) — indexes the
; RESP0-family strobe and the CXP0FB-family read alike. Parks the object at
; its step-0 column, then runs the 6-step sweep against each probe cell,
; filling PROF+PNUM and PROF+PNUM+1. Every probe window is opened with CXCLR
; on its own strobe line, so latches from parking/idle lines never leak in.
;
; Geometry. Step s re-strobes 3px on from step s-1: the strobe write completes
; at CPU cycle 36+s, so the first-lit column is x = 44+3s for a missile or the
; ball and x = 45+3s for a player (the player's extra pipeline stage). The two
; probe cells are cell A = PF2 bit 0, x [48,52) and cell B = PF2 bit 1,
; x [52,56). Step pitch 3 and cell width 4 are coprime, so the two cells sit at
; different phases mod 3 and the two profiles together pin the landing to a
; single pixel. The playfield ruler has no reset latency of its own, so a
; latency error shared by every object cannot cancel out. The steps whose
; column falls in the lit cell (bit s set = step s latched):
;   player   cell A: s=1,2 -> $06    cell B: s=3 -> $08
;   missile  cell A: s=2   -> $04    cell B: s=3 -> $08
;   ball     cell A: s=2   -> $04    cell B: s=3 -> $08
sweep_object:
        sta WSYNC
        SLEEP 31
        sta RESP0,y             ; park: completes cycle 36, like step 0
        sta WSYNC
        lda #$01
        sta PF2                 ; probe cell A: x [48,52)
        jsr sweep6
        sta WSYNC
        lda #$02
        sta PF2                 ; probe cell B: x [52,56)
        jsr sweep6
        lda #0
        sta PF2
        rts

; sweep6: six probe steps for the current object and cell. Per step: strobe
; line (slide-timed re-strobe, then CXCLR clears the line's own transients —
; the write lands at CLK 117+3s, after the object's new pixel at <=113+3s),
; one clean full line to latch, then read in the next hblank.
sweep6:
        ldx #0
.step:
        stx IDX
        lda #5
        sec
        sbc IDX                 ; slide entry offset 5-s -> 3+s cycles
        clc
        adc #<Slide
        sta VEC
        lda #>Slide
        adc #0
        sta VEC+1
        sta WSYNC
        jmp (VEC)
Slide:
        .byte $C9,$C9,$C9,$C9,$C9      ; cmp-imm slide: entry Slide+i burns 8-i
        .byte $C5,$EA                   ; cycles (tail: cmp $EA, a zp RAM read)
        SLEEP 23
        sta RESP0,y             ; strobe completes cycle 36+s
        sta CXCLR
        ldx #2
.latch:
        sta WSYNC
        dex
        bne .latch
        lda CXP0FB,y            ; read the object-PF bit in this hblank
        and #$80
        beq .miss
        ldx IDX                 ; hit: set bit s in the current profile
        lda BitTab,x
        ldx PNUM
        ora PROF,x
        sta PROF,x
.miss:
        ldx IDX
        inx
        cpx #6
        bne .step
        inc PNUM
        rts

BitTab:
        .byte $01,$02,$04,$08,$10,$20

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
