; pa7-edge — a PA7 pin transition of the armed polarity sets the RIOT's edge
; flag; reading the flag register clears it.
;
; The RIOT (the 6532 "RAM-I/O-Timer" chip) carries the console's two parallel
; I/O ports alongside its RAM and interval timer. Bit 7 of port A (the pin named
; PA7) has a dedicated edge detector: a transition of the configured polarity
; latches bit 6 of the interrupt flag register (named TIMINT), and reading
; TIMINT clears that flag while leaving the timer flag (bit 7) untouched — the
; timer flag clears only on a timer read or write. The polarity is chosen by the
; WRITE address, not by the data written: a write to $284 arms the negative
; (high->low) edge, a write to $285 the positive (low->high) edge. (Address bit
; A1 would enable the chip's IRQ pin, which the 2600 does not wire up; the flag
; latches regardless.) A select write never sets the flag itself (pa7-polarity
; pins this down); the TIMINT read after each arming clears any pre-existing
; flag state.
;
; PA7 is normally a joystick input, but with the port-A direction register
; (SWACNT) bit 7 set to OUTPUT the pin follows the port-A output register
; (SWCHA). The detector watches the pin itself, so an edge the CPU makes by
; writing SWCHA counts — no controller plugged in. The test drives PA7 high and
; low under both polarity settings and samples TIMINT after each move.
;
;   CODE $01 = negative armed and no edge has happened, yet the flag is set
;        $02 = PA7 went high->low with negative armed, but the flag did not set
;        $03 = reading TIMINT did not clear the PA7 flag
;        $04 = PA7 low->high under negative arming set the flag (wrong direction)
;        $05 = PA7 high->low under positive arming set the flag (wrong direction)
;        $06 = PA7 low->high with positive armed, but the flag did not set
;        $07 = timer underflow plus a fresh PA7 edge: the first read did not
;              show both flags set (timer and PA7)
;        $08 = the second read did not show the timer flag alone still set (a
;              TIMINT read clears the PA7 flag, not the timer flag)
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

PA7_NEG = $0284                 ; write: arm negative (high->low) edge detect
PA7_POS = $0285                 ; write: arm positive (low->high) edge detect

S       = $90                   ; S..S+7: masked TIMINT samples

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        lda #$80
        sta SWACNT              ; PA7 = output, PA0-6 = inputs
        sta SWCHA               ; drive PA7 pin high

        sta PA7_NEG             ; arm negative-edge detect (data ignored)
        lda TIMINT              ; clear any power-on or leftover flag state
        lda TIMINT
        and #$40                ; keep the PA7 flag only: bit 7 (the timer flag)
                                ;   is undefined until the first timer write
        sta S+0                 ; armed, no edge yet -> expect $00

        lda #$00
        sta SWCHA               ; PA7 high -> low: the armed negative edge
        lda TIMINT
        and #$40
        sta S+1                 ; expect $40 (this read also clears the flag)

        lda TIMINT
        and #$40
        sta S+2                 ; the previous read cleared it -> expect $00

        lda #$80
        sta SWCHA               ; PA7 low -> high: wrong polarity while NEG armed
        lda TIMINT
        and #$40
        sta S+3                 ; expect $00

        sta PA7_POS             ; re-arm for positive edges
        lda TIMINT              ; defensive clear (arming sets no flag)
        lda #$00
        sta SWCHA               ; PA7 high -> low: wrong polarity while POS armed
        lda TIMINT
        and #$40
        sta S+4                 ; expect $00

        lda #$80
        sta SWCHA               ; PA7 low -> high: the armed positive edge
        lda TIMINT
        and #$40
        sta S+5                 ; expect $40 (this read clears the PA7 flag)

        ; --- independence from the timer flag: underflow the timer (never
        ;     reading INTIM, so bit 7 stays set), raise a fresh PA7 edge, then
        ;     read TIMINT twice and watch the two flags clear separately
        lda #$02
        sta TIM1T               ; timer = 2 at /1 -> underflows within a few cycles
        SLEEP 10                ; let it run past underflow: timer flag now set
        lda #$00
        sta SWCHA               ; PA7 high -> low (POS armed: no PA7 flag)
        lda #$80
        sta SWCHA               ; PA7 low -> high: the armed positive edge
        lda TIMINT
        and #$C0
        sta S+6                 ; expect $C0: timer flag + PA7 flag together
        lda TIMINT
        and #$C0
        sta S+7                 ; expect $80: PA7 flag cleared by the read, timer stays

        ASSERT_EQ S+0, $00, $01
        ASSERT_EQ S+1, $40, $02
        ASSERT_EQ S+2, $00, $03
        ASSERT_EQ S+3, $00, $04
        ASSERT_EQ S+4, $00, $05
        ASSERT_EQ S+5, $40, $06
        ASSERT_EQ S+6, $C0, $07
        ASSERT_EQ S+7, $80, $08
        PASS_TEST

        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
