; bank-ef — a 64K homebrew cart of sixteen 4K banks, chosen by a block of
; sixteen hotspots. It scales the F-series bank-select scheme up to 64K.
;
; The cartridge answers every access with address line A12 high: the 4K window
; $F000-$FFFF. A 64K cart holds sixteen 4K banks and shows one in that window at
; a time. Which one is set by a hotspot (an address the board watches; touching
; it switches banks). EF's sixteen hotspots sit at $1FE0-$1FEF:
;
;   access $1FE0+n  ->  show bank n     (bank 0 at $1FE0, bank 15 at $1FEF)
;
; A select fires on the bus access alone: read or write, the data value does not
; matter; an access made only to fire a select is a strobe. The board decodes only
; 13 address lines, so the same sixteen selects also answer at the mirror
; $FFE0-$FFEF (a mirror is a second address range that reaches the same place).
; "EF" is the high nibble pair of the hotspot address.
;
; The switch takes effect on the next bus cycle, so the instruction fetched just
; after a select already comes from the new bank. Each bank holds a one-byte
; signature ($A0+bank, i.e. $A0..$AF) at a fixed mid-bank address ($FC00), clear
; of the hotspots and vectors so reading it never pages. The signatures are how
; the test names the bank it is looking at.
;
;   CODE $01/$02 = write/read strobe did not page bank 0
;        $03/$04 = write/read strobe did not page bank 1
;        $05/$06 = write/read strobe did not page bank 8 (a middle bank)
;        $07/$08 = write/read strobe did not page bank 14
;        $09/$0A = write/read strobe did not page bank 15 (the last)
;        $0B = the below-first edge ($1FDF) wrongly paged a bank
;        $0C = the above-last edge ($1FF0) wrongly paged a bank
;        $0D = the sixteen-bank sweep checksum was wrong (a bank was missed)
;   OBSERVED = the signature of the power-on/start bank. Diagnostic only, not a
;              pass/fail cell: the power-on bank is undefined and some
;              implementations disagree on it.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: EF

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

NB      = 16                    ; bank count
HOT     = $1FE0                 ; hotspot base: HOT+n selects bank n ($1FE0..$1FEF)
EDGELO_ = HOT-1                 ; $1FDF: just below the first hotspot (must be inert)
EDGEHI_ = HOT+NB               ; $1FF0: just above the last hotspot (must be inert)
SIG     = $FC00                 ; per-bank signature ($A0+bank), mid-bank

; sampled banks (first, second, a middle, the last two) and the edge-park bank
B0      = 0
B1      = 1
BMID    = 8
BPEN    = NB-2                  ; 14
BLAST   = NB-1                  ; 15
BEDGE   = 5
CHKEXP  = (NB*$A0 + (NB*(NB-1))/2) & $FF   ; sum of all signatures, mod 256

ENTRY   = $F000                ; reset target; identical stub in every bank
PROBE   = $F015                ; jsr target: the probe, just after the fixed entry

; ZP scratch: probe readbacks. STARTSIG ($9D) is filled in the entry (before the
; probe) and must survive jsr PROBE, so it sits clear of $90-$9C.
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

; The shared stub — byte-identical in all sixteen banks so execution can cross a
; bank select and keep fetching valid code at the same address. The entry is a
; fixed size so PROBE is a constant address (labels here would be multiply
; defined across the sixteen expansions).
        MAC STUB
        ; --- ENTRY ($F000): observe the start bank, then force the home bank ---
        CLEAN_START            ; clears RAM; touches no hotspot -> live bank kept
        lda SIG                ; the live (power-on) bank's signature
        sta STARTSIG           ; stash it (RAM is clean now) for the diagnostic
        bit HOT                ; force bank 0 (the harness home)
        jmp Main
        ; --- PROBE ($F015): walk the banks from home, then return home ---
        ; Each cell: strobe a hotspot (write or read), then read the now-paged
        ; signature. A dummy nop lets the switch settle before the signature read.
        ; A board that decoded only writes would fail every read-strobe cell.
        sta HOT+B0             ; bank 0 via write strobe
        nop
        lda SIG
        sta W0
        bit HOT+B0             ; bank 0 via read strobe
        nop
        lda SIG
        sta R0
        sta HOT+B1             ; bank 1
        nop
        lda SIG
        sta W1
        bit HOT+B1
        nop
        lda SIG
        sta R1
        sta HOT+BMID           ; a middle bank
        nop
        lda SIG
        sta WM
        bit HOT+BMID
        nop
        lda SIG
        sta RM
        sta HOT+BPEN           ; penultimate bank
        nop
        lda SIG
        sta WP
        bit HOT+BPEN
        nop
        lda SIG
        sta RP
        sta HOT+BLAST          ; last bank
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
        bit EDGELO_            ; below first hotspot -> must stay in BEDGE
        nop
        lda SIG
        sta ELO
        bit EDGEHI_            ; above last hotspot  -> must stay in BEDGE
        nop
        lda SIG
        sta EHI
        ; full sweep: visit every bank via an indexed strobe, sum the signatures —
        ; one missed bank changes the checksum, and the loop keeps the source small
        lda #0
        sta CHK
        ldx #0
.sw     lda HOT,x              ; strobe bank X (also reads; A discarded next)
        lda SIG                ; bank X's signature
        clc
        adc CHK
        sta CHK
        inx
        cpx #NB
        bne .sw
        bit HOT                ; sweep left us in the last bank -> force home
        rts
        ENDM

; a data bank: identical stub + signature + vectors, at file base {1}*$1000
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
        TEST_BEGIN             ; CLEAN_START already ran in the entry
        jsr PROBE              ; walk the banks
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
        ASSERT_EQ ELO, $A0+BEDGE, $0B   ; below-first edge did not page out
        ASSERT_EQ EHI, $A0+BEDGE, $0C   ; above-last edge did not page out
        ASSERT_EQ CHK, CHKEXP,  $0D     ; the sweep visited every bank
        lda STARTSIG
        sta OBSERVED           ; record the (divergent) power-on bank; diagnostic
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0+B0                    ; bank 0 signature
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; --------------------------------------------------------- banks 1..14 (data)
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

; ------------------------------------------------------ bank 15 (last + marker)
; The last bank carries the `EFEF` ASCII marker in its last eight bytes ($FFF8),
; just below the vectors — the tail marker EF board-detection scans for (the last
; eight bytes of the image, the strong form). $FFFA-B is the 6507's unused NMI
; slot, so the marker overwrites nothing live.
        SEG BANK15
        ORG $F000
        RORG $F000
        STUB
        ORG $FC00
        RORG $FC00
        .byte $A0+BLAST
        ORG $FFF8
        RORG $FFF8
        .byte "EFEF"
        ORG $FFFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
