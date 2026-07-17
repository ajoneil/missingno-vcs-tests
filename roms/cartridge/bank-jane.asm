; bank-jane — the JANE board (a 16K Tarzan prototype) is an F8-family
; bankswitcher with four 4K banks, chosen by four hotspots scattered across the
; top page.
;
; The cartridge answers every access that has address line A12 high: the 4K
; window $F000-$FFFF. A 16K cart carries four 4K banks and shows one in that
; window at a time. Each bank has its own hotspot (an address that, when touched,
; pages that bank in); JANE spreads its four across the top page with gaps:
;
;   touch $1FF0 -> bank 0        touch $1FF8 -> bank 2
;   touch $1FF1 -> bank 1        touch $1FF9 -> bank 3
;
; $1FF2-$1FF7 and $1FFA/$1FFB are not hotspots: an access there pages nothing. A
; hotspot fires on the bus access — read or write, the data value does not matter
; — so the test proves both, strobing some hotspots with a write (sta) and others
; with a read (lda/bit). The cart decodes only 13 address lines, so the CPU
; reaches the hotspots through their $FFFx mirror (higher addresses the partial
; decode treats as the same ones) at the top of the window.
;
;   CODE $01 = write $1FF0 did not page in bank 0
;        $02 = read  $1FF1 did not page in bank 1
;        $03 = write $1FF8 did not page in bank 2
;        $04 = read  $1FF9 did not page in bank 3
;        $05 = write $1FF0 did not return to the home bank (bank 0)
;        $06 = a non-hotspot neighbour ($1FF2/$1FF7/$1FFA/$1FFB) wrongly switched
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: JANE

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

H_B0    = $FFF0                 ; touch -> bank 0  (mirror of $1FF0)
H_B1    = $FFF1                 ; touch -> bank 1  (mirror of $1FF1)
H_B2    = $FFF8                 ; touch -> bank 2  (mirror of $1FF8)
H_B3    = $FFF9                 ; touch -> bank 3  (mirror of $1FF9)
SIG     = $FC00                 ; per-bank signature byte (mid-bank, clear of $FFxx)

ENTRY   = $F000                 ; stub entry (reset target), identical in all banks
PROBE   = $F006                 ; probe routine (jsr target), after the 6-byte entry
READ1   = $F040                 ; fingerprint helper, right after the probe body's rts

S0      = $90                   ; signature after write $1FF0  (expect $A0)
S1      = $91                   ; signature after read  $1FF1  (expect $B1)
S2      = $92                   ; signature after write $1FF8  (expect $C2)
S3      = $93                   ; signature after read  $1FF9  (expect $D3)
SH      = $94                   ; signature after return $1FF0 (expect $A0)
SN      = $95                   ; signature after neighbour strobes (expect $A0)

; The shared stub — emitted byte-identical into all four banks so execution can
; cross a bank switch and keep fetching valid code at the same address.
        MAC STUB
        ; --- ENTRY ($F000) ---
        bit H_B0                ; 2C F0 FF : power-on bank undefined -> force bank 0
        jmp Main                ; 4C .. .. : run the test (Main lives in bank 0)
        ; --- PROBE ($F006) ---
        sta H_B0                ; 8D F0 FF : write $1FF0 -> bank 0
        lda SIG
        sta S0                  ; expect $A0
        jsr READ1               ; AD F1 FF 60 : read $1FF1 -> bank 1 (the fingerprint)
        lda SIG
        sta S1                  ; expect $B1
        sta H_B2                ; 8D F8 FF : write $1FF8 -> bank 2
        lda SIG
        sta S2                  ; expect $C2
        lda H_B3                ; AD F9 FF : read $1FF9 -> bank 3
        lda SIG
        sta S3                  ; expect $D3
        sta H_B0                ; 8D F0 FF : write $1FF0 -> back to the home bank
        lda SIG
        sta SH                  ; expect $A0
        ; the six gap addresses between/around the hotspots must not switch
        bit H_B0+2              ; 2C F2 FF : $1FF2 (not a hotspot)
        bit H_B0+7              ; 2C F7 FF : $1FF7 (not a hotspot)
        bit H_B2+2              ; 2C FA FF : $1FFA (not a hotspot)
        bit H_B2+3              ; 2C FB FF : $1FFB (not a hotspot)
        lda SIG
        sta SN                  ; expect $A0 (bank unchanged by the neighbours)
        rts
        ; READ1 ($F040) — the JANE fingerprint AD F1 FF 60. It is part of the
        ; STUB (replicated in every bank) because `lda $1FF1` pages bank 1 in on
        ; that very access, so the following `rts` is fetched from bank 1 and
        ; must be the identical $60 there. Referenced by the READ1 constant
        ; (a bare label here would multiply-define across the four expansions).
        lda H_B1                ; AD F1 FF : read $1FF1 -> bank 1
        rts                     ; 60
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        CLEAN_START
        TEST_BEGIN

        jsr PROBE                       ; collect a signature after every strobe
        ASSERT_EQ S0, $A0, $01          ; write $1FF0 -> bank 0
        ASSERT_EQ S1, $B1, $02          ; read  $1FF1 -> bank 1 (fingerprint path)
        ASSERT_EQ S2, $C2, $03          ; write $1FF8 -> bank 2
        ASSERT_EQ S3, $D3, $04          ; read  $1FF9 -> bank 3
        ASSERT_EQ SH, $A0, $05          ; write $1FF0 returned home
        ASSERT_EQ SN, $A0, $06          ; neighbours did not switch

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

; ------------------------------------------------------------ banks 1..3 (data)
; Each carries the identical stub (execution crosses into it on a switch) plus a
; distinct mid-bank signature.
        SEG BANK1
        ORG $1000
        RORG $F000
        STUB
        ORG $1C00
        RORG $FC00
        .byte $B1                       ; bank 1 signature
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

        SEG BANK2
        ORG $2000
        RORG $F000
        STUB
        ORG $2C00
        RORG $FC00
        .byte $C2                       ; bank 2 signature
        ORG $2FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

        SEG BANK3
        ORG $3000
        RORG $F000
        STUB
        ORG $3C00
        RORG $FC00
        .byte $D3                       ; bank 3 signature
        ORG $3FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
