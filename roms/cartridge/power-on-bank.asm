; power-on-bank — a diagnostic, not a pass/fail test: it records which bank an
; F8 board is in at power-on, before any code forces one.
;
; A bankswitched cart's power-on bank is undefined: nothing on the board latches
; a known bank at reset, so which 4K bank the CPU first sees is whatever the
; switching flip-flops happen to hold. Every other cartridge test forces its home
; bank in the reset entry before doing anything observable — correct for testing
; switch behaviour, but it discards the one fact this ROM wants: which bank each
; implementation (and, one day, real hardware) actually wakes in.
;
; So this F8 image's entry does not force a bank. Both banks hold a byte-identical
; stub, and the reset vectors point at it; the only difference between banks is a
; one-byte signature ($A0 bank 0, $B1 bank 1) at a fixed mid-bank address ($FC00).
;
;   OBSERVED $A0 = the machine powered on in bank 0
;   OBSERVED $B1 = the machine powered on in bank 1
;   RESULT always PASS (this ROM asserts nothing)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: F8

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $1FF8               ; touch -> select bank 0 (used only to normalise)
SIG      = $FC00               ; per-bank signature ($A0 bank 0, $B1 bank 1)
POWERON  = $90                 ; RAM: the observed power-on signature (survives TEST_BEGIN)

ENTRY    = $F000               ; stub entry (reset target), identical in both banks

; The shared stub — byte-identical in both banks (only the $FC00 signature data
; differs). It records the woke-in bank before forcing a known one.
        MAC STUB
        CLEAN_START            ; clears RAM; touches no F8 hotspot -> live bank unchanged
        lda SIG                ; read the live (power-on) bank's signature before
                               ;   the force below: after it, it always reads $A0
        sta POWERON            ; stash which bank we woke in (RAM is clean now)
        bit HOTSPOT0           ; only now normalise: force bank 0
        jmp Main               ; enter the harness in bank 0
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        TEST_BEGIN             ; deterministic-state anchor (CLEAN_START already ran)
        lda POWERON
        sta OBSERVED           ; surface the observed power-on bank in the PASS record
        PASS_TEST              ; unconditional PASS — this ROM measures, it does not judge

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0                       ; bank 0 signature
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        STUB
        ORG $1C00
        RORG $FC00
        .byte $B1                       ; bank 1 signature (differs)
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
