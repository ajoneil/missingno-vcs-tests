; reset-same-line — strobing the ball's RESBL mid-line draws the ball on that
; same line; strobing a missile's RESMx moves it but draws nothing until the
; next line.
;
; The TIA draws its movable objects — two players, two missiles, one ball — from
; per-object position counters that advance as the beam sweeps a scanline.
; Writing an object's reset strobe (RESBL for the ball, RESM0 for missile 0)
; snaps that counter to the beam's current column, which becomes the object's
; new horizontal position. For the ball the reset does double duty as a draw
; trigger: the strobe itself starts a scan, so the ball appears at its new
; column on the very line the strobe happened. A missile's reset only moves the
; counter — it plants no draw. The missile stays dark for the rest of the strobe
; line and first appears when its counter next wraps back to the object's start,
; on the following line. The asymmetry is intrinsic to the two objects' reset
; logic and holds at every column alignment.
;
; The test reads the asymmetry out through the TIA's collision latches. Each
; pair of objects that can overlap has a sticky latch: a single overlapping
; pixel sets it, and it stays set until a write to CXCLR clears it. A wide
; playfield bar (PF2 = $FF) lights x=[48..80) as a fixed backdrop to collide
; with; the ball-vs-playfield latch is CXBLPF bit 7, the missile-vs-playfield
; latch is CXM0FB bit 7. (Horizontal blank below means the off-screen span at
; the start of each scanline, before the visible 160 pixels.)
;
; For each object the test runs three lines:
;   negative control — park the object at x=95, OUTSIDE the bar, and confirm a
;       full parked line sets no latch (proves the geometry: parked here it
;       never touches the bar).
;   strobe line — clear the latch during horizontal blank, then strobe the reset
;       mid-line so the new column x=65 lands INSIDE the bar. The latch is read
;       in the NEXT line's horizontal blank, so it reflects only whether the
;       reset itself drew on the strobe line.
;   positive control — a following steady line at the new column, which must set
;       the latch (proves the object does draw at x=65 once settled).
; The ball must latch on its strobe line; the missile must not.
;
;   CODE $01 = ball parked outside the bar still latched (geometry broken)
;        $02 = ball strobe line: no draw at the new column (a mid-line reset
;              must start a scan on the same line)
;        $03 = ball steady state at the new column missing (positive control)
;        $04 = missile parked outside the bar still latched (geometry broken)
;        $05 = missile strobe line: DREW at the new column (a missile's first
;              draw belongs to the next line's counter wrap, not the reset)
;        $06 = missile steady state at the new column missing (positive control)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

S       = $90                   ; S..S+5: masked collision samples

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$FF
        sta PF2                 ; bar at x=[48..80) (+ right-half repeat at [128..160))
        lda #$0E
        sta COLUPF              ; (CTRLPF=0: 1px ball, playfield not reflected)

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; ---------- phase 1: ball ----------
        lda #$02
        sta ENABL

        sta WSYNC
        SLEEP 50
        sta RESBL               ; park BL at x=95, outside both bars
        sta WSYNC               ; one steady parked line
        sta CXCLR
        sta WSYNC               ; a full parked line under a clean latch
        lda CXBLPF
        and #$80
        sta S+0                 ; expect $00: parked ball touches no PF

        sta WSYNC
        sta CXCLR               ; hblank: latch window opens on the strobe line
        SLEEP 37
        sta RESBL               ; mid-line reset: new column x=65, in the bar
        sta WSYNC
        lda CXBLPF              ; hblank of the next line: window closes before
        and #$80                ; steady-state drawing can reach the bar
        sta S+1                 ; expect $80: the reset drew same-line

        sta CXCLR
        sta WSYNC               ; one steady line at the new column
        lda CXBLPF
        and #$80
        sta S+2                 ; expect $80: steady-state control
        lda #$00
        sta ENABL

        ; ---------- phase 2: missile M0, identical geometry ----------
        lda #$02
        sta ENAM0

        sta WSYNC
        SLEEP 50
        sta RESM0               ; park M0 at x=95
        sta WSYNC
        sta CXCLR
        sta WSYNC
        lda CXM0FB
        and #$80
        sta S+3                 ; expect $00: parked missile touches no PF

        sta WSYNC
        sta CXCLR
        SLEEP 37
        sta RESM0               ; mid-line reset: new column x=65
        sta WSYNC
        lda CXM0FB
        and #$80
        sta S+4                 ; expect $00: no same-line draw for a missile

        sta CXCLR
        sta WSYNC
        lda CXM0FB
        and #$80
        sta S+5                 ; expect $80: steady-state control

        ASSERT_EQ S+0, $00, $01
        ASSERT_EQ S+1, $80, $02
        ASSERT_EQ S+2, $80, $03
        ASSERT_EQ S+3, $00, $04
        ASSERT_EQ S+4, $00, $05
        ASSERT_EQ S+5, $80, $06
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
