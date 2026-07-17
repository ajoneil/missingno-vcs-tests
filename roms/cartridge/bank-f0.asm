; bank-f0 — the F0 board (Dynacom "Megaboy", 64K) holds sixteen 4K banks, and one
; hotspot steps through them in order; no address picks a bank directly.
;
; The cartridge answers every access that has address line A12 high: the 4K
; window $F000-$FFFF. F0 shows one of its sixteen 4K banks in that window at a
; time. It watches one hotspot (an address that, when touched, acts): $1FF0. Any
; access to it (a strobe) — read or write, the data value does not matter —
; advances the visible bank by one, wrapping from bank 15 back to bank 0.
;
; The cart decodes only 13 address lines, so the CPU reaches the hotspot through
; its $FFF0 mirror (a higher address the partial decode treats as the same one).
;
; Each bank stores a signature ($A0 + bank number, i.e. $A0..$AF) at a fixed
; mid-bank address ($FC00), clear of the hotspot so reading it never advances the
; bank. The signatures are how the test names the bank it is looking at.
;
;   CODE $01 = one strobe from bank 0 did not reach bank 1
;        $02 = two strobes did not reach bank 2
;        $03 = fifteen strobes did not reach bank 15
;        $04 = the sixteenth strobe did not wrap back to bank 0
;        $05 = a read of $1FF0 did not advance the bank (read must trigger too)
;        $06 = a write of $1FF0 did not advance the bank
;        $07 = a non-hotspot access ($1FF1/$1FF4/$1FF8/$1FFB) wrongly advanced it
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: F0

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT = $FFF0                 ; the single F0 hotspot (mirror of $1FF0): touch -> next bank
SIG     = $FC00                 ; per-bank signature ($A0 + bank#), mid-bank
SIG0    = $A0                   ; bank 0's signature (the sync landmark)

ENTRY   = $F000                 ; stub entry (reset target), identical in all 16 banks
PROBE   = $F012                 ; probe routine (jsr target), after the entry sync loop

C1      = $90                   ; sig after 1 strobe  (expect $A1)
C2      = $91                   ; sig after 2 strobes (expect $A2)
C3      = $92                   ; sig after 15 strobes(expect $AF)
C4      = $93                   ; sig after 16 strobes, wrapped (expect $A0)
C5      = $94                   ; sig after a read strobe  (expect $A1)
C6      = $95                   ; sig after a write strobe (expect $A2)
C7      = $96                   ; sig after non-hotspot strobes (expect $A2, unchanged)

; The shared stub — emitted byte-identical into all 16 banks so execution can
; cross a bank increment and keep fetching valid code at the same address.
; Strobes are written `sta $FFF0` (8D F0 FF); that byte pattern doubles as the
; detection fingerprint for a 64K F0 image.
        MAC STUB
        ; --- ENTRY ($F000): the power-on bank is undefined and F0 has no direct
        ; select, so step until bank 0's signature appears; only then is the bank
        ; position known and counting can begin. ---
        ldx #16                 ; A2 10 : bound the search to 16 steps (16 reach bank 0 from anywhere)
.sync:  lda SIG                 ; AD 00 FC : current bank's signature
        cmp #SIG0               ; C9 A0 : is this bank 0?
        beq .go                 ; F0 06
        sta HOTSPOT             ; 8D F0 FF : advance to the next bank (data irrelevant)
        dex                     ; CA
        bne .sync               ; D0 F3
.go:    jmp Main                ; 4C .. .. : bank 0 reached -> run the test
        ; --- PROBE ($F012): entered in bank 0 ---
        sta HOTSPOT             ; strobe 1 -> bank 1
        lda SIG
        sta C1                  ; expect $A1
        sta HOTSPOT             ; strobe 2 -> bank 2
        lda SIG
        sta C2                  ; expect $A2
        ldx #13                 ; advance 13 more (2 + 13 = 15)
.adv:   sta HOTSPOT
        dex
        bne .adv                ; now at bank 15
        lda SIG
        sta C3                  ; expect $AF
        sta HOTSPOT             ; strobe 16 -> wraps to bank 0
        lda SIG
        sta C4                  ; expect $A0 (wrap)
        ; reads advance too: a read of $1FF0 (from bank 0) -> bank 1
        bit HOTSPOT             ; 2C F0 FF : read $1FF0 -> bank 1
        lda SIG
        sta C5                  ; expect $A1
        sta HOTSPOT             ; write $1FF0 -> bank 2
        lda SIG
        sta C6                  ; expect $A2
        ; the neighbours of $1FF0 are not hotspots: bank must stay put
        bit $FFF1
        bit $FFF4
        bit $FFF8
        bit $FFFB
        lda SIG
        sta C7                  ; expect $A2 (unchanged)
        ; F0 has no direct select, and the cells above left us mid-way through
        ; the banks; step until bank 0's signature reappears so the rts lands on
        ; the bank-0 harness (same landmark discipline as the entry).
        ldx #16                 ; bounded, like the entry's search: a mapper
.home:  lda SIG                 ;   that stalls mid-walk gives a deterministic
        cmp #SIG0               ;   wrong-bank FAIL instead of hanging here
        beq .done
        sta HOTSPOT             ; advance toward bank 0
        dex
        bne .home
.done:  rts
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        STUB
Main:
        CLEAN_START
        TEST_BEGIN

        jsr PROBE                       ; walk all sixteen banks, sampling signatures
        ASSERT_EQ C1, $A1, $01          ; 1 strobe  -> bank 1
        ASSERT_EQ C2, $A2, $02          ; 2 strobes -> bank 2
        ASSERT_EQ C3, $AF, $03          ; 15 strobes-> bank 15
        ASSERT_EQ C4, $A0, $04          ; 16 strobes-> wrapped to bank 0
        ASSERT_EQ C5, $A1, $05          ; a read strobe advanced the bank
        ASSERT_EQ C6, $A2, $06          ; a write strobe advanced the bank
        ASSERT_EQ C7, $A2, $07          ; the non-hotspot neighbours did not advance

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0C00
        RORG $FC00
        .byte $A0                       ; bank 0 signature
        ORG $0FFA
        RORG $FFFA
        .word ENTRY
        .word ENTRY
        .word ENTRY

; ------------------------------------------------------------ banks 1..15 (data)
; Each carries the identical stub (execution crosses into it on every increment)
; plus a distinct signature. The macro emits stub + signature + vectors per bank.
        MAC DATABANK            ; {1} = file base, {2} = signature byte
        SEG
        ORG {1}
        RORG $F000
        STUB
        ORG {1} + $0C00
        RORG $FC00
        .byte {2}
        ORG {1} + $0FFA
        RORG $FFFA
        .word ENTRY
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
