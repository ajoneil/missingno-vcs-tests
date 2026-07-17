; bank-fc — the FC board (Amiga "Power Play Arcade", 32K) picks a 4K bank in two
; steps: two registers latch a target bank number, and a separate hotspot commits
; it. Latching a target does not switch the bank on its own.
;
; The cartridge answers every access that has address line A12 high: the 4K
; window $F000-$FFFF. A 32K image is eight 4K banks. Three hotspots (addresses
; the board watches) do the work, split by role:
;   $1FF8  a write latches the target's low 2 bits   (value & %11)
;   $1FF9  a write latches the target's high bits      (value, folded)
;   $1FFC  commit: the latched target becomes the live bank
; The bank index is bank = (high << 2) | low, so a bank >= 4 needs both writes.
; The visible bank changes only when $1FFC is touched.
;
; Which access to $1FFC commits is contested: any access (read or write), or a
; read alone with a write left inert. This test asserts the read-only side
; (cell $04 pins the asymmetry). Untested on hardware.
;
; The latch persists across a commit: the target register is not cleared, so
; touching $1FFC again re-commits the same bank with no fresh latch writes.
;
;   CODE $01 = latch-without-commit switched: after writing $1FF8/$1FF9 to select
;              bank 1 but touching no commit hotspot, the live bank changed (it
;              must stay the home bank until $1FFC is read)
;        $02 = a read of $1FFC did not commit the latched bank 1
;        $03 = the bank walk failed: latch 2 + read $1FFC did not page bank 2
;        $04 = a write to $1FFC committed the latched bank (this test asserts
;              read-only commit)
;        $05 = low+high combine failed: latch low=1 ($1FF8) and high=1 ($1FF9),
;              read $1FFC, expected bank (1<<2)|1 = 5
;        $06 = latch did not persist: a second read of $1FFC with no fresh latch
;              writes did not re-commit the same bank 5
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: FC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

FClo    = $1FF8                ; a write latches the target bank's low 2 bits
FChi    = $1FF9                ; a write latches the target bank's high bits
FCcommit= $1FFC                ; a read commits the latched target (a write does not)
SIG     = $FC00                ; per-bank signature (mid-bank, clear of hotspots/vectors)

ENTRY   = $F000                ; stub entry (reset target), identical in every bank
PROBE   = $F00E                ; probe routine (jsr target), after the 14-byte entry

; probe result cells (harness owns $80-$89; scratch is $90+)
SNOCM   = $90                  ; signature after latch-without-commit (must stay home)
SRD1    = $91                  ; signature after read-commit of bank 1
SRD2    = $92                  ; signature after read-commit of bank 2 (walk)
SWR     = $93                  ; signature after a write to $1FFC (must not commit)
SCOMB   = $94                  ; signature after low+high combine -> bank 5
SPERS   = $95                  ; signature after a bare re-commit (latch persists)

; The shared stub — emitted byte-identically into all eight banks, so code can run
; across a commit (which takes effect on the next bus cycle) undisturbed. The
; entry forces bank 0 by latching 0/0 and reading $1FFC; the probe exercises the
; latch/commit split. nop nop lets a commit settle before the signature read.
        MAC STUB
        ; ENTRY ($F000): force the home bank on reset (power-on bank undefined)
        lda #0                  ; A9 00
        sta FClo                ; 8D F8 1F : latch low = 0
        sta FChi                ; 8D F9 1F : latch high = 0  -> target 0
        bit FCcommit            ; 2C FC 1F : read $1FFC -> commit bank 0
        jmp Main                ; 4C .. .. : run the harness from bank 0
        ; PROBE ($F00E):
        ; --- cell 01: latch bank 1 but do not commit; the live bank must stay home
        lda #1
        sta FClo                ; latch low = 1
        lda #0
        sta FChi                ; latch high = 0  -> target 1 (latched, uncommitted)
        lda SIG
        sta SNOCM               ; still bank 0 -> $A0
        ; --- cell 02: a read of $1FFC commits the latched bank 1
        bit FCcommit            ; read-commit
        nop
        nop
        lda SIG
        sta SRD1                ; -> $A1
        ; --- cell 03: walk on — latch 2, read-commit -> bank 2
        lda #2
        sta FClo
        lda #0
        sta FChi
        bit FCcommit
        nop
        nop
        lda SIG
        sta SRD2                ; -> $A2
        ; --- cell 04: a write to $1FFC must not commit. Latch bank 3, sta $1FFC,
        ; and the live bank must remain bank 2.
        lda #3
        sta FClo                ; latch low = 3
        lda #0
        sta FChi                ; -> target 3 (latched)
        sta FCcommit            ; write $1FFC (A=0): read-only-commit model stays put
        nop
        nop
        lda SIG
        sta SWR                 ; still bank 2 -> $A2
        ; --- cell 05: low+high combine. low=1, high=1 -> bank (1<<2)|1 = 5.
        lda #1
        sta FClo                ; latch low = 1
        lda #1
        sta FChi                ; latch high = 1 -> target 5
        bit FCcommit            ; read-commit
        nop
        nop
        lda SIG
        sta SCOMB               ; -> $A5
        ; --- cell 06: latch persists. Re-read $1FFC with no fresh latch writes;
        ; the same target 5 must re-commit.
        bit FCcommit
        nop
        nop
        lda SIG
        sta SPERS               ; still -> $A5
        ; restore the home bank (0) before returning to Main
        lda #0
        sta FClo
        sta FChi
        bit FCcommit
        rts
        ENDM

; a data bank: shared stub + signature + vectors, at the given file base
        MAC BANK
        ORG {1}
        RORG $F000
        STUB
        ORG {1}+$C00
        RORG $FC00
        .byte {2}
        ORG {1}+$FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        CLEAN_START
        TEST_BEGIN
        jsr PROBE               ; exercise the latch/commit split across the banks
        ASSERT_EQ SNOCM, $A0, $01       ; latch alone did not switch (still home)
        ASSERT_EQ SRD1,  $A1, $02       ; read $1FFC committed bank 1
        ASSERT_EQ SRD2,  $A2, $03       ; walk: read-commit reached bank 2
        ASSERT_EQ SWR,   $A2, $04       ; write $1FFC did not commit (still bank 2)
        ASSERT_EQ SCOMB, $A5, $05       ; low+high assembled bank 5
        ASSERT_EQ SPERS, $A5, $06       ; latch persisted across a bare re-commit
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0                       ; bank 0 signature
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; -------------------------------------------------------------- banks 1..7 (data)
        SEG BANK1
        BANK $1000, $A1
        SEG BANK2
        BANK $2000, $A2
        SEG BANK3
        BANK $3000, $A3
        SEG BANK4
        BANK $4000, $A4
        SEG BANK5
        BANK $5000, $A5
        SEG BANK6
        BANK $6000, $A6
        SEG BANK7
        BANK $7000, $A7
