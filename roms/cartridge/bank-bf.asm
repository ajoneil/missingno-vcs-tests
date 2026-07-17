; bank-bf — a 256K homebrew cart of sixty-four 4K banks: the widest of the
; EF/DF/BF family.
;
; BF works exactly like EF (see bank-ef for the full explanation and the terms
; hotspot, strobe, and mirror), with the most banks. It holds sixty-four 4K banks
; in the 4K window $F000-$FFFF, and its sixty-four hotspots widen to the block
; $1F80-$1FBF:
;
;   access $1F80+n  ->  show bank n     (bank 0 at $1F80, bank 63 at $1FBF)
;
; A select fires on the bus access alone: read or write, the data value does not
; matter. The same selects also answer at the mirror $FF80-$FFBF. "BF" is the
; high nibble pair of the hotspot address. Each bank holds a one-byte signature
; ($A0+bank, $A0..$DF) at $FC00, clear of the hotspots and vectors; the signatures
; are how the test names the bank it is looking at.
;
;   CODE $01/$02 = write/read strobe did not page bank 0
;        $03/$04 = write/read strobe did not page bank 1
;        $05/$06 = write/read strobe did not page bank 32 (a middle bank)
;        $07/$08 = write/read strobe did not page bank 62
;        $09/$0A = write/read strobe did not page bank 63 (the last)
;        $0B = the below-first edge ($1F7F) wrongly paged a bank
;        $0C = the above-last edge ($1FC0) wrongly paged a bank
;        $0D = the sixty-four-bank sweep checksum was wrong (a bank was missed)
;   OBSERVED = the signature of the power-on/start bank. Diagnostic only, not a
;              pass/fail cell: the power-on bank is undefined and some
;              implementations disagree on it.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: BF

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

NB      = 64                    ; bank count
HOT     = $1F80                 ; hotspot base: HOT+n selects bank n ($1F80..$1FBF)
EDGELO_ = HOT-1                 ; $1F7F: just below the first hotspot (must be inert)
EDGEHI_ = HOT+NB               ; $1FC0: just above the last hotspot (must be inert)
SIG     = $FC00                 ; per-bank signature ($A0+bank), mid-bank

B0      = 0
B1      = 1
BMID    = 32
BPEN    = NB-2                  ; 62
BLAST   = NB-1                  ; 63
BEDGE   = 5
CHKEXP  = (NB*$A0 + (NB*(NB-1))/2) & $FF   ; sum of all signatures, mod 256

ENTRY   = $F000
PROBE   = $F015

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

; The shared stub — byte-identical in all sixty-four banks at the same address, so
; execution can cross a select and keep fetching valid code. Each cell strobes a
; hotspot (write or read) then reads the now-paged signature; a board that decoded
; only writes would fail every read-strobe cell.
        MAC STUB
        ; --- ENTRY ($F000): observe the start bank, then force the home bank ---
        CLEAN_START
        lda SIG
        sta STARTSIG
        bit HOT                ; force bank 0 (the harness home)
        jmp Main
        ; --- PROBE ($F015): walk the banks from home, then return home ---
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

        MAC DBANK
        ORG {1}*$1000
        RORG $F000
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
        lda STARTSIG
        sta OBSERVED
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0+B0
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; --------------------------------------------------------- banks 1..62 (data)
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
        DBANK 31
        DBANK 32
        DBANK 33
        DBANK 34
        DBANK 35
        DBANK 36
        DBANK 37
        DBANK 38
        DBANK 39
        DBANK 40
        DBANK 41
        DBANK 42
        DBANK 43
        DBANK 44
        DBANK 45
        DBANK 46
        DBANK 47
        DBANK 48
        DBANK 49
        DBANK 50
        DBANK 51
        DBANK 52
        DBANK 53
        DBANK 54
        DBANK 55
        DBANK 56
        DBANK 57
        DBANK 58
        DBANK 59
        DBANK 60
        DBANK 61
        DBANK 62

; ------------------------------------------------------ bank 63 (last + marker)
; The last bank carries `BFBF` in the image's last eight bytes ($FFF8): BF
; board-detection scans either the image's last eight bytes or the whole image,
; so this single mark serves both paths. $FFFA-B is the unused NMI slot.
        SEG BANK63
        ORG $3F000
        RORG $F000
        STUB
        ORG $3F000+$C00
        RORG $FC00
        .byte $A0+BLAST
        ORG $3F000+$FF8
        RORG $FFF8
        .byte "BFBF"
        ORG $3F000+$FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
