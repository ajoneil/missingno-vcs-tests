; bank-wd — the WD board (the "Wickstead Design" prototype for an unreleased Pink
; Panther cart) is an 8K scheme that maps four of its eight 1K banks into the 4K
; window at once, one per 1K segment, in an arrangement chosen from a fixed table.
; No segment is fixed.
;
; The cartridge window $F000-$FFFF is split into four 1K segments:
;   segment 0  $F000-$F3FF      segment 2  $F800-$FBFF
;   segment 1  $F400-$F7FF      segment 3  $FC00-$FFFF
;
; A read of TIA-space $30-$3F is a hotspot (an address the board watches): the
; low three bits of the address load one of eight arrangements, so $38-$3F repeat
; $30-$37. Each arrangement names the 1K bank placed in segments 0,1,2,3:
;   $30/$38 -> 0,0,1,3     $34/$3C -> 0,0,6,7
;   $31/$39 -> 0,1,2,3     $35/$3D -> 0,1,7,6
;   $32/$3A -> 4,5,6,7     $36/$3E -> 2,3,4,5
;   $33/$3B -> 7,4,2,3     $37/$3F -> 6,0,5,1
;
; The switch is delayed: the board latches the chosen arrangement and applies it
; about three CPU cycles after the hotspot read. A segment read taken right after
; the hotspot still returns the old bank; the new bank appears once the latch
; settles.
;
; The board also has 64 bytes of RAM: read port $F000-$F03F, write port
; $F040-$F07F (read-low, the opposite of a Superchip). The RAM overlaps the low
; 128 bytes of segment 0, so segment-0 ROM under it is unreachable.
;
;   CODE $01..$08 = segment signature wrong for bank 0..7 (each bank reached
;                   through some arrangement; $01=bank0 ... $08=bank7)
;        $09 = the $38-$3F mirror ($3B) did not select arrangement $33
;        $0A = RAM read-back (port $F000) wrong after a write to $F040
;        $0B = RAM read-back (port $F03F) wrong after a write to $F07F
;        $0C = delayed switch: after settling, the new bank did not appear
;        $0D = delayed switch: the immediate absolute read did not match the
;              settled bank — see the delay note below
;        $0E = a load of the write port ($F040) did not destroy RAM[$00]: with no
;              R/W line the board decodes direction from the address alone, takes
;              the load for a store, and latches the undriven bus ($F0, the
;              operand high byte) into the cell
;
; Delay note ($0C/$0D): the latch delay is shorter than a 6507 absolute read can
; catch — even the immediately following `lda abs` has its data cycle after the
; latch has settled, so both cells observe and assert the settled new bank. The
; exact latch edge is untested on hardware.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: WD

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

; segment signature read addresses (in-bank offset $3F8, per segment)
SEG0 = $F3F8
SEG1 = $F7F8
SEG2 = $FBF8
SEG3 = $FFF8

; RAM ports
RAMWR = $F040                   ; write port base ($F040-$F07F)
RAMRD = $F000                   ; read port base  ($F000-$F03F)

ENTRY = $FC00                   ; reset target (segment-3 code, replicated)
PROBE = $FC05                   ; probe routine, after the 5-byte entry

; probe result cells (bank k signature -> Sk); harness owns $80-$89
S0   = $90
S1   = $91
S2   = $92
S3   = $93
S4   = $94
S5   = $95
S6   = $96
S7   = $97
SM   = $98                      ; signature via the $3B mirror (expect bank4 $A4)
RV0  = $99                      ; RAM read-back from $F000 (expect $5A)
RV1  = $9A                      ; RAM read-back from $F03F (expect $C3)
DLYN = $9B                      ; delayed switch, settled read (expect $A4, new)
DLYO = $9C                      ; delayed switch, immediate read (measured old/new)
GHOST= $9D                      ; RAM[$00] after a load landed on its write port

; SETTLE — let a pending arrangement latch resolve (well over the board's ~3-4
; cycle arrangement delay) before trusting a segment read.
        MAC SETTLE
        nop
        nop
        nop
        ENDM

; ---------------------------------------------------------------------------
; WDCODE — the segment-3 entry + probe, emitted byte-identical into every bank
; that can occupy segment 3 during the walk (3, 6, 5). Straight-line only (no
; labels) so it can expand three times. {1}=file base, {2}=this bank's signature.
        MAC WDCODE
        ORG {1}
        RORG $FC00
; ENTRY ($FC00): power-on arrangement is undefined (implementations commonly wake
; in $30, which also keeps bank 3 in segment 3), so re-select home arrangement $31
; via its $39 mirror (A5 39 4C is the WD fingerprint) and run the harness in
; bank 0 / segment 0.
        lda $39                 ; A5 39 : select arrangement $31 = (0,1,2,3)
        jmp Main                ; 4C .. .. : Main lives in bank 0
; PROBE ($FC05): walk the banks. Entered under home $31 (segment 3 = bank 3).
        lda $31                 ; ensure home $31
        SETTLE
        lda SEG0
        sta S0                  ; seg0 = bank0 -> $A0
        lda SEG1
        sta S1                  ; seg1 = bank1 -> $A1
        lda SEG2
        sta S2                  ; seg2 = bank2 -> $A2
        lda SEG3
        sta S3                  ; seg3 = bank3 -> $A3
        ; arrangement $33 = (7,4,2,3): seg3 stays bank3, read seg0=7, seg1=4
        lda $33
        SETTLE
        lda SEG0
        sta S7                  ; seg0 = bank7 -> $A7
        lda SEG1
        sta S4                  ; seg1 = bank4 -> $A4
        lda $31                 ; home
        SETTLE
        ; arrangement $35 = (0,1,7,6): seg3 -> bank6 (replicated), read own seg3
        lda $35
        SETTLE                  ; segment 3 flips bank3 -> bank6 here
        lda SEG3
        sta S6                  ; seg3 = bank6 -> $A6
        lda $31                 ; home (executes from bank6, identical code)
        SETTLE
        ; arrangement $36 = (2,3,4,5): seg3 -> bank5 (replicated), read own seg3
        lda $36
        SETTLE                  ; segment 3 flips bank3 -> bank5 here
        lda SEG3
        sta S5                  ; seg3 = bank5 -> $A5
        lda $31                 ; home
        SETTLE
        ; mirror: $3B selects $33 (via the $38-$3F mirror); read seg1 = bank4
        lda $3B
        SETTLE
        lda SEG1
        sta SM                  ; expect $A4 (mirror selected $33)
        lda $31                 ; home
        SETTLE
        ; delayed switch probe: strobe $33 (seg1 bank1 -> bank4); an immediate
        ; seg1 read should still show the old bank, a settled read the new bank.
        lda $33                 ; strobe (seg3 stays bank3, probe survives)
        lda SEG1                ; immediate (within the pending window)
        sta DLYO
        SETTLE
        lda SEG1                ; settled
        sta DLYN                ; expect $A4 (new = bank4)
        lda $31                 ; home before returning
        SETTLE
        rts
        ; --- per-bank tail: signature at $FFF8, vectors at $FFFC ---
        ORG {1}+$3F8
        RORG $FFF8
        .byte {2}               ; segment-3 signature for this bank
        .byte $FF
        ORG {1}+$3FC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
        ENDM

; DATABANK — a plain data bank: the same two-instruction boot stub as the code
; banks at $FC00 (so a power-on arrangement that parks a data bank in segment 3
; still boots — $37 does this with bank 1, $32/$34 with bank 7), signature at
; in-bank offset $3F8, vectors at the end.
        MAC DATABANK
        ORG {1}
        RORG $FC00
        lda $39                 ; select home arrangement $31 = (0,1,2,3)
        jmp Main                ; runs from segment 3 while the latch settles
        ORG {1}+$3F8
        RORG $FFF8
        .byte {2}
        .byte $FF
        ORG {1}+$3FC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
        ENDM

; ---------------------------------------------------------------- bank 0 (home / harness)
; Segment 0 under home arrangement $31 = (0,1,2,3), which lays banks 0,1,2,3 out
; as the four quarters of an ordinary 4K image — so under $31 the cart reads as a
; plain 4K program, and the harness (Main, asserts, result screen) runs entirely
; under it. The RAM read port shadows $F000-$F03F and the write port $F040-$F07F,
; so real code starts at $F080. Signature $A0 at offset $3F8.
        SEG BANK0
        ORG $0000
        RORG $F000
        ds $80, $FF                     ; $F000-$F07F: RAM shadow (unreachable ROM)
Main:
        CLEAN_START                     ; (entry has selected home $31)
        TEST_BEGIN

        jsr PROBE                       ; walk the eight banks, collect signatures

        ; RAM ports (read-low): write then read back through the two ports
        lda #$5A
        sta RAMWR                       ; write RAM[$00] via the write port
        lda #$C3
        sta RAMWR+$3F                   ; write RAM[$3F]
        lda RAMRD                       ; read RAM[$00] via the read port
        sta RV0
        lda RAMRD+$3F                   ; read RAM[$3F]
        sta RV1

        ASSERT_EQ S0, $A0, $01          ; bank 0 (home seg0)
        ASSERT_EQ S1, $A1, $02          ; bank 1 (home seg1)
        ASSERT_EQ S2, $A2, $03          ; bank 2 (home seg2)
        ASSERT_EQ S3, $A3, $04          ; bank 3 (home seg3)
        ASSERT_EQ S4, $A4, $05          ; bank 4 (via $33 seg1)
        ASSERT_EQ S5, $A5, $06          ; bank 5 (via $36 seg3)
        ASSERT_EQ S6, $A6, $07          ; bank 6 (via $35 seg3)
        ASSERT_EQ S7, $A7, $08          ; bank 7 (via $33 seg0)
        ASSERT_EQ SM, $A4, $09          ; $3B mirror selected $33
        ASSERT_EQ RV0, $5A, $0A         ; RAM read-back low
        ASSERT_EQ RV1, $C3, $0B         ; RAM read-back high
        ASSERT_EQ DLYN, $A4, $0C        ; settled switch shows the new bank
        ASSERT_EQ DLYO, $A4, $0D        ; immediate abs read already shows the new bank
                                        ;   (latch resolves within the next fetch; see header)

        ; --- a load of the write port destroys the cell ---
        ; Runs last: it clobbers RAM[$00], which $0A reads. The board decodes
        ; direction from the address alone, so it takes this load for a store and
        ; latches the undriven bus — the operand high byte $F0.
        lda RAMWR                       ; AD 40 F0 : LOAD the write port -> ghost store
        lda RAMRD                       ; RAM[$00] back through the read port
        sta GHOST
        ASSERT_EQ GHOST, $F0, $0E       ; RAM[$00] holds the residue, not $5A

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $03F8
        RORG $F3F8
        .byte $A0                       ; bank 0 signature (seg0 read at $F3F8)
        ORG $03FC
        RORG $F3FC
        .byte $FF, $FF, $FF, $FF        ; pad bank 0 to its 1K boundary

; --------------------------------------------------------- banks 1,2 (data)
        SEG BANK1
        DATABANK $0400, $A1
        SEG BANK2
        DATABANK $0800, $A2

; --------------------------------------------------------- bank 3 (home segment-3 code)
        SEG BANK3
        WDCODE $0C00, $A3

; --------------------------------------------------------- bank 4 (data)
        SEG BANK4
        DATABANK $1000, $A4

; --------------------------------------------------------- banks 5,6 (data + replicated probe)
        SEG BANK5
        WDCODE $1400, $A5
        SEG BANK6
        WDCODE $1800, $A6

; --------------------------------------------------------- bank 7 (data)
        SEG BANK7
        DATABANK $1C00, $A7
