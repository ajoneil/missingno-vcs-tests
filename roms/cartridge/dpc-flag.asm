; dpc-flag — the DPC fetcher's mask flag and the masked read window. The DPC
; ("Display Processor Chip", Pitfall II) gives each of its eight fetchers a
; one-bit "flag" that gates a masked data window. Pitfall II uses it to blank a
; graphic outside a horizontal span without branching.
;
; The fetcher mechanism is explained in dpc-fetch.
;
; The flag is set and reset by exact 8-bit matches on the counter's low byte, not
; by a range compare. As a counter is read down, the chip re-checks the flag from
; the current low byte before forming the output byte:
;   - set     when counter-low == Top,
;   - reset   when counter-low == Bottom,
;   - cleared by any write to Top (a contested edge, probed in dpc-flag-edges),
;   - a load of counter-low to a value between Top and Bottom leaves it as it is.
; So as reads walk the counter down, the flag changes only when a read lands
; exactly on Top or Bottom: the byte
; at counter-low == Top is the first byte the flag lets through, and it stays set
; on every read after that until one lands on Bottom.
;
; Three windows read the same fetcher (each read still decrements the pointer):
;   read $F008+x   unmasked   the display byte, always
;   read $F010+x   masked     display byte AND flag (byte if set, $00 if clear)
;   read $F038+x   flag       $FF if set, $00 if clear
;
; Registers are reached through the $F000-$F07F mirror.
;
; Cells $01-$06 are behaviour every implementation shares. Cell $07 reads DF0's
; flag through the flag window: specified for all eight fetchers (patent Table 1),
; never read by Pitfall II for DF0-DF4, untested on hardware.
;
;   CODE $01 = flag not clear when counter loaded between Top and Bottom
;              (masked read must be $00 while the unmasked read returns data)
;        $02 = walking a read down onto Top did not set the flag
;              (masked read at low==Top must return the first unmasked byte)
;        $03 = flag did not stay set past Top (edge, not level: later masked
;              reads must still return data)
;        $04 = reaching Bottom did not reset the flag (masked reads must return
;              $00 from that read on)
;        $05 = flag is not per-fetcher (DF4 set while DF1 clear)
;        $06 = flag readout on a high fetcher wrong (DF5 $F03D: $FF set / $00 clear)
;        $07 = flag readout on DF0 wrong ($F038 must be $FF when DF0's flag is set;
;              a DF5-DF7-only guard returns $00 instead)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8
HOTSPOT1 = $FFF9

; Each cell reloads Top/Bottom and the counter, then reads the masked or flag
; window; the reads are destructive, so the expected values account for every
; decrement. $F000-$F007 is never touched, music stays off (counter-high writes
; keep D4/D5 = 0) and the transformed read windows (dpc-swizzle, dpc-shift) are
; never used.
DATA     = $F008             ; read DFx data unmasked (decrements)
MASKED   = $F010             ; read DFx data AND flag (decrements)
FLAG     = $F038             ; read DFx flag: $FF set / $00 clear (decrements)
TOP      = $F040             ; write DFx Top    (clears the flag)
BOTTOM   = $F048             ; write DFx Bottom
CLOW     = $F050             ; write DFx counter low
CHIGH    = $F058             ; write DFx counter high (DF4=$F05C, DF5-7=$F05D-F)

V1       = $90
V2       = $91
V3       = $92

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

        ; --- cell 01: flag clear when the counter is loaded between Top/Bottom
        lda #$C0
        sta TOP+0             ; DF0 Top = $C0 (the write clears the flag)
        lda #$40
        sta BOTTOM+0          ; Bottom = $40
        lda #$00
        sta CHIGH+0
        lda #$80
        sta CLOW+0            ; low = $80, strictly between Bottom and Top
        lda DATA+0            ; unmasked: display byte f($80)=$88, ptr -> $7F
        sta V1
        lda MASKED+0          ; masked: flag clear (low never hit Top) -> $00
        sta V2
        ASSERT_EQ V1, $88, $01 ; unmasked returns data...
        ASSERT_EQ V2, $00, $01 ; ...masked returns $00 -> flag is clear

        ; --- cell 02: walking a read down onto Top sets the flag
        lda #$50
        sta TOP+0            ; Top = $50 (clears flag again)
        lda #$10
        sta BOTTOM+0         ; Bottom = $10
        lda #$00
        sta CHIGH+0
        lda #$53
        sta CLOW+0           ; low = $53, three above Top
        lda DATA+0           ; low $53 (clear), ptr -> $52
        lda DATA+0           ; low $52 (clear), ptr -> $51
        lda DATA+0           ; low $51 (clear), ptr -> $50
        lda MASKED+0         ; low $50 == Top: flag sets, output data f($50)=$55, ptr->$4F
        sta V1
        ASSERT_EQ V1, $55, $02 ; the byte at low==Top is the first unmasked one

        ; --- cell 03: the flag stays set past Top (edge, not level)
        lda MASKED+0         ; low $4F: still set -> f($4F)=$4B, ptr -> $4E
        sta V1
        lda MASKED+0         ; low $4E: still set -> f($4E)=$4A, ptr -> $4D
        sta V2
        ASSERT_EQ V1, $4B, $03
        ASSERT_EQ V2, $4A, $03

        ; --- cell 04: reaching Bottom resets the flag
        ; Top/Bottom unchanged; the flag latch is still set from cell 02/03. Only
        ; the counter is reloaded (a counter-low write does not touch the flag).
        lda #$11
        sta CLOW+0           ; low = $11 (Bottom + 1)
        lda MASKED+0         ; low $11: still set -> data f($11)=$10, ptr -> $10
        sta V1
        lda MASKED+0         ; low $10 == Bottom: flag resets -> $00, ptr -> $0F
        sta V2
        lda MASKED+0         ; low $0F: stays clear -> $00, ptr -> $0E
        sta V3
        ASSERT_EQ V1, $10, $04 ; data just before Bottom
        ASSERT_EQ V2, $00, $04 ; reset at Bottom
        ASSERT_EQ V3, $00, $04 ; stays reset after

        ; --- cell 05: the flag is per-fetcher (DF4 set while DF1 clear)
        lda #$A0
        sta TOP+1
        lda #$20
        sta BOTTOM+1
        lda #$00
        sta CHIGH+1
        lda #$60
        sta CLOW+1           ; DF1 low = $60 between -> flag clear
        lda #$A0
        sta TOP+4
        lda #$20
        sta BOTTOM+4
        lda #$00
        sta CHIGH+4          ; $F05C: DF4 counter high (D4=0, no draw-line)
        lda #$A0
        sta CLOW+4           ; DF4 low = $A0 == Top
        lda MASKED+1         ; DF1 masked: flag clear -> $00
        sta V1
        lda MASKED+4         ; DF4 masked: low==Top sets flag -> data f($A0)=$AA
        sta V2
        ASSERT_EQ V1, $00, $05
        ASSERT_EQ V2, $AA, $05

        ; --- cell 06: flag readout on a high fetcher (DF5), music off
        lda #$70
        sta TOP+5
        lda #$10
        sta BOTTOM+5
        lda #$00
        sta CHIGH+5          ; $F05D: DF5 high, D4=0 music off, D5=0 clock select
        lda #$40
        sta CLOW+5           ; low = $40 between -> flag clear
        lda FLAG+5           ; $F03D: flag readout, low $40 -> $00, ptr -> $3F
        sta V1
        lda #$70
        sta CLOW+5           ; low = $70 == Top (Top/Bottom unchanged; latch still clear)
        lda FLAG+5           ; $F03D: low $70 == Top sets flag -> $FF, ptr -> $6F
        sta V2
        ASSERT_EQ V1, $00, $06
        ASSERT_EQ V2, $FF, $06

        ; --- cell 07 (last): flag readout on DF0 ($F038) — the DF0-DF4 guard cell
        lda #$30
        sta TOP+0
        lda #$08
        sta BOTTOM+0
        lda #$00
        sta CHIGH+0
        lda #$30
        sta CLOW+0           ; low = $30 == Top
        lda FLAG+0           ; $F038: low==Top sets flag -> $FF (a DF5-DF7-only guard returns $00)
        sta V1
        ASSERT_EQ V1, $FF, $07

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
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
