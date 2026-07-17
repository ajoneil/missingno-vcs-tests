; bank-wf8 — the WF8 board (Coleco white-label, 8K) is F8-like but picks the
; bank from the written data, not from which address was touched.
;
; The cartridge answers every access that has address line A12 high: the 4K
; window $F000-$FFFF. An 8K cart carries two 4K banks and shows one at a time.
; Plain F8 has two hotspots (addresses the board watches): $1FF8 selects bank 0,
; $1FF9 selects bank 1, and the written value is ignored. WF8 has one hotspot,
; $1FF8, and picks the bank from one bit of the value written there; $1FF9 does
; nothing. So `lda #v : sta $1FF8` pages bank 0 or bank 1 depending on one bit
; of v.
;
; Which bit selects the bank is contested: documentation gives D3 (values
; $00-$07 -> bank 0, $08-$0F -> bank 1); the implementations that model this
; board use D2 (the $04 bit). The test asserts D2. Cells $02 and $03 use the two
; deciding values $04 (D2=1, D3=0) and $08 (D2=0, D3=1), which the two readings
; page opposite ways. Untested on hardware.
;
; A read of $1FF8 is undefined by the board and implementations disagree, so it
; is not tested.
;
;   CODE $01 = write data $00 (D2=0) did not page bank 0
;        $02 = write data $04 (D2=1, D3=0) did not page bank 1  [pins the bit vs D3]
;        $03 = write data $08 (D2=0, D3=1) did not page bank 0  [pins the bit vs D3]
;        $04 = write data $0C (D2=1) did not page bank 1
;        $05 = write $04 then $00 did not round-trip back to bank 0
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: WF8

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT = $FFF8                 ; the single WF8 hotspot (mirror of $1FF8)
SIG     = $FC00                 ; per-bank signature byte (mid-bank, clear of $FFxx)

ENTRY   = $F000                 ; stub entry (reset target), identical in both banks
PROBE   = $F008                 ; probe routine (jsr target), after the 8-byte entry

C1      = $90                   ; sig after write $00 (expect $A0)
C2      = $91                   ; sig after write $04 (expect $B1)
C3      = $92                   ; sig after write $08 (expect $A0)
C4      = $93                   ; sig after write $0C (expect $B1)
C5      = $94                   ; sig after $04 then $00 (expect $A0)

; The shared stub — byte-identical in both banks at the same address, so execution
; crosses a switch (which takes effect on the next bus cycle) undisturbed.
        MAC STUB
        ; --- ENTRY ($F000) ---
        lda #0                  ; A9 00
        sta HOTSPOT             ; 8D F8 FF : write D2=0 -> force bank 0 (power-on undefined)
        jmp Main                ; 4C .. .. : run the test (Main lives in bank 0)
        ; --- PROBE ($F008) ---
        lda #$00
        sta HOTSPOT             ; data $00, D2=0 -> bank 0
        lda SIG
        sta C1                  ; expect $A0
        lda #$04
        sta HOTSPOT             ; data $04, D2=1 -> bank 1
        lda SIG
        sta C2                  ; expect $B1
        lda #$08
        sta HOTSPOT             ; data $08, D2=0 (D3=1) -> bank 0
        lda SIG
        sta C3                  ; expect $A0
        lda #$0C
        sta HOTSPOT             ; data $0C, D2=1 -> bank 1
        lda SIG
        sta C4                  ; expect $B1
        lda #$04
        sta HOTSPOT             ; -> bank 1
        lda #$00
        sta HOTSPOT             ; -> bank 0 (round-trip home; probe ends in bank 0)
        lda SIG
        sta C5                  ; expect $A0
        rts
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        CLEAN_START
        TEST_BEGIN

        jsr PROBE                       ; sweep the data-bit and read signatures
        ASSERT_EQ C1, $A0, $01          ; $00 -> bank 0
        ASSERT_EQ C2, $B1, $02          ; $04 -> bank 1 (D2=1; pins bit vs D3)
        ASSERT_EQ C3, $A0, $03          ; $08 -> bank 0 (D2=0; pins bit vs D3)
        ASSERT_EQ C4, $B1, $04          ; $0C -> bank 1
        ASSERT_EQ C5, $A0, $05          ; round-trip returned home

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0                       ; bank 0 signature
        ORG $0FFC
        RORG $FFFC
        .word ENTRY                     ; reset vector
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
