; bank-df — a 128K homebrew cart of thirty-two 4K banks: EF doubled.
;
; DF works exactly like EF (see bank-ef for the full explanation and the terms
; hotspot, strobe, and mirror), with twice the banks. It holds thirty-two 4K
; banks in the 4K window $F000-$FFFF, and its thirty-two hotspots sit one nibble
; lower than EF's, at $1FC0-$1FDF:
;
;   access $1FC0+n  ->  show bank n     (bank 0 at $1FC0, bank 31 at $1FDF)
;
; A select fires on the bus access alone: read or write, the data value does not
; matter. The same selects also answer at the mirror $FFC0-$FFDF. "DF" is the
; high nibble pair of the hotspot address. Each bank holds a one-byte signature
; ($A0+bank, $A0..$BF) at $FC00, clear of the hotspots and vectors; the signatures
; are how the test names the bank it is looking at.
;
; Unlike EF and BF, DF has a defined power-on bank: the board comes up showing
; bank 15, so the start bank is a pass/fail cell here rather than a diagnostic.
;
; Plain DF has no cartridge RAM, but the DFSC variant (and some DF implementations
; always) map 128 bytes of SuperChip RAM over $F000-$F0FF: writes land at
; $F000-$F07F, reads at $F080-$F0FF. This image stays clear of that window, so it
; boots the same whether $F000-$F0FF is ROM (plain DF) or RAM (SuperChip).
;
;   CODE $01/$02 = write/read strobe did not page bank 0
;        $03/$04 = write/read strobe did not page bank 1
;        $05/$06 = write/read strobe did not page bank 16 (a middle bank)
;        $07/$08 = write/read strobe did not page bank 30
;        $09/$0A = write/read strobe did not page bank 31 (the last)
;        $0B = the below-first edge ($1FBF) wrongly paged a bank
;        $0C = the above-last edge ($1FE0) wrongly paged a bank
;        $0D = the thirty-two-bank sweep checksum was wrong (a bank was missed)
;        $0E = the power-on/start bank was not bank 15
;   OBSERVED = the signature of the power-on/start bank
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DF

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

NB      = 32                    ; bank count
HOT     = $1FC0                 ; hotspot base: HOT+n selects bank n ($1FC0..$1FDF)
EDGELO_ = HOT-1                 ; $1FBF: just below the first hotspot (must be inert)
EDGEHI_ = HOT+NB               ; $1FE0: just above the last hotspot (must be inert)
SIG     = $FC00                 ; per-bank signature ($A0+bank), mid-bank

B0      = 0
B1      = 1
BMID    = 16
BPEN    = NB-2                  ; 30
BLAST   = NB-1                  ; 31
BEDGE   = 5
BSTART  = 15                    ; DF's defined power-on bank
CHKEXP  = (NB*$A0 + (NB*(NB-1))/2) & $FF   ; sum of all signatures, mod 256

ENTRY   = $F100                ; reset target (above the SC RAM window); every bank
PROBE   = $F115                ; jsr target: the probe, just after the fixed entry

W0=$90
R0=$91
W1=$92
R1=$93
WM=$94
RM=$95
WP=$96
RP=$97
WL=$98
RL=$99
ELO=$9A
EHI=$9B
CHK=$9C
STARTSIG=$9D

; The shared stub — byte-identical in all thirty-two banks at the same address, so
; execution can cross a select and keep fetching valid code. Based at $F100, clear
; of the $F000-$F0FF SuperChip RAM window either way (the first 256 bytes of each
; bank are unused). Each cell strobes a hotspot (write or read) then reads the
; now-paged signature; a board that decoded only writes would fail every
; read-strobe cell.
        MAC STUB
        ; --- ENTRY ($F100): observe the start bank, then force the home bank ---
        CLEAN_START
        lda SIG
        sta STARTSIG
        bit HOT                ; force bank 0 (the harness home)
        jmp Main
        ; --- PROBE ($F115): walk the banks from home, then return home ---
        sta HOT+B0
        nop
        lda SIG
        sta W0
        bit HOT+B0
        nop
        lda SIG
        sta R0
        sta HOT+B1
        nop
        lda SIG
        sta W1
        bit HOT+B1
        nop
        lda SIG
        sta R1
        sta HOT+BMID
        nop
        lda SIG
        sta WM
        bit HOT+BMID
        nop
        lda SIG
        sta RM
        sta HOT+BPEN
        nop
        lda SIG
        sta WP
        bit HOT+BPEN
        nop
        lda SIG
        sta RP
        sta HOT+BLAST
        nop
        lda SIG
        sta WL
        bit HOT+BLAST
        nop
        lda SIG
        sta RL
        ; hotspot-range edges: park in bank BEDGE, prove neither edge pages out
        sta HOT+BEDGE
        nop
        bit EDGELO_
        nop
        lda SIG
        sta ELO
        bit EDGEHI_
        nop
        lda SIG
        sta EHI
        ; full sweep: visit every bank via an indexed strobe, sum the signatures —
        ; one missed bank changes the checksum
        lda #0
        sta CHK
        ldx #0
.sw     lda HOT,x
        lda SIG
        clc
        adc CHK
        sta CHK
        inx
        cpx #NB
        bne .sw
        bit HOT                ; sweep left us in the last bank -> force home
        rts
        ENDM

; a data bank: 256-byte RAM-window gap + identical stub + signature + vectors
        MAC DBANK
        ORG {1}*$1000
        RORG $F000
        ds 256
        STUB
        ORG {1}*$1000+$C00
        RORG $FC00
        .byte $A0+{1}
        ORG {1}*$1000+$FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        ds 256                          ; $F000-$F0FF: unused / SC RAM window
        STUB
Main:
        TEST_BEGIN
        jsr PROBE
        ASSERT_EQ W0, $A0+B0,   $01
        ASSERT_EQ R0, $A0+B0,   $02
        ASSERT_EQ W1, $A0+B1,   $03
        ASSERT_EQ R1, $A0+B1,   $04
        ASSERT_EQ WM, $A0+BMID, $05
        ASSERT_EQ RM, $A0+BMID, $06
        ASSERT_EQ WP, $A0+BPEN, $07
        ASSERT_EQ RP, $A0+BPEN, $08
        ASSERT_EQ WL, $A0+BLAST,$09
        ASSERT_EQ RL, $A0+BLAST,$0A
        ASSERT_EQ ELO, $A0+BEDGE, $0B
        ASSERT_EQ EHI, $A0+BEDGE, $0C
        ASSERT_EQ CHK, CHKEXP,  $0D
        ASSERT_EQ STARTSIG, $A0+BSTART, $0E   ; power-on bank is 15 (defined)
        lda STARTSIG
        sta OBSERVED
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0+B0
        ; one DF detection path reads bank 0's $FFF8 (file offset $0FF8) for `DFSC`.
        ORG $0FF8
        RORG $FFF8
        .byte "DFSC"
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; --------------------------------------------------------- banks 1..30 (data)
        DBANK 1
        DBANK 2
        DBANK 3
        DBANK 4
        DBANK 5
        DBANK 6
        DBANK 7
        DBANK 8
        DBANK 9
        DBANK 10
        DBANK 11
        DBANK 12
        DBANK 13
        DBANK 14
        DBANK 15
        DBANK 16
        DBANK 17
        DBANK 18
        DBANK 19
        DBANK 20
        DBANK 21
        DBANK 22
        DBANK 23
        DBANK 24
        DBANK 25
        DBANK 26
        DBANK 27
        DBANK 28
        DBANK 29
        DBANK 30

; ------------------------------------------------------ bank 31 (last + marker)
; The last bank carries `DFDF` in the image's last eight bytes ($FFF8), the mark
; the other DF detection path scans for (last 8 bytes of the whole image). DF is
; fingerprinted two ways, so the image carries both marks (`DFSC` at bank 0's
; $FFF8, `DFDF` here) to satisfy either.
        SEG BANK31
        ORG $1F000
        RORG $F000
        ds 256
        STUB
        ORG $1F000+$C00
        RORG $FC00
        .byte $A0+BLAST
        ORG $1F000+$FF8
        RORG $FFF8
        .byte "DFDF"
        ORG $1F000+$FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
