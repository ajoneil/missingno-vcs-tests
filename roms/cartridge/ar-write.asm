; ar-write — Starpath Supercharger (AR) read-driven write protocol, swept.
;
; The Supercharger has no write line: reads do everything (see ar-config). A RAM
; write works like this:
;   - a read of $F0nn arms a write (sets it up), saving the low byte $nn as the
;     value to write;
;   - the value is written at the cart access exactly five address-bus
;     transitions later, and is forced onto the data bus so the CPU reads it too.
; A transition is any cycle whose address differs from the cycle before it, so a
; byte read twice back-to-back counts as one transition, not two. The write fires
; only if RAM write-enable (control bit 1) is set and the fifth access falls in a
; RAM window (the low window is always RAM).
;
; The transition-based count is documented board behaviour, untested on hardware.
;
;   CODE $01 = standard +5 write did not land on the target, or the reading
;              instruction did not read back the written value
;        $02 = write lands at +4: the target (read one transition early) was
;              written, or the +5 scratch cell was not
;        $03 = write lands at +6: the target (read one transition late) was
;              written, or the +5 scratch cell was not
;        $04 = repeated-address (NOP) shape: the write did not land at the 5th
;              transition (a raw-cycle model fires one access early, on a code
;              address, and leaves CELL_04 at $FF; only a landed write sets it)
;        $05 = driven-bus readback: the value read back does not match the value
;              the cart forced onto the bus when the write fired
;        $06 = write enable off (control bit 1 = 0) changed RAM at some distance
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

; baked data cells (all $FF at load; a write lands a value != $FF so "changed"
; is unambiguous). Distinct addresses per cell so cells never cross-contaminate.
CELL_01  = $F500                ; canonical +5 target
CELL_02T = $F510                ; $02 target read at +4 (must stay $FF)
CELL_04  = $F520                ; $04 repeated-address target
CELL_05  = $F540                ; $05 driven-bus target
CELL_06  = $F560                ; $06 write-disabled target
CELL_02S = $F610                ; $02 +5 scratch (must receive the write)
CELL_03S = $F620                ; $03 +5 scratch (must receive the write)
CELL_03T = $F720                ; $03 target read at +6 (must stay $FF)

; SET_CFG value: latch a control byte (read $F000+value) then commit (read
; $FFF8). BIT $FFF8 commits the config.
        MAC SET_CFG
        ldy #{1}
        lda $F000,y
        bit HOTSPOT
        ENDM

        SEG BANK
        ORG   $0000
        RORG  $F000
        ds    256, $FF          ; $F000-$F0FF: control-register latch page

Start:                          ; $F100 — BIOS jumps here once the image loads
        CLEAN_START
        TEST_BEGIN

; --- cell $01: the canonical +5 write lands, and drives the bus -----------------
; `lda $F0nn ; lda (WPTR),y` — arm read is transition A0, the indirect data read
; is A0+5 (op,zp,ptrlo,ptrhi,read). The write puts $3C into CELL_01, and the
; committing LDA reads back $3C (the value the cart forces onto the bus).
        SET_CFG $06             ; bank0 low, write enable
        lda   #<CELL_01
        sta   WPTR
        lda   #>CELL_01
        sta   WPTR+1
        ldy   #0
        lda   $F03C             ; arm value $3C          (A0)
        lda   (WPTR),y          ; +5 -> write $3C, A=$3C (A0+5)
        sta   A_OBS
        SET_CFG $04             ; bank0 low, write off (safe read)
        ASSERT_EQ A_OBS, $3C, $01
        ASSERT_EQ CELL_01, $3C, $01

; --- cell $02: commit distance +4 (target read one transition early) -----------
; `lda $F0nn ; lda $F5C0,X` (X=$50) page-crosses: the CPU issues a dummy read of
; $F510 (A0+4) then the real read of $F610 (A0+5). The write fires at the 5th
; transition = $F610 (scratch); the +4 dummy read $F510 (the "target", one
; transition early) is not written.
;   op(A0+1) lo(A0+2) hi(A0+3) dummy $F510(A0+4) real $F610(A0+5)
        SET_CFG $06
        ldx   #$50
        lda   $F05A             ; arm value $5A          (A0)
        lda   $F5C0,x           ; dummy $F510 (+4), real $F610 (+5) -> write $5A
        SET_CFG $04
        ASSERT_EQ CELL_02T, $FF, $02   ; +4 target: untouched
        ASSERT_EQ CELL_02S, $5A, $02   ; +5 scratch: written

; --- cell $03: commit distance +6 (target read one transition late) ------------
; `lda $F0nn ; lda (WPTR),y` with a page-crossing pointer (WPTR=$F6C0, Y=$60):
; the indirect load is 6 cycles — op,zp,ptrlo,ptrhi,dummy $F620(A0+5),real
; $F720(A0+6). The write fires at the 5th transition = the dummy $F620 (scratch);
; the intended target $F720 arrives one transition too late and is not written.
        SET_CFG $06
        lda   #$C0
        sta   WPTR
        lda   #$F6
        sta   WPTR+1
        ldy   #$60
        lda   $F06E             ; arm value $6E          (A0)
        lda   (WPTR),y          ; dummy $F620 (+5) -> write $6E ; real $F720 (+6)
        SET_CFG $04
        ASSERT_EQ CELL_03S, $6E, $03   ; +5 scratch: written
        ASSERT_EQ CELL_03T, $FF, $03   ; +6 target: untouched (one transition late)

; --- cell $04: repeated-address shape (NOP double-read) -------------------------
; the repeated-address trick: `cmp $F000,Y ; nop ; cmp CELL_04`. NOP's 2nd cycle
; dummy-reads the CMP opcode address, which the CMP then re-reads — the same
; address twice = one transition. So the write is 6 cycles but only 5 transitions
; after the arm, landing at CELL_04. A raw-cycle counter would land one cell
; early; counting transitions, the write hits CELL_04.
;   cmp$F000,Y read $F047(A0)  nop op(A0+1) nop-dummy(A0+2 = cmp opcode addr)
;   cmp opcode(A0+2 repeat, no transition) lo(A0+3) hi(A0+4) read CELL_04(A0+5)
        SET_CFG $06
        lda   #0                ; define A for CMP (flags unused)
        ldy   #$47              ; arm value $47 via $F047
        cmp   $F000,y           ; arm read $F047          (A0)
        nop                     ; A0+1 opcode, A0+2 dummy = next opcode addr
        cmp   CELL_04           ; opcode A0+2 (repeat), read CELL_04 at +5 -> write $47
        SET_CFG $04
        ASSERT_EQ CELL_04, $47, $04

; --- cell $05: the driven-bus readback -----------------------------------------
; At the committing access the cart forces the written value onto the bus, so the
; instruction performing the read receives it (the BIOS RAM test depends on
; this). The canonical `lda (WPTR),y` therefore leaves A = value.
        SET_CFG $06
        lda   #<CELL_05
        sta   WPTR
        lda   #>CELL_05
        sta   WPTR+1
        ldy   #0
        lda   $F029             ; arm value $29          (A0)
        lda   (WPTR),y          ; +5 -> write $29; A now = $29 (forced bus)
        sta   A_OBS
        SET_CFG $04
        ASSERT_EQ A_OBS, $29, $05      ; the CPU read the written value
        ASSERT_EQ CELL_05, $29, $05    ; ...and it also reached RAM

; --- cell $06: write with D1 (control bit 1, the RAM write-enable) = 0 is a no-op at every distance ---
; Same shapes as $01 (+5), $02 (+4/+5) but write-enable off: nothing may change.
        SET_CFG $04             ; bank0 low, write disabled
        lda   #<CELL_06
        sta   WPTR
        lda   #>CELL_06
        sta   WPTR+1
        ldy   #0
        lda   $F05B             ; arm attempt (D1=0 -> inert)
        lda   (WPTR),y          ; +5 access, but no write
        ldx   #$50
        lda   $F05B             ; arm attempt again
        lda   $F5C0,x           ; +4/+5 accesses, but no write
        SET_CFG $04
        ASSERT_EQ CELL_06, $FF, $06    ; +5 target untouched
        ASSERT_EQ CELL_02T, $FF, $06   ; +4 dummy cell still untouched
        ASSERT_EQ CELL_02S, $5A, $06   ; $02's write survived (only $5A there)

        SET_CFG $04             ; settle a clean, write-disabled map for the screen
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

; baked data cells: fill $F500-$F7FF with $FF so every cell (and every page-cross
; dummy-read address) is defined; writes land values != $FF.
        ORG   $0500
        RORG  $F500
        ds    $300, $FF         ; $F500-$F7FF
