; dpc-flag-edges — three contested edges of the DPC fetcher's one-bit flag.
;
; The DPC ("Display Processor Chip", Pitfall II) gives each display fetcher a
; one-bit flag. Two 8-bit comparators watch the fetcher's counter-low value: the
; flag sets when counter-low == Top and resets when counter-low == Bottom (US
; Patent 4,644,495). That set/reset rule is settled; dpc-flag exercises it.
;
; This ROM probes three edges the patent leaves terse and Pitfall II never
; exercises — untested on hardware. Each cell asserts one documented reading.
; All flag reads use DF5 ($F03D): flag reads on the low fetchers DF0-DF4 are
; unreliable on some implementations, which DF5 avoids.
;
; The three contested edges:
;
;   Write-to-Top polarity. The patent says a write to Top (a "Tx signal") also
;   resets the flag; other documentation says the write sets it. Cell $02 asserts
;   the patent's reset.
;
;   Top == Bottom == counter-low. Both comparators fire on the same value; the
;   patent does not say which wins. Some implementations are set-wins ($FF),
;   others reset-wins ($00). Cell $03 asserts set-wins.
;
;   Comparator timing. The comparators run continuously, so writing counter-low
;   == Top (flag clear, no read), then a value strictly between Top and Bottom,
;   should leave the flag set: the brief equality with Top already latched it and
;   the between-value never equals Bottom. Some implementations evaluate at write
;   time and agree ($FF); others defer to reads and see only the between-value
;   ($00). Cell $04 asserts the patent value ($FF).
;
;   CODE $01 = baseline set/reset broken (read-walk: set at low==Top, reset at
;              low==Bottom on DF5 — a compact repeat of dpc-flag)
;        $02 = write-to-Top did not reset the flag (patent: $00)
;        $03 = Top==Bottom==low did not resolve set-wins ($FF)
;        $04 = comparator timing: counter-low==Top then a between-value left the
;              flag clear instead of latched set ($FF)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8
HOTSPOT1 = $FFF9

; Counter-high writes keep music off (D4=0) and D5=0, and no read touches
; $F000-$F007, so each cell's reading turns only on the edge it probes. Counters
; are reloaded between cells and the reads' decrements are accounted for.
FLAG     = $F038             ; read DFx flag: $FF set / $00 clear (decrements)
TOP      = $F040             ; write DFx Top    (clears the flag)
BOTTOM   = $F048             ; write DFx Bottom
CLOW     = $F050             ; write DFx counter low
CHIGH    = $F058             ; write DFx counter high (DF5-7 = $F05D-F)

V1       = $90
V2       = $91

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

        ; --- cell 01: baseline set/reset via a read-walk on DF5
        ; A flag-read whose counter-low lands on Top sets the flag; one that
        ; lands on Bottom resets it. Proves the plumbing before the contested
        ; cells; DF5 avoids the low-fetcher flag-read gap (see header).
        lda #$00
        sta CHIGH+5         ; $F05D: DF5 high, D4=0 music off, D5=0
        lda #$10
        sta BOTTOM+5        ; Bottom = $10
        lda #$50
        sta TOP+5           ; Top = $50 (the write clears the flag)
        lda #$50
        sta CLOW+5          ; low == Top
        lda FLAG+5          ; $F03D: low==Top sets flag -> $FF, ptr -> $4F
        sta V1
        lda #$10
        sta CLOW+5          ; low == Bottom (flag still set from above)
        lda FLAG+5          ; $F03D: low==Bottom resets flag -> $00, ptr -> $0F
        sta V2
        ASSERT_EQ V1, $FF, $01
        ASSERT_EQ V2, $00, $01

        ; --- cell 02: a write to Top resets the flag
        ; Set the flag (low==Top read), then write Top again (same value): the
        ; patent's Tx signal clears the flag (other documentation says it sets
        ; -- untested on hardware). The following flag-read is at $6F (neither Top nor
        ; Bottom), so it reports the latched level.
        lda #$00
        sta CHIGH+5
        lda #$10
        sta BOTTOM+5
        lda #$70
        sta TOP+5           ; Top = $70 (clears flag)
        lda #$70
        sta CLOW+5          ; low == Top
        lda FLAG+5          ; sets flag -> $FF, ptr -> $6F
        sta V1
        lda #$70
        sta TOP+5           ; write Top again -> resets the flag (patent)
        lda FLAG+5          ; low $6F, latch reports reset -> $00, ptr -> $6E
        sta V2
        ASSERT_EQ V1, $FF, $02  ; the flag really was set first
        ASSERT_EQ V2, $00, $02  ; ...and the Top write cleared it

        ; --- cell 04 (patent): comparator timing, write-time evaluation
        ; Flag clear; write counter-low == Top (no read), then write counter-low
        ; to a between-value; then flag-read. Continuous comparators latched the
        ; Top equality at write time -> $FF. A model that evaluates on writes
        ; agrees; one that defers to reads sees only the between-value -> $00.
        ; A self-test stops at its first failing cell, so no ordering can show
        ; every contested cell on every model. This cell has patent authority, so
        ; it runs before the patent-silent tie in cell 03; the codes keep their
        ; labels, making the execution order $01, $02, $04, $03.
        lda #$00
        sta CHIGH+5
        lda #$20
        sta BOTTOM+5        ; Bottom = $20
        lda #$60
        sta TOP+5           ; Top = $60 (clears flag -> starts clear)
        lda #$60
        sta CLOW+5          ; write low == Top, no read: continuous HW latches set
        lda #$40
        sta CLOW+5          ; write low = $40 (between): never equals Bottom, stays set
        lda FLAG+5          ; write-time eval: $FF; deferred eval: $00, ptr -> $3F
        sta V1
        ASSERT_EQ V1, $FF, $04

        ; --- cell 03 (set-wins asserted): Top==Bottom==low
        ; Both comparators fire on the same counter value. A set-wins model
        ; reports $FF; a reset-wins model reports $00. Patent-silent tie.
        lda #$00
        sta CHIGH+5
        lda #$40
        sta TOP+5           ; Top = $40 (clears flag)
        lda #$40
        sta BOTTOM+5        ; Bottom = $40 == Top
        lda #$40
        sta CLOW+5          ; low = $40 == Top == Bottom
        lda FLAG+5          ; set-wins -> $FF (reset-wins -> $00), ptr -> $3F
        sta V1
        ASSERT_EQ V1, $FF, $03

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
