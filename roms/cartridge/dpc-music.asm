; dpc-music — the DPC's music mode, clocked deterministically off the read strobe.
;
; The DPC ("Display Processor Chip", Pitfall II) can put its three high fetchers
; DF5-DF7 into "music mode". Then the low counter becomes a free-running 8-bit
; down-counter that reloads from Top after passing 0 (period Top+1 clocks); the
; flag logic keeps running (set at counter==Top, reset at counter==Bottom) and its
; output becomes a square wave, SINx; and the three square waves are summed through
; a fixed weighting into an amplitude the CPU reads at $F004. Pitfall II pokes that
; amplitude to AUDV0 once per line to make its music (US Patent 4,644,495 Fig. 6).
;
; Music mode is entered by setting D4=1 in a counter-high write ($F05D-$F05F).
; Two further quirks (patent, all references agree):
;   - a counter-low write loads Top, not the value written (so a game restarts a
;     voice's phase by writing any byte to counter-low);
;   - D5 in the counter-high write selects the clock: 0 = the fetcher's own read
;     strobe (any read of its $008-$03F window), 1 = the internal RC oscillator.
;
; This ROM sets D5=0 everywhere, so the read strobe is the clock: each read of a
; music fetcher's window is one clock, and the whole voice follows from the
; instruction stream. Absolute pitch is never asserted, and the RC oscillator
; (D5=1) is avoided entirely, because it has no pitch to assert: its frequency
; comes from a 5% resistor on the cart board and a capacitor on the DPC die, so it
; varies with the part, with die process spread, and — the oscillator node being
; very high impedance — with a finger near the board. It differs cart to cart.
; The patent's 42 kHz is a preferred embodiment over a stated 15-80 kHz range, not
; a value a chip must hit; do not assert it. Timbre and voice state are what this
; ROM pins down, and D5=0 makes them exact.
;
; The read-strobe clock (D5=0) is specified in the patent but unused by
; Pitfall II, untested on hardware.
;
;   CODE $01 = counter-low write did not load Top — the first flag read after a
;              music-mode counter-low write must see counter==Top ($FF); a model
;              that loaded the written value ($C0) reads $00.
;        $02 = down-count / flag pattern wrong — counting down from Top the flag
;              must stay set to Bottom+1 then reset at Bottom.
;        $03 = reload-from-Top wrong — past 0 the counter must reload to Top and
;              the flag pattern must repeat with period Top+1.
;        $04 = mixer amplitude wrong — $F004 low nibble must equal the table
;              {0,4,5,9,6,10,11,15} indexed by {DF7,DF6,DF5} SINx states.
;        $05 = music-off did not silence a voice — clearing D4 must force that
;              fetcher's SINx to 0 and drop its weight out of $F004.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8
HOTSPOT1 = $FFF9

; The amplitude is sampled at $F004 only. That port does not strobe DF5-7 on the
; patent model, so parked voice states persist across a sample; $F005-$F007 would
; strobe DF5-7 on some implementations and are never read, nor is $F000-$F003
; (RNG). Draw-line stays disabled (DF4 D4 never set, MOVAMT never written), so
; the $F004 high nibble is 0 and each cell asserts the full byte.
AMPL     = $F004             ; read mixer amplitude (low nibble); never $F005-$F007
FLAG     = $F038             ; read DFx flag: $FF set / $00 clear (one music clock)
TOP      = $F040             ; write DFx Top
BOTTOM   = $F048             ; write DFx Bottom
CLOW     = $F050             ; write DFx counter low (music mode: loads Top)
CHIGH    = $F058             ; write DFx counter high (+D4 music, +D5 clock-select)

V1       = $90
V2       = $91
V3       = $92
V4       = $93
V5       = $94
V6       = $95

ENTRY    = $F080

        MAC ENTRYSTUB
        bit HOTSPOT0
        jmp Main
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        ds 128                 ; DPC register window: no code/vectors
        ENTRYSTUB              ; ENTRY ($F080)
Main:
        CLEAN_START
        TEST_BEGIN

        ; --- cell 01: a counter-low write loads Top (music mode).
        ; Enable DF5 music with D5=0 (read-strobe clock): $F05D = $10 (D4=1,
        ; D5=0, high bits 0). Top=$05, Bottom=$02. Writing counter-low = $C0
        ; must load Top ($05), not $C0. The very next flag read ($F03D, itself
        ; one clock) evaluates counter==Top -> sets the flag -> $FF. Had the
        ; write loaded $C0 (neither Top nor Bottom) the flag would stay clear.
        lda #$10
        sta CHIGH+5           ; $F05D: DF5 music on, read-strobe clock
        lda #$05
        sta TOP+5             ; Top = $05 (also clears the flag)
        lda #$02
        sta BOTTOM+5          ; Bottom = $02
        lda #$C0
        sta CLOW+5            ; music mode: loads Top ($05), not $C0
        lda FLAG+5            ; counter $05 == Top -> flag sets -> $FF; counter -> $04
        sta V1
        ASSERT_EQ V1, $FF, $01

        ; --- cell 02: strobe the counter down; the flag holds set to Bottom+1
        ; then resets at Bottom. Continuing from counter $04 (flag set):
        ;   $04 set  $03 set  $02==Bottom reset  $01 reset  $00 reset (-> reload)
        lda FLAG+5           ; counter $04 -> FF; counter -> $03
        sta V1
        lda FLAG+5           ; counter $03 -> FF; counter -> $02
        sta V2
        lda FLAG+5           ; counter $02 == Bottom -> reset $00; counter -> $01
        sta V3
        lda FLAG+5           ; counter $01 -> $00; counter -> $00
        sta V4
        lda FLAG+5           ; counter $00 -> $00; counter -> reload Top $05
        sta V5
        ASSERT_EQ V1, $FF, $02
        ASSERT_EQ V2, $FF, $02
        ASSERT_EQ V3, $00, $02
        ASSERT_EQ V4, $00, $02
        ASSERT_EQ V5, $00, $02

        ; --- cell 03: past 0 the counter reloaded to Top; one full second
        ; period must repeat the pattern (period Top+1 = 6):
        ;   $05==Top set  $04 set  $03 set  $02==Bottom reset  $01 reset  $00 reset
        lda FLAG+5           ; counter $05 == Top -> FF; counter -> $04
        sta V1
        lda FLAG+5           ; counter $04 -> FF; counter -> $03
        sta V2
        lda FLAG+5           ; counter $03 -> FF; counter -> $02
        sta V3
        lda FLAG+5           ; counter $02 == Bottom -> $00; counter -> $01
        sta V4
        lda FLAG+5           ; counter $01 -> $00; counter -> $00
        sta V5
        lda FLAG+5           ; counter $00 -> $00; counter -> reload Top $05
        sta V6
        ASSERT_EQ V1, $FF, $03
        ASSERT_EQ V2, $FF, $03
        ASSERT_EQ V3, $FF, $03
        ASSERT_EQ V4, $00, $03
        ASSERT_EQ V5, $00, $03
        ASSERT_EQ V6, $00, $03

        ; --- cell 04: mixer amplitude table, indexed by {DF7,DF6,DF5} SINx.
        ; table = 0,4,5,9,6,10,11,15. A music-off fetcher contributes 0, so an
        ; index bit is realised by music-enabling that voice and parking its flag
        ; set (counter-low write -> Top, then one own-window read lands on Top).
        ; $F004 does not strobe DF5-7 (patent), so parked states persist.

        ; config A {none} = index 0 -> 0: all three voices music-off.
        lda #$00
        sta CHIGH+5
        sta CHIGH+6
        sta CHIGH+7          ; DF5/6/7 music off
        lda AMPL             ; $F004: no SINx -> low nibble 0, high nibble 0
        sta V1
        ASSERT_EQ V1, $00, $04

        ; config B {DF5} = index 1 -> 4: DF5 on+set, DF6/DF7 off.
        lda #$10
        sta CHIGH+5          ; DF5 music on, D5=0
        lda #$05
        sta TOP+5
        lda #$02
        sta BOTTOM+5
        lda #$00
        sta CLOW+5           ; loads Top $05
        lda FLAG+5           ; counter $05 == Top -> SIN5 set; counter -> $04
        lda AMPL             ; $F004: {0,0,1} -> table[1] = 4
        sta V2
        ASSERT_EQ V2, $04, $04

        ; config C {DF5+DF6} = index 3 -> 9: DF5 on+set, DF6 on+set, DF7 off.
        lda #$05
        sta TOP+5
        lda #$00
        sta CLOW+5           ; re-park DF5: loads Top $05
        lda FLAG+5           ; counter $05 == Top -> SIN5 set; counter -> $04
        lda #$10
        sta CHIGH+6          ; DF6 music on, D5=0
        lda #$07
        sta TOP+6
        lda #$03
        sta BOTTOM+6
        lda #$00
        sta CLOW+6           ; loads Top $07
        lda FLAG+6           ; counter $07 == Top -> SIN6 set; counter -> $06
        lda AMPL             ; $F004: {0,1,1} -> table[3] = 9
        sta V3
        ASSERT_EQ V3, $09, $04

        ; --- cell 05: clearing D4 forces that voice's SINx to 0.
        ; Park DF5 set (nibble 4), sample, then music-off DF5 and re-sample: the
        ; weight must drop out -> 0 (DF6/DF7 held off).
        lda #$00
        sta CHIGH+6
        sta CHIGH+7          ; DF6/DF7 off
        lda #$10
        sta CHIGH+5          ; DF5 music on
        lda #$05
        sta TOP+5
        lda #$02
        sta BOTTOM+5
        lda #$00
        sta CLOW+5           ; loads Top $05
        lda FLAG+5           ; counter $05 == Top -> SIN5 set; counter -> $04
        lda AMPL             ; $F004: DF5 on+set -> 4
        sta V1
        lda #$00
        sta CHIGH+5          ; DF5 music off (D4=0) -> SIN5 forced 0
        lda AMPL             ; $F004: voice silenced -> 0
        sta V2
        ASSERT_EQ V1, $04, $05  ; voice audible while enabled
        ASSERT_EQ V2, $00, $05  ; ...and silent once disabled

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        ds 128
        ENTRYSTUB
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ------------------------------------------------- 2K display ROM + 256B pad
; Unused by this ROM, but the 2K block + 256B pad set the 10496-byte size
; accepted as a DPC cart. Laid out identically to dpc-fetch.
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
