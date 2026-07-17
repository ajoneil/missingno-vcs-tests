; ar-hazards — Starpath Supercharger (AR) read-driven corruption hazards.
;
; The AR has no write line: reads do everything (see ar-config, ar-write). Two
; read effects make the $F0xx page and the control latch hazardous:
;   - a read of $F0nn arms a pending write of $nn that lands 5 address-bus
;     transitions later;
;   - a read of $FFF8 copies the pending value into the control register.
;
; Two consequences follow:
;   - With RAM write-enable (control bit 1) on, any read of $F0xx arms a write:
;     an innocent `lda $F042` overwrites whatever RAM cell is accessed 5
;     transitions later.
;   - There is no time limit between the $F0xx read and the $FFF8 commit; the
;     pending value waits as long as it takes. A write that is already pending
;     freezes the latch for its lifetime, so a second $F0xx read does not re-arm.
;
;   CODE $01 = normal write and readback failed (write path or driven-bus read)
;        $02 = writes-on $F0xx read did not overwrite the +5 cell with its low byte
;        $03 = control latch did not survive a long gap from latch to commit
;              (switch failed to take, or took the wrong bank)
;        $04 = a writes-off $F0xx read corrupted a cell at some distance
;        $05 = back-to-back arms: the first armed value did not win at +5
;        $06 = two-read commit: the committed bank was not the last latched value
;
; Cell $06 is contested: with two $F0xx reads inside the write-delay window, a
; transparent latch — the documented board — reloads on the second read and
; commits the last value; a latch that freezes until the delay drains commits the
; first. The test asserts the documented last-wins side; untested on hardware.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: AR

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

WPTR    = $8E                   ; zero-page pointer for indirect writes ($8E/$8F)
A_OBS   = $90                   ; stashed accumulator (driven-bus readback)

HOTSPOT = $FFF8                 ; control-register commit ($1FF8 mirror)

MARKER0 = $3A                   ; distinct per-bank marker bytes
MARKER1 = $5C
MARKER2 = $71
MARK    = $F700                 ; per-bank marker cell in the low window

HZ01    = $F500                 ; $01 control target
HZ_KNOWN= $F520                 ; $02 corruption target (the +5 cell)
HZ04    = $F540                 ; $04 writes-off target (+5, canonical)
HZ04B   = $F610                 ; $04 writes-off target (+5 real read of page-cross)

        MAC SET_CFG
        ldy #{1}
        lda $F000,y
        bit HOTSPOT
        ENDM

; WRITE_MARK cfg, armval : canonical +5 write of $armval into MARK, in the bank
; the config selects into the low window. WPTR must already point at MARK.
        MAC WRITE_MARK
        SET_CFG {1}
        ldy #0
        lda $F000+{2}
        lda (WPTR),y
        ENDM

        SEG BANK
        ORG   $0000
        RORG  $F000
        ds    256, $FF          ; $F000-$F0FF: control-register latch page

Start:                          ; $F100 — BIOS jumps here once the image loads
        CLEAN_START
        TEST_BEGIN

; --- prologue: stamp a distinct marker into MARK ($F700) of each RAM bank ------
        lda   #<MARK
        sta   WPTR
        lda   #>MARK
        sta   WPTR+1
        WRITE_MARK $06, MARKER0         ; bank0 low, write on -> MARK=$3A
        WRITE_MARK $16, MARKER1         ; bank1 low            -> MARK=$5C
        WRITE_MARK $02, MARKER2         ; bank2 low            -> MARK=$71

; --- cell $01: a normal write + readback, clear of the hazard zones -----------
        SET_CFG $06                     ; bank0 low, write enable
        lda   #<HZ01
        sta   WPTR
        lda   #>HZ01
        sta   WPTR+1
        ldy   #0
        lda   $F0C7                     ; arm value $C7
        lda   (WPTR),y                  ; +5 -> write $C7, A=$C7
        sta   A_OBS
        SET_CFG $04                     ; bank0 low, write off
        ASSERT_EQ A_OBS, $C7, $01
        ASSERT_EQ HZ01, $C7, $01

; --- cell $02: writes on, any $F0xx read corrupts the +5 RAM cell --------------
; The read `lda $F042` looks innocent but arms a write of $42; the canonical +5
; access lands it on HZ_KNOWN.
        SET_CFG $06                     ; bank0 low, write enable
        lda   #<HZ_KNOWN
        sta   WPTR
        lda   #>HZ_KNOWN
        sta   WPTR+1
        ldy   #0
        lda   $F042                     ; "innocent" read -> arms $42
        lda   (WPTR),y                  ; +5 -> HZ_KNOWN clobbered with $42
        SET_CFG $04
        ASSERT_EQ HZ_KNOWN, $42, $02

; --- cell $03: control-latch survival — no upper limit latch->commit ----------
; Latch config $04 (bank0, D1 (control bit 1, the RAM write-enable) off), then run a long run of filler transitions
; (D1 stays off, so no stray write fires), and only then commit. The switch
; still takes: the data-hold latch is not governed by the write-delay counter.
        SET_CFG $00                     ; start: bank2 low (MARK reads $71), D1 off
        lda   $F004                     ; latch $04 (bank0), do not commit yet
        nop                             ; 12 filler transitions — well past the 5 the write-delay counter needs
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        bit   HOTSPOT                   ; commit far later -> bank0 low
        ASSERT_EQ MARK, MARKER0, $03    ; the switch took: MARK now $3A

; --- cell $04: writes off, a $F0xx read corrupts nothing (sweep distances) -----
        SET_CFG $04                     ; bank0 low, write disabled
        lda   #<HZ04
        sta   WPTR
        lda   #>HZ04
        sta   WPTR+1
        ldy   #0
        lda   $F0E5                     ; arm attempt (D1=0 -> inert)
        lda   (WPTR),y                  ; +5 access, no write
        ldx   #$50
        lda   $F0E5                     ; arm attempt again
        lda   $F5C0,x                   ; +4/+5 accesses (dummy $F510, real $F610), no write
        SET_CFG $04
        ASSERT_EQ HZ04, $FF, $04        ; +5 cell untouched
        ASSERT_EQ HZ04B, $FF, $04       ; +5 page-cross cell ($F610) untouched
        ASSERT_EQ HZ01, $C7, $04        ; $01's write is the only thing at HZ01

; --- cell $05: back-to-back write arms — the first value wins ------------------
; With D1 on, `lda $F055` arms $55; a 2nd $F0xx read (via the indirect load, which
; itself reads $F02A) arrives while the write is still pending, so it does not
; re-latch — and that same access is the +5 commit, writing the first value $55
; into bank0[$2A].
        SET_CFG $06                     ; bank0 low, write enable
        lda   #$00
        sta   WPTR
        lda   #$F0
        sta   WPTR+1                    ; WPTR = $F000
        ldy   #$2A                      ; 2nd $F0xx read will be $F02A
        lda   $F055                     ; arm1 value $55            (A0)
        lda   (WPTR),y                  ; reads $F02A at +5 = 2nd arm attempt + commit
        SET_CFG $04                     ; bank0 low, write off
        lda   $F02A                     ; read back bank0[$2A]
        sta   A_OBS
        ASSERT_EQ A_OBS, $55, $05       ; first value won, second ($2A) ignored

; --- cell $06: contested — control-latch two-read commit (D1 off) --------------
; Two $F0xx reads inside the delay window, then commit. A transparent latch
; (the documented reading) takes the last value; a latch that freezes
; until the delay drains keeps the first.
;   lda $F000 -> latch $00 (bank2)   ; arm1
;   lda $F004 -> transparent latch reloads $04 (bank0); a frozen latch keeps $00
;   bit $FFF8 -> commit
        SET_CFG $00                     ; start from bank2 (MARK reads $71)
        lda   $F000                     ; arm1: latch $00 (bank2)
        lda   $F004                     ; reload $04 (bank0) if transparent; else keep $00
        bit   HOTSPOT                   ; commit
        ASSERT_EQ MARK, MARKER0, $06    ; last-wins -> bank0 ($3A); a frozen latch -> $71

        SET_CFG $04                     ; settle a clean, write-disabled map
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

; baked data cells: $F500-$F7FF all $FF; markers are written into MARK at runtime.
        ORG   $0500
        RORG  $F500
        ds    $300, $FF         ; $F500-$F7FF
