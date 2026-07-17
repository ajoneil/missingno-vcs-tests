; bank-03e0 — the 03E0 board (Brazilian Parker Bros, 8K) is an E0-style board
; whose three pageable 1K windows are selected from active-low hotspots down in
; low memory, not from hotspots in the cartridge window.
;
; Like E0, the board cuts the 6507's 4K window ($F000-$FFFF) into four 1K
; segments and fills the first three from a pool of eight 1K slices; the fourth
; is fixed:
;   $F000-$F3FF  segment 0  <- one of slices 0..7
;   $F400-$F7FF  segment 1  <- one of slices 0..7
;   $F800-$FBFF  segment 2  <- one of slices 0..7
;   $FC00-$FFFF  segment 3  <- always slice 7 (holds the code)
;
; E0's select hotspots (addresses the board watches for an access) live inside
; the fixed slice ($1FE0..$1FF7); 03E0's live in low memory at $0380-$03FF, and
; the decode is active-low (a line being low, not high, enables it). One access
; can touch all three selects at once: each segment's select is enabled by its
; own address line being low, and loads the slice named by the low three address
; bits A0-A2:
;       A4 low  ->  segment 0 <- slice (A0-A2)
;       A5 low  ->  segment 1 <- slice (A0-A2)
;       A6 low  ->  segment 2 <- slice (A0-A2)
; To move one segment, hold the other two enable lines high:
;       $03E0+N  ->  segment 0 <- slice N   (A4=0, A5=1, A6=1)
;       $03D0+N  ->  segment 1 <- slice N   (A5=0, A4=1, A6=1)
;       $03B0+N  ->  segment 2 <- slice N   (A6=0, A4=1, A5=1)
; With all three enables low, one access pages every segment at once:
;       $0380+N  ->  segments 0,1,2 all <- slice N
; With all three high, nothing moves:
;       $03F0+N  ->  no segment selected (A4=A5=A6=1)
; A select fires on the bus access — read or write, data irrelevant.
;
;   CODE $01 = $03E1 did not page slice 1 into segment 0
;        $02 = $03E2 did not page slice 2 into segment 0
;        $03 = $03D3 did not page slice 3 into segment 1
;        $04 = write $03D5 did not page slice 5 into segment 1 (writes select too)
;        $05 = $03B4 did not page slice 4 into segment 2
;        $06 = write $03B6 did not page slice 6 into segment 2
;        $07 = paging segment 0 disturbed segment 1 (segments not independent)
;        $08 = paging segment 0 disturbed segment 2
;        $09 = fixed segment 3 was not the last slice (slice 7)
;        $0A = combined select $0383 did not page slice 3 into segment 0
;        $0B = combined select $0383 did not page slice 3 into segment 1
;        $0C = combined select $0383 did not page slice 3 into segment 2
;        $0D = near-miss $03F0 (all enables high) wrongly moved segment 0
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: 03E0

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

; signature read addresses (in-slice offset $3F8, per window)
WIN0   = $F3F8
WIN1   = $F7F8
WIN2   = $FBF8
FIXSIG = $FFF8                  ; slice 7's signature, seen in the fixed segment 3

; probe result cells (harness owns $80-$89; scratch is $90+)
W0S1   = $90                    ; segment 0 <- slice 1
W0S2   = $91                    ; segment 0 <- slice 2
W1S3   = $92                    ; segment 1 <- slice 3 (read strobe)
W1S5   = $93                    ; segment 1 <- slice 5 (write strobe)
W2S4   = $94                    ; segment 2 <- slice 4 (read strobe)
W2S6   = $95                    ; segment 2 <- slice 6 (write strobe)
INDEP1 = $96                    ; segment 1 after re-paging segment 0
INDEP2 = $97                    ; segment 2 after re-paging segment 0
FIXED  = $98                    ; the fixed segment-3 signature
COMB0  = $99                    ; combined select: segment 0
COMB1  = $9A                    ; combined select: segment 1
COMB2  = $9B                    ; combined select: segment 2
NMISS  = $9C                    ; near-miss: segment 0 must be untouched

; ---------------------------------------------------------------- slice 0 (harness)
        SEG SLICE0
        ORG $0000
        RORG $F000
Main:
        CLEAN_START            ; (entry has already paged slice 0 into segment 0)
        TEST_BEGIN

        jsr PROBE              ; strobe every segment, collect signatures (in slice 7)

        ASSERT_EQ W0S1, $A1, $01        ; $03E1 -> slice 1 in segment 0
        ASSERT_EQ W0S2, $A2, $02        ; $03E2 -> slice 2 in segment 0
        ASSERT_EQ W1S3, $A3, $03        ; $03D3 -> slice 3 in segment 1
        ASSERT_EQ W1S5, $A5, $04        ; write $03D5 -> slice 5 in segment 1
        ASSERT_EQ W2S4, $A4, $05        ; $03B4 -> slice 4 in segment 2
        ASSERT_EQ W2S6, $A6, $06        ; write $03B6 -> slice 6 in segment 2
        ASSERT_EQ INDEP1, $A3, $07      ; segment 1 kept slice 3 while segment 0 moved
        ASSERT_EQ INDEP2, $A4, $08      ; segment 2 kept slice 4 while segment 0 moved
        ASSERT_EQ FIXED, $A7, $09       ; segment 3 is always slice 7
        ASSERT_EQ COMB0, $A3, $0A       ; $0383 paged slice 3 into segment 0
        ASSERT_EQ COMB1, $A3, $0B       ; ...and segment 1
        ASSERT_EQ COMB2, $A3, $0C       ; ...and segment 2
        ASSERT_EQ NMISS, $A1, $0D       ; $03F0 moved nothing (segment 0 still slice 1)

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $03F8
        RORG $F3F8
        .byte $A0                      ; slice 0 signature
        ds 7, $FF                      ; pad slice 0 to its 1K boundary

; a pure-data slice: non-uniform header + signature at offset $3F8
        MAC DATASLICE          ; {1}=file base, {2}=signature byte
        ORG {1}
        RORG $F000
        .byte $03, {2}                 ; header bytes (dodge a phantom-Superchip fingerprint)
        ds ($3F8-2), $00               ; gap to the signature offset
        .byte {2}                      ; signature at in-slice offset $3F8
        ds 7, $FF                      ; pad to the 1K boundary
        ENDM

; ------------------------------------------------------------ slices 1..6 (data)
        SEG SLICE1
        DATASLICE $0400, $A1
        SEG SLICE2
        DATASLICE $0800, $A2
        SEG SLICE3
        DATASLICE $0C00, $A3
        SEG SLICE4
        DATASLICE $1000, $A4
        SEG SLICE5
        DATASLICE $1400, $A5
        SEG SLICE6
        DATASLICE $1800, $A6

; ----------------------------------------------------------- slice 7 (fixed code)
; Always mapped at $FC00-$FFFF (segment 3). Holds the reset entry, the probe
; (every opcode here is fetched from the fixed segment, so it survives a page),
; slice 7's own signature, and the vectors. The hotspots are in low memory, so
; the code here never has to dodge them.
        SEG SLICE7
        ORG $1C00
        RORG $FC00
ENTRY:                        ; power-on segment config is undefined -> force a
                              ;   known slice into all three pageable segments
        lda $03E0             ; segment 0 <- slice 0 (the harness; too big to share
                              ;   slice 7 with the probe, so it lives in slice 0)
        lda $03D0             ; segment 1 <- slice 0 (known baseline)
        lda $03B0             ; segment 2 <- slice 0
        jmp Main              ; run the harness from segment 0 (slice 0)

; PROBE — walk the three segments, storing each slice's signature. The hotspots
; ($0380-$03FF) fall in the RIOT I/O region (address lines A7 and A9 high), so each
; strobe also reaches the 6532; the write strobes keep A=$00, and no frame is drawn.
PROBE:
        ; segment 0: two read-strobe selects
        lda $03E1             ; segment 0 <- slice 1
        lda WIN0
        sta W0S1             ; expect $A1
        lda $03E2             ; segment 0 <- slice 2
        lda WIN0
        sta W0S2             ; expect $A2
        ; segment 1: a read strobe then a write strobe (both must page)
        lda $03D3            ; segment 1 <- slice 3 (read)
        lda WIN1
        sta W1S3            ; expect $A3
        lda #0
        sta $03D5            ; segment 1 <- slice 5 (write)
        lda WIN1
        sta W1S5            ; expect $A5
        ; segment 2: read then write strobe
        lda $03B4           ; segment 2 <- slice 4 (read)
        lda WIN2
        sta W2S4           ; expect $A4
        lda #0
        sta $03B6           ; segment 2 <- slice 6 (write)
        lda WIN2
        sta W2S6           ; expect $A6
        ; independence: set a known config, then re-page segment 0 only
        lda $03E1           ; segment 0 <- slice 1
        lda $03D3           ; segment 1 <- slice 3
        lda $03B4           ; segment 2 <- slice 4
        lda $03E2           ; re-page segment 0 <- slice 2 (only segment 0 moves)
        lda WIN1
        sta INDEP1          ; segment 1 still slice 3 -> $A3
        lda WIN2
        sta INDEP2          ; segment 2 still slice 4 -> $A4
        ; fixed segment 3 = slice 7 always
        lda FIXSIG
        sta FIXED           ; $A7
        ; combined select: all three enables low pages every segment at once
        lda $0383           ; segments 0,1,2 <- slice 3
        lda WIN0
        sta COMB0           ; $A3
        lda WIN1
        sta COMB1           ; $A3
        lda WIN2
        sta COMB2           ; $A3
        ; near-miss: all three enables high selects nothing
        lda $03E1           ; segment 0 <- slice 1 (park a known slice)
        lda $03F0           ; A4=A5=A6=1 -> no select
        lda WIN0
        sta NMISS           ; segment 0 still slice 1 -> $A1
        ; restore segment 0 <- slice 0 (harness) so the rts lands on real code
        lda $03E0
        rts

        ORG $1FF8
        RORG $FFF8
        .byte $A7                      ; slice 7 signature (read at $FFF8 in segment 3)
        .byte $FF                      ; $FFF9 filler
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY
