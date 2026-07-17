; bank-sb — the SB "SuperBanking" board: a 128K cart of thirty-two 4K banks,
; chosen from low memory instead of from the cartridge window.
;
; The cartridge answers every access with address line A12 high: the 4K window
; $F000-$FFFF (its $1000-$1FFF image). That window is plain ROM and never
; switches. SB puts its bank selects down in the $0800-$0FFF range instead. The
; board watches just two address lines plus the low five:
;
;   A12=0 and A11=1  ->  this access is a bank select
;   low 5 bits       ->  the bank number (0..31)
;
; A select fires on the bus access alone: read or write, the data value does not
; matter. Lines A8-A10 are ignored in the compare, so every $100 page from $0800
; to $0F00 is a mirror of the same select (a mirror is a second address that
; reaches the same place): $0805, $0905, ... all pick bank 5.
;
; The selects sit inside TIA/RIOT space ($0800-$0FFF), so a strobe (a bus access
; made only to trigger a select) also pokes those chips as a side effect.
;
; No document defines which bank SB shows at power-on. The test records the
; bank it wakes in without judging it: OBSERVED carries that bank's signature,
; and the green pass screen displays the byte (pass_result_observed).
;
;   CODE $01/$02 = write/read strobe did not page bank 0
;        $03/$04 = write/read strobe did not page bank 1
;        $05/$06 = write/read strobe did not page bank 16 (a middle bank)
;        $07/$08 = write/read strobe did not page bank 30
;        $09/$0A = write/read strobe did not page bank 31 (the last)
;        $0B = the $0805 select did not page bank 5
;        $0C = the $0905 mirror did not page bank 5 (A8-A10 don't-cares)
;        $0D = write near-miss $07FF (A11=0) wrongly switched
;        $0E = read near-miss $1000 (A12=1, the ROM window) wrongly switched
;        $0F = the thirty-two-bank sweep checksum was wrong (a bank was missed)
;   OBSERVED = the signature of the power-on/start bank (recorded, not asserted)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: SB

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

NB      = 32                    ; bank count
HOME    = $0800                 ; select base: HOME+n (A8-A10 don't-care) selects bank n
MIRROR  = $0900                 ; a $100-page mirror of the same selects
NMLO    = $07FF                 ; near-miss below $0800 (A11=0): must not switch
NMHI    = $1000                 ; near-miss in the ROM window (A12=1): must not switch
SIG     = $FC00                 ; per-bank signature ($A0+bank), mid-bank

B0      = 0
B1      = 1
BMID    = 16
BPEN    = NB-2                  ; 30
BLAST   = NB-1                  ; 31
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
MIR1=$9A
MIR2=$9B
NM1=$9C
NM2=$9D
CHK=$9E
STARTSIG=$9F

; The shared stub — byte-identical in all thirty-two banks at the same address, so
; code can cross a switch and keep fetching valid code. A stays $00 across the
; write strobes so the incidental TIA pokes are benign, and no frame is drawn
; while the probe runs, so the extra bus traffic does nothing visible.
        MAC STUB
        ; --- ENTRY ($F000): observe the start bank, then force home ---
        CLEAN_START
        lda SIG
        sta STARTSIG
        bit HOME               ; force bank 0 (the harness home)
        jmp Main
        ; --- PROBE ($F015): walk the banks from home, then return home ---
        ; write strobe (A=0) then read strobe (indexed lda) for each sampled bank
        lda #0
        sta HOME+B0            ; bank 0 via write strobe
        lda SIG
        sta W0
        ldx #B0
        lda HOME,x            ; bank 0 via read strobe (BD 00 08 fingerprint form)
        lda SIG
        sta R0
        lda #0
        sta HOME+B1            ; bank 1
        lda SIG
        sta W1
        ldx #B1
        lda HOME,x
        lda SIG
        sta R1
        lda #0
        sta HOME+BMID          ; a middle bank
        lda SIG
        sta WM
        ldx #BMID
        lda HOME,x
        lda SIG
        sta RM
        lda #0
        sta HOME+BPEN          ; penultimate bank
        lda SIG
        sta WP
        ldx #BPEN
        lda HOME,x
        lda SIG
        sta RP
        lda #0
        sta HOME+BLAST         ; last bank
        lda SIG
        sta WL
        ldx #BLAST
        lda HOME,x
        lda SIG
        sta RL
        ; mirror probe: $0805 and $0905 both page bank 5
        lda #0
        sta HOME+BMID          ; move off bank 5 first
        lda #0
        sta HOME+BEDGE         ; $0805 -> bank 5
        lda SIG
        sta MIR1
        lda #0
        sta HOME+BMID          ; move off again
        lda #0
        sta MIRROR+BEDGE       ; $0905 (mirror) -> bank 5
        lda SIG
        sta MIR2
        ; near misses: park in bank 5, prove neither address switches. The low
        ; near-miss uses a write strobe (A=0) — writes trigger SB too, so a write
        ; to $07FF that does not switch is the stronger inertness test, and it
        ; keeps the RIOT read it would otherwise do (divergent I/O bits) out of
        ; the trace. The high near-miss is a ROM read (deterministic).
        lda #0
        sta HOME+BEDGE
        sta NMLO               ; write $07FF (A11=0) -> must stay bank 5
        lda SIG
        sta NM1
        bit NMHI               ; read $1000 (ROM window, A12=1) -> must stay bank 5
        lda SIG
        sta NM2
        ; full sweep: visit every bank via the indexed read strobe, sum signatures
        lda #0
        sta CHK
        ldx #0
.sw     lda HOME,x             ; strobe bank X (BD 00 08); A discarded next
        lda SIG
        clc
        adc CHK
        sta CHK
        inx
        cpx #NB
        bne .sw
        lda #0
        sta HOME               ; sweep left us in the last bank -> force home
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
        ASSERT_EQ MIR1, $A0+BEDGE, $0B
        ASSERT_EQ MIR2, $A0+BEDGE, $0C
        ASSERT_EQ NM1, $A0+BEDGE,  $0D
        ASSERT_EQ NM2, $A0+BEDGE,  $0E
        ASSERT_EQ CHK, CHKEXP,  $0F
        lda STARTSIG            ; the power-on bank is recorded, not judged:
        sta OBSERVED            ; no document defines one for SB

RS_PASS_OBSERVED = 1            ; pass screen shows OBSERVED (the start bank)

        lda #$00
        sta CODE
        lda #PASS_MAGIC
        sta RESULT
        jmp pass_result_observed

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0+B0
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; --------------------------------------------------------- banks 1..31 (data)
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
