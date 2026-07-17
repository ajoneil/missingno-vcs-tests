; reset-phase — a position-reset strobe must land its object correctly at every
; strobe phase, not only the phase a model was tuned for.
;
; Each of the TIA's movable objects — the two players, the two missiles, and the
; ball — carries a horizontal position counter that free-runs once across every
; line and decides which column the object is drawn at. Writing the object's
; reset strobe (RESP0 for player 0, RESM0 for missile 0, RESBL for the ball)
; snaps that counter so the object is redrawn at the beam's current position. The
; counter is stepped by its own private divide-by-four two-phase clock, and the
; strobe does more than reload a number: it re-phases that little clock to the
; exact colour clock the strobe fell on. (A colour clock is one TIA pixel; the
; 6507 runs at one third of that rate, so a single CPU cycle spans three colour
; clocks.) Because the re-phasing resolves to one colour clock, the object's
; first-lit column follows the precise strobe sub-cycle — three strobe timings
; that share the same CPU cycle can still land the object on three columns.
;
; A model that instead reloads the counter with one fixed reset-to-draw delay,
; blind to that sub-cycle phase, lands correctly at the phases its constant was
; fitted to and one colour clock off at the others. A test that only ever strobes
; at a single phase never sees the error. The same off-by-one is what makes the
; game Surround report a false collision between a player and a wall.
;
; The test pins each object against a "wall" of playfield: PF0/PF1 bits, which
; are drawn at fixed screen columns and are untouched by any reset, so the wall
; is a stationary ruler. After a few settled lines it reads the object-versus-
; playfield collision latch — the TIA sets that latch's top bit (D7) the instant
; the object and the playfield are both lit on the same pixel (CXP0FB for the
; player, CXM0FB for the missile, CXBLPF for the ball). Each object is checked at
; two strobe phases:
;   Control — the strobe is written during horizontal blank (HBLANK, the off-
;     screen span before each visible line). A reset there is clamped to the
;     start of the visible line whatever the exact cycle, so its landing is
;     phase-insensitive; the wall is placed so the object lands on it and the
;     latch must fire — proving the object really renders and the latch is armed.
;   Probe — the strobe is written in the visible region (around beam column 90,
;     the neighbourhood where Surround strobes). Here the wall's rightmost column
;     sits one column left of a correct landing's first-lit column, so a correct
;     landing clears the wall and the latch must not fire; a landing one column
;     short reaches back onto the wall's rightmost column and latches — the
;     Surround misfire in miniature.
;
; The divergence appears only at one specific strobe timing — the one a short,
; straight-line run-up (Surround's own) happens to land on.
;
;   CODE $01/$03/$05 = P0/M0/BL HBLANK control did not latch (the object never
;                      rendered, or the collision latch was not armed)
;        $02/$04/$06 = P0/M0/BL visible probe latched (the reset landed one
;                      column short and caught the wall — the Surround defect)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

R       = $90                   ; R..R+5: the six masked latch samples

        org $F000

Reset:
        ; Do not replace this with CLEAN_START. The divergence lives at one
        ; specific strobe global-clock phase — the one Surround hits with its
        ; brief kernel preamble — and a ~2600-cycle RAM/stack clear
        ; (CLEAN_START, or any 256-iteration loop) walks every strobe below
        ; onto a correct-landing phase, where the test passes no matter what the
        ; model does. A spurious pass is the failure mode to guard against here,
        ; so this init deliberately zeroes only what the test uses, with
        ; straight-line stores, and stays short.
        sei
        cld
        lda #$00
        sta VBLANK
        sta COLUBK
        sta CTRLPF             ; ball width 1, reflect off
        sta PF0
        sta PF1
        sta PF2
        sta NUSIZ0             ; missile width 1
        sta HMP0
        sta HMP1
        sta HMM0
        sta HMBL
        sta GRP1
        sta ENAM0
        sta ENABL
        TEST_BEGIN

        lda #$0E
        sta COLUP0              ; player + missile colour
        sta COLUPF              ; wall + ball colour

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; Every strobe below is written inline, straight off a fresh WSYNC: sta
        ; WSYNC, a fixed run of NOPs, sta RESx. Do not fold these into a loop, a
        ; computed jump or an indexed store to shorten them — any of those shifts
        ; the strobe's sub-cycle phase off the fault, and the test then passes
        ; regardless of the model. The repetition below is the test.
        ;
        ; Geometry (visible-pixel columns). The player draws GRP0=$0F, whose four
        ; low bits are its four lit pixels; the missile and ball are a single
        ; pixel. The control strobe waits 8 NOPs after WSYNC, the probe 15 (the
        ; missile and ball probes add a 3-cycle BIT so their strobe meets the same
        ; fault phase). The walls, and what a correct landing does at each:
        ;   P0 control  PF0=$20  cols 4-7    first-lit column 7, on the wall -> latch
        ;   P0 probe    PF1=$04  cols 36-39  correct landing clears the wall; one
        ;                                    column short lands on col 39 -> latch
        ;   M0/BL ctrl  PF0=$10  cols 0-3    object pixel on the wall -> latch
        ;   M0/BL probe PF1=$02  cols 40-43  correct landing clears the wall; one
        ;                                    column short lands on col 43 -> latch

        ; ---- Player (GRP0=$0F): control then probe -----------------------
        lda #$0F
        sta GRP0

        ; #1 P0 HBLANK control: 8 NOP strobe, wall cols 4-7, must latch
        sta WSYNC
        REPEAT 8
        nop
        REPEND
        sta RESP0
        sta WSYNC
        sta CXCLR
        lda #$20
        sta PF0                 ; wall cols 4-7
        jsr draw6
        lda CXP0FB
        and #$80                ; keep D7 = object-vs-playfield collision
        sta R+0
        lda #$00
        sta PF0

        ; #2 P0 visible probe: 15 NOP strobe, wall cols 36-39, must not latch
        sta WSYNC
        REPEAT 15
        nop
        REPEND
        sta RESP0
        sta WSYNC
        sta CXCLR
        lda #$04
        sta PF1                 ; wall cols 36-39
        jsr draw6
        lda CXP0FB
        and #$80                ; keep D7 = object-vs-playfield collision
        sta R+1
        lda #$00
        sta PF1
        sta GRP0                ; player off

        ; ---- Missile (ENAM0) ---------------------------------------------
        lda #$02
        sta ENAM0

        ; #3 M0 HBLANK control: 8 NOP strobe, wall cols 0-3, must latch
        sta WSYNC
        REPEAT 8
        nop
        REPEND
        sta RESM0
        sta WSYNC
        sta CXCLR
        lda #$10
        sta PF0                 ; wall cols 0-3
        jsr draw6
        lda CXM0FB
        and #$80                ; keep D7 = object-vs-playfield collision
        sta R+2
        lda #$00
        sta PF0

        ; #4 M0 visible probe: 15 NOP + BIT strobe, wall cols 40-43, must not latch
        sta WSYNC
        REPEAT 15
        nop
        REPEND
        bit RESULT              ; 3-cycle phase pad (reads $00, harmless)
        sta RESM0
        sta WSYNC
        sta CXCLR
        lda #$02
        sta PF1                 ; wall cols 40-43
        jsr draw6
        lda CXM0FB
        and #$80                ; keep D7 = object-vs-playfield collision
        sta R+3
        lda #$00
        sta PF1
        sta ENAM0               ; missile off

        ; ---- Ball (ENABL) ------------------------------------------------
        lda #$02
        sta ENABL

        ; #5 BL HBLANK control: 8 NOP strobe, wall cols 0-3, must latch
        sta WSYNC
        REPEAT 8
        nop
        REPEND
        sta RESBL
        sta WSYNC
        sta CXCLR
        lda #$10
        sta PF0                 ; wall cols 0-3
        jsr draw6
        lda CXBLPF
        and #$80                ; keep D7 = object-vs-playfield collision
        sta R+4
        lda #$00
        sta PF0

        ; #6 BL visible probe: 15 NOP + BIT strobe, wall cols 40-43, must not latch
        sta WSYNC
        REPEAT 15
        nop
        REPEND
        bit RESULT              ; 3-cycle phase pad
        sta RESBL
        sta WSYNC
        sta CXCLR
        lda #$02
        sta PF1                 ; wall cols 40-43
        jsr draw6
        lda CXBLPF
        and #$80                ; keep D7 = object-vs-playfield collision
        sta R+5
        lda #$00
        sta PF1
        sta ENABL               ; ball off

        ; ---- verdict -----------------------------------------------------
        ASSERT_EQ R+0, $80, $01   ; P0 control latches
        ASSERT_EQ R+1, $00, $02   ; P0 probe clears
        ASSERT_EQ R+2, $80, $03   ; M0 control latches
        ASSERT_EQ R+3, $00, $04   ; M0 probe clears
        ASSERT_EQ R+4, $80, $05   ; BL control latches
        ASSERT_EQ R+5, $00, $06   ; BL probe clears
        PASS_TEST

; Six settled beam-on lines: enough for the static object+wall to latch. The
; object holds its strobed position (no HMOVE) and the wall is beam-decoded, so
; every line draws the same overlap.
draw6:
        ldx #6
.d:     sta WSYNC
        dex
        bne .d
        rts

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
