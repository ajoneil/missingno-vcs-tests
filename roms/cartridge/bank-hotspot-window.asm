; bank-hotspot-window — a data read near the bank-switch hotspots must come from
; the bank currently paged in; a read of a hotspot returns the bank it selects.
;
; This is an F8 board: two 4K banks, with $1FF8 selecting bank 0 and $1FF9
; selecting bank 1 (reached here at their $FFF8/$FFF9 mirror). The hotspots
; (the addresses the board watches; touching one switches banks) sit at the
; very top of the address space. Real data lives right beside them: jump
; tables, constants, the reset vectors.
;
; A read of, say, $FFE0 is therefore an ordinary data fetch two bytes from a
; live switch. It must return the byte from the bank paged in at that instant,
; and it must not switch banks — only $FFF8/$FFF9 do that. A board that
; resolved these reads from the wrong bank would hand back a stale byte and
; corrupt any table a game keeps up there.
;
; A read of a hotspot itself is the sharper case, because it switches and
; fetches in the same bus cycle. Per US Patents 4,368,515 and 4,432,067 the
; board decodes the address and flips a set/reset flip-flop while the hotspot
; address is still on the bus, and that flip-flop's output is the ROM's 13th
; address bit. So the bank changes during the very access that names it, and
; the ROM answers from the bank just selected — not the one it left. Each bank
; carries its own byte at the hotspots ($58/$59 in bank 0, $78/$79 in bank 1),
; so the two answers are told apart.
;
;   CODE $01..$05 = bank 0 read of $FFE0/$FFE7/$FFED/$FFF0/$FFF7 was wrong
;        $06..$0A = bank 1 read of $FFE0/$FFE7/$FFED/$FFF0/$FFF7 was wrong
;        $0B = read of $FFF8 from bank 1 did not page in bank 0
;        $0C = the $FFF8 read returned bank 1's byte ($78), the bank it left,
;              not bank 0's ($58), the bank it selected
;        $0D = read of $FFF9 from bank 0 did not page in bank 1
;        $0E = the $FFF9 read returned bank 0's byte ($59), the bank it left,
;              not bank 1's ($79), the bank it selected
;
; Hotspot bytes ($0C/$0E): a genuine Atari cartridge cannot show this. Atari's
; images hold a NOP ($EA) at $FFF8 and $FFF9 in both banks, so a hotspot read
; returns $EA whichever bank answers, and the question never comes up. This
; image gives each bank its own byte there instead — that is what lets the two
; cells see it. The board's answer follows from the patents above; it is
; untested on hardware, because the flip-flop sits inside the mask-ROM chip
; and its output reaches no pin a probe could touch.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: F8

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8               ; touch -> select bank 0 (mirror of $1FF8)
HOTSPOT1 = $FFF9               ; touch -> select bank 1 (mirror of $1FF9)
RDBASE   = $FF00               ; indexed base: lda RDBASE,x reads $FF00+x

ENTRY    = $F000               ; stub entry (reset target), identical in both banks
PROBE    = $F006               ; probe routine (jsr target), after the 6-byte entry

B0     = $90                   ; bank-0 readbacks for the five probe addresses ($90..$94)
B1     = $95                   ; bank-1 readbacks ($95..$99)
H8BYTE = $9A                   ; the byte the $FFF8 read returned (read from bank 1)
H8BANK = $9B                   ; the bank that read left paged in
H9BYTE = $9C                   ; the byte the $FFF9 read returned (read from bank 0)
H9BANK = $9D                   ; the bank that read left paged in

; The shared stub — emitted identically into both banks, so execution can cross a
; switch and keep fetching valid code at the same address. It pages in a bank and
; reads five addresses spanning the signature range through indexed loads
; (`lda $FF00,x`, BD 00 FF) rather than absolute `lda $FFE0` (AD E0 FF): the
; absolute form spells an $FFEx operand that cart auto-detectors scan for as an
; E0/E7 board fingerprint, which would misidentify this F8 image.
        MAC STUB
        bit HOTSPOT0            ; ENTRY ($F000): power-on bank is undefined -> force bank 0
        jmp Main                ; ...then run the test (Main lives in bank 0)
        ; PROBE ($F006): read each bank's high signature bytes.
        sta HOTSPOT0            ; select bank 0 (home)
        nop                     ; settle
        nop
        ldx #$E0
        lda RDBASE,x            ; $FFE0
        sta B0+0
        ldx #$E7
        lda RDBASE,x            ; $FFE7
        sta B0+1
        ldx #$ED
        lda RDBASE,x            ; $FFED
        sta B0+2
        ldx #$F0
        lda RDBASE,x            ; $FFF0
        sta B0+3
        ldx #$F7
        lda RDBASE,x            ; $FFF7
        sta B0+4
        sta HOTSPOT1            ; select bank 1 (next fetch is bank 1's identical stub)
        nop
        nop
        ldx #$E0
        lda RDBASE,x            ; $FFE0 under bank 1
        sta B1+0
        ldx #$E7
        lda RDBASE,x
        sta B1+1
        ldx #$ED
        lda RDBASE,x
        sta B1+2
        ldx #$F0
        lda RDBASE,x
        sta B1+3
        ldx #$F7
        lda RDBASE,x
        sta B1+4
        ; The hotspots' own bytes. Each is read twice: once for the byte the
        ; read drives, once for a signature naming the bank it left paged in.
        ; One reading alone is ambiguous: a board that answers from the bank it
        ; left and a board that never switches on a read both hand back $78.
        ; No settling nops here — at a hotspot the switch and the data fetch
        ; share one bus cycle, and each signature read has an ldx+lda ahead of
        ; it, a longer settle than the nop pair used above. The opcode fetch
        ; after each switch lands in the bank just selected; the stub is
        ; identical in both banks, so execution never derails.
        ldx #$F8                ; still in bank 1
        lda RDBASE,x            ; $FFF8: selects bank 0 and drives a byte
        sta H8BYTE              ; $58 (the bank it selected) or $78 (the one it left)
        ldx #$E0
        lda RDBASE,x
        sta H8BANK              ; the bank it left us in: expect $40 -> bank 0
        ldx #$F9                ; now in bank 0
        lda RDBASE,x            ; $FFF9: selects bank 1 and drives a byte
        sta H9BYTE              ; $79 (the bank it selected) or $59 (the one it left)
        ldx #$E0
        lda RDBASE,x
        sta H9BANK              ; the bank it left us in: expect $60 -> bank 1
        sta HOTSPOT0            ; back to the home bank
        nop
        nop
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

        jsr PROBE               ; collect both banks' high signatures
        ASSERT_EQ B0+0, $40, $01        ; bank 0 $FFE0
        ASSERT_EQ B0+1, $47, $02        ; bank 0 $FFE7
        ASSERT_EQ B0+2, $4D, $03        ; bank 0 $FFED
        ASSERT_EQ B0+3, $50, $04        ; bank 0 $FFF0
        ASSERT_EQ B0+4, $57, $05        ; bank 0 $FFF7
        ASSERT_EQ B1+0, $60, $06        ; bank 1 $FFE0
        ASSERT_EQ B1+1, $67, $07        ; bank 1 $FFE7
        ASSERT_EQ B1+2, $6D, $08        ; bank 1 $FFED
        ASSERT_EQ B1+3, $70, $09        ; bank 1 $FFF0
        ASSERT_EQ B1+4, $77, $0A        ; bank 1 $FFF7
        ASSERT_EQ H8BANK, $40, $0B      ; the $FFF8 read paged in bank 0
        ASSERT_EQ H8BYTE, $58, $0C      ; the $FFF8 read drove the bank it selected
        ASSERT_EQ H9BANK, $60, $0D      ; the $FFF9 read paged in bank 1
        ASSERT_EQ H9BYTE, $79, $0E      ; the $FFF9 read drove the bank it selected

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0FE0                       ; bank 0 signature: $FFE0-$FFF9 = $40..$59
        RORG $FFE0
        .byte $40,$41,$42,$43,$44,$45,$46,$47
        .byte $48,$49,$4A,$4B,$4C,$4D,$4E,$4F
        .byte $50,$51,$52,$53,$54,$55,$56,$57
        .byte $58,$59                   ; $FFF8/$FFF9: the hotspots' own bytes
        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
        SEG BANK1
        ORG $1000
        RORG $F000
        STUB
        ORG $1FE0                       ; bank 1 signature: $FFE0-$FFF9 = $60..$79
        RORG $FFE0
        .byte $60,$61,$62,$63,$64,$65,$66,$67
        .byte $68,$69,$6A,$6B,$6C,$6D,$6E,$6F
        .byte $70,$71,$72,$73,$74,$75,$76,$77
        .byte $78,$79                   ; $FFF8/$FFF9: the hotspots' own bytes
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
