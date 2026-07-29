; hmove-reset-merge — a reset strobe and an HMOVE motion pulse landing on the
; same colour clock count once between them, not twice.
;
; Every movable TIA object has a horizontal position counter. It free-runs once
; across each line and decides which column the object is drawn at. Two things
; drive it. Writing a reset strobe — RESBL for the ball — forces the counter to
; wherever the beam is at that moment. Writing HMOVE starts a short burst of
; extra motion clocks, a pulse train that steps the counter once per pulse until
; the object has moved by the amount in its motion register. That train runs on
; every HMOVE, even when the motion register holds $00 and the object finishes
; where it began.
;
; A reset written a few cycles after HMOVE arrives while the train is still
; running, so one of its pulses can fall on the very colour clock the reset
; does. Both act on the same counter bits at the same instant, and the reset
; wins: it forces the counter, and the pulse has nothing left to step, so it is
; swallowed. The counter moves on by one, not by two (hardware-measured:
; real PAL console, 2026-07-26). Treating the two as separate events and
; applying them in turn moves it by two, and leaves the object one column
; to the left of where the hardware puts it.
;
; The ball is the object that shows this, because RESBL also re-triggers the
; ball's start signal, so a swallowed pulse shifts the column it is drawn at.
; After a WSYNC, an HMOVE, and a RESBL three cycles later, the ball lands on
; column 3. The Activision Decathlon uses that run-up and then walks the ball
; three columns left, landing it on column 0 — the flush left-edge bar it draws
; its meter with. Count the swallowed pulse and the ball starts on column 2
; instead, so the same walk carries it off the screen and round to column 159.
;
; The test repeats that run-up and walks the ball across a fixed playfield
; marker, looking for the motion value at which it steps off the marker's edge.
; A counted pulse moves that crossing by one value.
;
;   CODE $01 = the ball did not land on column 3: walking it left, it stepped
;              off the marker at the wrong motion value
;        $02 = the same error walking it right, at the marker's far edge
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PROFILE = $90                   ; 2-byte collision bitfield ($90 lo, $91 hi)

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$0E
        sta COLUPF              ; colour is irrelevant to the collision latch
        lda #$30
        sta PF0                 ; the marker: playfield columns 0-7. The half
                                ; repeats unreflected, so columns 80-87 light
                                ; too, which the ball never reaches.
        lda #$00
        sta PF1
        sta PF2
        sta CTRLPF              ; ball width 1px; no reflect, score or priority
        lda #$02
        sta ENABL               ; ball on for the whole sweep

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        lda #$00
        sta PROFILE
        sta PROFILE+1

        ; One pass per motion value. A motion register holds a signed amount in
        ; its high nibble, positive moving the object left, so the 16 values
        ; walk the ball off both ends of the marker and each crossing pins the
        ; landing column from one side:
        ;
        ;   HMBL   $00 $10 $20 $30 $40 $50 $60 $70   $80 $90 $A0 $B0 $C0 $D0 $E0 $F0
        ;   motion   0  +1  +2  +3  +4  +5  +6  +7    -8  -7  -6  -5  -4  -3  -2  -1
        ;   column   3   2   1   0 159 158 157 156    11  10   9   8   7   6   5   4
        ;   on 0-7   Y   Y   Y   Y   .   .   .   .     .   .   .   .   Y   Y   Y   Y
        ;
        ; Each answer is one bit of PROFILE, so a correct landing reads $0F low
        ; and $F0 high. Counting the swallowed pulse starts the ball on column 2,
        ; sliding every column along one and reading $07 / $F8 instead.
        ldx #0                  ; X = motion value index, held across the loop
.hmloop:
        txa                     ; this pass's HMBL value ($00,$10,..,$F0)
        asl
        asl
        asl
        asl
        tay
        sta HMCLR               ; motion registers zero, so the run-up's train
                                ; moves the ball nowhere and only the swallowed
                                ; pulse is left to see

        ; The run-up. These strobes must stay inline and WSYNC-anchored: the
        ; coincidence being measured is one colour clock wide.
        sta WSYNC
        sta HMOVE               ; cycles 0-2: starts the motion pulse train
        sta RESBL               ; cycles 3-5: lands on a pulse, which is swallowed
        SLEEP 25                ; let the train finish: an HMBL write mid-train
        sty HMBL                ; would jam the motion latch

        sta WSYNC
        sta HMOVE               ; walk the ball by this pass's motion value

        ; Measure. No HMOVE on these lines, so no comb blanks the ball away.
        sta WSYNC
        sta CXCLR               ; clear, then two settled lines to latch on
        sta WSYNC
        sta WSYNC
        lda CXBLPF
        and #$80                ; CXBLPF bit 7 = ball overlaps playfield
        beq .next               ; off the marker: leave this pass's bit clear

        txa                     ; on the marker: set this pass's bit
        and #$07
        tay
        lda Bit,y
        cpx #8                  ; values $00-$70 -> low byte, $80-$F0 -> high
        bcc .lo
        ora PROFILE+1
        sta PROFILE+1
        jmp .next
.lo:
        ora PROFILE
        sta PROFILE
.next:
        inx
        cpx #16
        bne .hmloop

        ASSERT_EQ PROFILE,   $0F, $01   ; steps off between $30 and $40
        ASSERT_EQ PROFILE+1, $F0, $02   ; steps back on between $B0 and $C0

        PASS_TEST

Bit:
        .byte $01,$02,$04,$08,$10,$20,$40,$80

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
