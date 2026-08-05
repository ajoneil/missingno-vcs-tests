; resp-restrobe — RESP0/RESP1 strobed alternately every 3 CPU cycles
; multiplies each player across the scanline: every strobe after a
; player's first delivers a copy of the graphic starting 5 clocks
; after itself, each player's first strobe of the line delivers
; nothing, and the copies the last strobe leaves in flight run out at
; the NUSIZ close-copy pitch. Real PAL console, 2026-08-05.
;
; The TIA (the console's video chip) has no frame memory: it draws
; each scanline live. A player has no position register. A counter
; free-runs across the line — clocked only outside horizontal
; blanking, it gains exactly one period per line, so a parked player
; redraws at a fixed column — and writing RESP0/RESP1 replants it at
; the beam's column. The reset draws nothing by itself: copies are
; delivered by the counter's copy decodes, each armed a few clocks
; ahead of its first pixel.
;
; Strobed every 18 clocks, the counter re-enters the close-copy decode
; inside every strobe interval, so each reset after the first lands
; with a delivery already in flight. The delivery rides through the
; reset (merge-delivery-replant pins that rule at single landings) and
; emerges 5 clocks after the reset, shifted off its natural column. A
; player's first strobe finds its counter mid-period with nothing
; armed, so it only replants the counter.
;
; Games and demos multiply sprites this way. A model that instead
; treats RESPx as "latch a position, place the NUSIZ copies from it"
; (last write wins) draws only the final strobe's copies and leaves
; the left of the line empty.
;
; The test locks that cadence — five strobes per player per line — and
; reads which columns were drawn through the player-playfield
; collision latches, against a single lit playfield cell per probe.
; Parked-player controls prove each probe cell's geometry from both
; sides.
;
;   CODE $01 = player 0 parked where a position-latching model puts it
;              touched the mid-burst probe (probe geometry broken)
;        $02 = player 0's mid-burst copy is missing from the cadence
;              line (each reset must deliver the copy in flight)
;        $03 = player 0 parked on the probe cell was not seen
;              (positive control)
;        $04 = player 1 parked where a position-latching model puts it
;              touched the mid-burst probe
;        $05 = player 1's mid-burst copy is missing
;        $06 = player 1 parked on the probe cell was not seen
;              (positive control)
;        $07 = player 1 parked at the first strobe's column was not
;              seen (positive control for $08)
;        $08 = a copy was delivered at the line's first strobe (nothing
;              is in flight there; the strobe must only replant)
;        $09 = player 0 parked one strobe short of the probe was not
;              seen (positive control for $0A)
;        $0A = the mid-burst copy landed at its natural column instead
;              of 5 clocks after the reset (the ride-through must
;              shift it)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

S       = $90                   ; S..S+9: masked collision samples

; Ten alternating resets at 3-cycle cadence, entered 22 cycles into the
; line: write ends at clock 75 and every 9 clocks per player after it.
; All strobes inline off a fresh WSYNC (see reset-phase).
    MAC CADENCE_STROBES
        sta RESP0               ; write ends cycle 25 -> clock 75
        sta RESP1               ; 28 -> 84
        sta RESP0               ; 31 -> 93
        sta RESP1               ; 34 -> 102
        sta RESP0               ; 37 -> 111
        sta RESP1               ; 40 -> 120
        sta RESP0               ; 43 -> 129
        sta RESP1               ; 46 -> 138
        sta RESP0               ; 49 -> 147
        sta RESP1               ; 52 -> 156
    ENDM

; Three warm-up cadence lines lock the counters' phase, then one more
; cadence line under a latch cleared in its horizontal blank; the latch
; is read in the next blank, so it reflects that line's draws only.
; {1} latch register, {2} sample cell.
    MAC CADENCE_MEASURE
        REPEAT 3
        sta WSYNC
        SLEEP 22
        CADENCE_STROBES
        REPEND
        sta WSYNC
        sta CXCLR               ; blank: the measured window opens
        SLEEP 19
        CADENCE_STROBES
        sta WSYNC
        lda {1}
        and #$80
        sta {2}
    ENDM

; Park one player with a single mid-line reset, let a line settle, then
; read one steady line under a clean latch. {1} SLEEP before the park
; strobe (write ends cycle {1}+3), {2} reset strobe, {3} latch register,
; {4} sample cell.
    MAC PARK_MEASURE
        sta WSYNC
        SLEEP {1}
        sta {2}
        sta WSYNC               ; the parked pattern settles
        sta WSYNC
        sta CXCLR               ; blank: this line draws steady state
        sta WSYNC
        lda {3}
        and #$80
        sta {4}
    ENDM

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$03
        sta NUSIZ0              ; three copies close, both players
        sta NUSIZ1
        lda #$F0
        sta GRP0                ; 4-pixel block per copy
        sta GRP1
        lda #$0E
        sta COLUP0              ; cosmetic; the collision matrix
        sta COLUP1              ; ignores colour
        sta COLUPF              ; (CTRLPF=0: playfield repeats, so a
                                ; cell also lights 80 clocks right)

        jsr vertical_sync
        jsr vblank_lines        ; beam on

        ; ---- player 0: the mid-burst copy at 48-51 ------------------------
        ; Probe PF2 bit 0: cells 48-51 and 128-131. Player 0's cadence
        ; copies (30/48/66/84/100/116) touch it only through the strobed
        ; copy at 48-51; parked at the final strobe's position (copies
        ; 84/100/116 — all a position-latching model draws) it stays
        ; clear of both cells.
        lda #$01
        sta PF2
        sta WSYNC
        SLEEP 46
        sta RESP0               ; park player 0: write ends clock 147
        PARK_MEASURE 49, RESP1, CXP0FB, S+0     ; park player 1 at 156;
                                                ; expect $00: the final
                                                ; position misses the probe
        CADENCE_MEASURE CXP0FB, S+1             ; expect $80: the strobed
                                                ; copy at 48-51
        PARK_MEASURE 34, RESP0, CXP0FB, S+2     ; park at 111 -> copy on
                                                ; the probe: expect $80

        ; ---- player 1: the mid-burst copy at 39-42 ------------------------
        ; Probe PF1 bit 1: cells 40-43 and 120-123. Player 1's cadence
        ; copies (39/57/75/93/109/125) touch it only at 40-42.
        lda #$00
        sta PF2
        lda #$02
        sta PF1
        PARK_MEASURE 49, RESP1, CXP1FB, S+3     ; park at 156: expect $00
        CADENCE_MEASURE CXP1FB, S+4             ; expect $80: the strobed
                                                ; copy at 39-42
        PARK_MEASURE 31, RESP1, CXP1FB, S+5     ; park at 102: expect $80

        ; ---- the first strobe delivers nothing ----------------------------
        ; Probe PF1 bit 6: cells 20-23 and 100-103. Player 1's first
        ; cadence strobe ends at clock 84; a copy delivered there would
        ; light 21-24. No cadence copy touches either cell.
        lda #$40
        sta PF1
        PARK_MEASURE 25, RESP1, CXP1FB, S+6     ; park at 84 -> a player
                                                ; genuinely at 21-24 hits
                                                ; the probe: expect $80
        CADENCE_MEASURE CXP1FB, S+7             ; expect $00: the first
                                                ; strobe plants nothing

        ; ---- the delivery shifts to strobe+5 ------------------------------
        ; Probe PF1 bit 0: cells 44-47 and 124-127. The close-copy start
        ; armed by player 0's reset at 93 would naturally deliver at
        ; 46-49; the reset at 111 carries it to 48-51 instead, one clock
        ; clear of the cell.
        lda #$01
        sta PF1
        PARK_MEASURE 32, RESP0, CXP0FB, S+8     ; park at 105 -> copy at
                                                ; 42-45 hits the probe:
                                                ; expect $80
        CADENCE_MEASURE CXP0FB, S+9             ; expect $00: 44-47 dark

        ; ---- verdict ------------------------------------------------------
        ASSERT_EQ S+0, $00, $01
        ASSERT_EQ S+1, $80, $02
        ASSERT_EQ S+2, $80, $03
        ASSERT_EQ S+3, $00, $04
        ASSERT_EQ S+4, $80, $05
        ASSERT_EQ S+5, $80, $06
        ASSERT_EQ S+6, $80, $07
        ASSERT_EQ S+7, $00, $08
        ASSERT_EQ S+8, $80, $09
        ASSERT_EQ S+9, $00, $0A
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
