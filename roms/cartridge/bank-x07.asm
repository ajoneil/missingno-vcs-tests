; bank-x07 — the X07 board (homebrew, "Stella's Stocking"; 64K, 16 4K banks)
; has two independent switch mechanisms; the second one fires on ordinary TIA
; writes.
;
; The cartridge answers every access with address line A12 high: the 4K window
; $F000-$FFFF, filled from one of 16 banks. The board also watches the whole low
; space $0000-$0FFF (it forwards TIA and RIOT accesses through) for two patterns.
;
; Mechanism (a) — direct select. The board acts when A12=0, A11=1 and the low
; nibble (A3-A0) is $D. The bank number comes from address bits A7-A4, which are
; outside the compare, so each bank b has a base hotspot (an address the board
; watches; touching it switches banks) at $080D + (b * 16):
;       $080D->0  $081D->1  $082D->2 ... $08ED->14  $08FD->15
; A10,A9,A8 are don't-cares, so $0C5D, $0A5D and $095D all also select bank 5.
;
; Mechanism (b) — TIA-shadow select. The board also acts when A12, A11 and A7 are
; all 0 — true of almost every TIA register access ($00-$7F) — but only while the
; current bank is already 14 or 15. Address bit A6 then picks the new bank:
;       A6 = 0  ->  bank 14        A6 = 1  ->  bank 15
; The TIA register is still written; the bank flip is a side effect. So `sta
; COLUBK` as $09 (A6=0) parks bank 14, and as its $49 mirror (A6=1) parks bank 15
; — the same store, two banks, chosen by A6.
;
; Because of mechanism (b), a render kernel cannot live in bank 14 or 15: it
; writes TIA constantly, and every such write would move the bank under it. Real
; X07 carts keep their kernels in the low banks for this reason.
;
;   CODE $01 = write $081D did not page in bank 1
;        $02 = write $085D did not page in bank 5
;        $03 = read  $08ED did not page in bank 14
;        $04 = read  $08FD did not page in bank 15
;        $05 = alias $0C5D did not page in bank 5 (A10 don't-care)
;        $06 = near-miss $080C wrongly switched from bank 5 (low nibble $C, not $D)
;        $07 = TIA write $49 (A6=1) from bank 14 did not flip to bank 15
;        $08 = TIA write $09 (A6=0) from bank 15 did not flip to bank 14
;        $09 = TIA read  $49 (A6=1) from bank 14 did not flip to bank 15 (reads too)
;        $0A = TIA write $49 from low bank 3 wrongly switched (needs bank 14/15)
;
; Self-test: verdict in RESULT ($80); region-independent.
;
; mapper: X07

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SEL0    = $080D                 ; direct-select bank 0 (LDA form AD 0D 08 = X07 id byte pattern)
SEL1    = $081D                 ; direct-select bank 1
SEL5    = $085D                 ; direct-select bank 5
SEL14   = $08ED                 ; direct-select bank 14 (read: RIOT-forward, benign)
SEL15   = $08FD                 ; direct-select bank 15 (read: RIOT-forward, benign)
SEL3    = $083D                 ; direct-select bank 3 (a low bank)
ALIAS5  = $0C5D                 ; A10 don't-care twin of $085D -> bank 5
MISS    = $080C                 ; mechanism-a near-miss (low nibble $C) -> no switch
TIAHI   = $49                   ; TIA COLUBK mirror, A6=1 -> shadow-selects bank 15
TIALO   = $09                   ; TIA COLUBK,        A6=0 -> shadow-selects bank 14
SIG     = $FC00                 ; per-bank signature ($A0+bank), mid-bank

ENTRY   = $F000                 ; stub entry (reset target), identical in all 16 banks
PROBE   = $F006                 ; probe routine (jsr target), after the 6-byte entry

; probe result cells (all $90+, so A7=1 and their stores never trip mechanism (b))
B1      = $90                   ; write $081D -> bank 1
B5      = $91                   ; write $085D -> bank 5
B14     = $92                   ; read  $08ED -> bank 14
B15     = $93                   ; read  $08FD -> bank 15
BAL     = $94                   ; alias $0C5D -> bank 5
NM      = $95                   ; near-miss $080C -> stayed bank 5
SH15    = $96                   ; bank14 + TIA write A6=1 -> bank 15
SH14    = $97                   ; bank15 + TIA write A6=0 -> bank 14
SHR     = $98                   ; bank14 + TIA read  A6=1 -> bank 15
LOW     = $99                   ; bank3  + TIA write A6=1 -> no switch (stays 3)

; The shared stub — emitted byte-identical into all 16 banks so execution can
; cross a bank select and keep fetching valid code at the same address.
        MAC STUB
        lda SEL0                        ; ENTRY ($F000): power-on bank is undefined, but
                                        ;   mechanism (a) reaches any bank from anywhere
                                        ;   -> force bank 0 (also the id byte pattern)
        jmp Main                        ; ...then run the test (Main lives in bank 0)
        ; --- PROBE ($F006), entered in bank 0 ---
        ; Direct-select walk (mechanism a). Writes to low banks forward to TIA and
        ; are benign at A=0. Banks 14/15 are read-selected instead: their selects
        ; $08ED/$08FD have A7=1, which forwards to the RIOT, so a write there would
        ; poke RIOT RAM — a read is harmless.
        lda #0
        sta SEL1                        ; write $081D -> bank 1
        lda SIG
        sta B1
        sta SEL5                        ; write $085D -> bank 5 (A still 0)
        lda SIG
        sta B5
        bit SEL14                       ; read  $08ED -> bank 14
        lda SIG
        sta B14
        bit SEL15                       ; read  $08FD -> bank 15
        lda SIG
        sta B15
        bit ALIAS5                      ; read  $0C5D (A10 don't-care) -> bank 5
        lda SIG
        sta BAL
        ; mechanism-a near-miss: $080C differs from $080D only in A0 -> no match,
        ; and A11=1 keeps mechanism (b) out too, so parked bank 5 stays undisturbed.
        bit MISS
        lda SIG
        sta NM
        ; --- TIA-shadow switch (mechanism b): bites only when parked in 14/15 ---
        bit SEL14                       ; park bank 14
        lda #0
        sta TIAHI                       ; sta $49 : TIA write, A6=1 -> 14 flips to 15
        lda SIG
        sta SH15
        lda #0
        sta TIALO                       ; sta $09 : TIA write, A6=0 -> 15 flips to 14
        lda SIG
        sta SH14
        bit TIAHI                       ; bit $49 : a TIA read, A6=1 -> 14 flips to 15
        lda SIG
        sta SHR
        ; the same TIA write from a low bank matches mechanism (b) but is inert
        bit SEL3                        ; park bank 3 (low)
        lda #0
        sta TIAHI                       ; sta $49 : bank 3 is not 14/15 -> no switch
        lda SIG
        sta LOW
        lda SEL0                        ; Restore the home bank (bank 0) before returning:
                                        ;   the frame kernel and result screen write TIA
                                        ;   constantly, so the probe must leave a low bank
                                        ;   live or mechanism (b) would page under them.
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

        jsr PROBE
        ASSERT_EQ B1,   $A1, $01        ; write $081D -> bank 1
        ASSERT_EQ B5,   $A5, $02        ; write $085D -> bank 5
        ASSERT_EQ B14,  $AE, $03        ; read  $08ED -> bank 14
        ASSERT_EQ B15,  $AF, $04        ; read  $08FD -> bank 15
        ASSERT_EQ BAL,  $A5, $05        ; alias $0C5D -> bank 5
        ASSERT_EQ NM,   $A5, $06        ; near-miss $080C: stayed bank 5
        ASSERT_EQ SH15, $AF, $07        ; TIA write A6=1 from 14 -> bank 15
        ASSERT_EQ SH14, $AE, $08        ; TIA write A6=0 from 15 -> bank 14
        ASSERT_EQ SHR,  $AF, $09        ; TIA read  A6=1 from 14 -> bank 15
        ASSERT_EQ LOW,  $A3, $0A        ; TIA write from bank 3: no switch

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

; ------------------------------------------------------------ banks 1..15 (data)
; Each carries the identical stub (execution crosses into it on every select) plus
; a distinct signature $A0+bank. The macro emits stub + signature + vectors.
        MAC DATABANK            ; {1} = file base, {2} = signature byte
        SEG
        ORG {1}
        RORG $F000
        STUB
        ORG {1} + $0C00
        RORG $FC00
        .byte {2}
        ORG {1} + $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
        ENDM

        DATABANK $1000, $A1
        DATABANK $2000, $A2
        DATABANK $3000, $A3
        DATABANK $4000, $A4
        DATABANK $5000, $A5
        DATABANK $6000, $A6
        DATABANK $7000, $A7
        DATABANK $8000, $A8
        DATABANK $9000, $A9
        DATABANK $A000, $AA
        DATABANK $B000, $AB
        DATABANK $C000, $AC
        DATABANK $D000, $AD
        DATABANK $E000, $AE
        DATABANK $F000, $AF
