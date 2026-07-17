; stack-aliases-ram — the 6507 stack is the zero-page RAM; page-1 pushes alias $0080-$00FF.
;
; The console's 128 bytes of RAM live in the RIOT chip (RAM-I/O-Timer). The
; 6507 CPU has only 13 address lines, and the board decodes just a few of them
; to pick which chip answers a bus access: with A12=0, A7=1 and A9=0 the RIOT
; RAM responds, and once it is selected only A0-A6 choose which of the 128 bytes.
; The RAM decode ignores A8, so it is a don't-care — addresses $01xx and $00xx
; that differ only in A8 name the same physical cell.
;
; This is why the stack works at all. The 6502 stack lives in page 1
; ($0100-$01FF), but the 2600 has no page-1 memory of its own; the upper half
; $0180-$01FF is just the RAM at $0080-$00FF seen through the ignored A8. PHA and
; PLA therefore read and write the very same 128 bytes the program uses as zero
; page.
;
; The test drives the stack into that aliased half and checks both directions:
;   - PUSH is a RAM write: with the stack pointer at $FF, PHA of $3C writes
;     $01FF, which must appear at its mirror RAM $00FF — and only there; the
;     neighbour cell $00FE must stay 0 (the alias is one exact cell, not a splat).
;   - PULL is a RAM read: a byte stored straight to RAM $00FE must be what PLA
;     pulls from $01FE.
;
;   CODE $01 = PHA to $01FF not visible at RAM mirror $00FF (stack not aliased)
;        $02 = the PHA also disturbed neighbour $00FE (alias not byte-exact)
;        $03 = PLA from $01FE did not read what was stored to RAM $00FE
;
; Self-test: verdict in RESULT ($80); region-independent.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

S_PHA   = $90                   ; scratch: value read back from the PHA mirror
S_NEI   = $91                   ; scratch: neighbour byte (negative control)
S_PLA   = $92                   ; scratch: value PLA pulled

        org $F000

Reset:
        CLEAN_START
        TEST_BEGIN

        ; --- PUSH is a RAM write: SP=$FF, PHA of $3C -> $01FF == RAM $00FF ---
        ldx #$FF
        txs                     ; stack pointer = $FF
        lda #$3C
        pha                     ; push -> $0100|$FF = $01FF   (RAM cell $00FF)
        lda $00FF               ; read that cell back through zero page
        sta S_PHA               ; must be $3C
        lda $00FE               ; the untouched neighbour cell
        sta S_NEI               ; must still be 0 (one exact cell, not a splat)

        ; --- PULL is a RAM read: store $C3 to RAM $00FE, pull from $01FE ---
        lda #$C3
        sta $00FE               ; write the cell through zero page
        ldx #$FD
        txs                     ; SP=$FD -> PLA reads $0100|($FD+1) = $01FE
        pla                     ; pull from $01FE   (RAM cell $00FE)
        sta S_PLA               ; must be $C3

        ldx #$FF                ; restore a sane stack: the assert helper (jsr)
        txs                     ; needs a working stack of its own

        ASSERT_EQ S_PHA, $3C, $01
        ASSERT_EQ S_NEI, $00, $02
        ASSERT_EQ S_PLA, $C3, $03
        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        org $FFFC
        .word Reset
        .word Reset
