; dpc-window-reads — reads of the DPC's random-number/music window ($F000-$F007)
; must not move the data fetchers.
;
; The DPC ("Display Processor Chip", Pitfall II) decides to decrement a fetcher
; only from reads in $008-$03F (US Patent 4,644,495 Fig. 3). The low window
; $000-$007 belongs to the random-number generator and the music amplitude:
; reading it returns those values and, by the patent decode, moves no fetcher —
; a program can poll the generator all day without disturbing its display
; pointers.
;
; The fetcher mechanism — an 11-bit down-counter, destructive reads, and a
; graphics ROM laid out so a counter holding c returns the byte
; f(c) = (c XOR (c >> 4)) AND $FF — is explained in dpc-fetch. Registers are
; reached through the $F000-$F07F mirror, the low window at $F000-$F007.
;
; This is the one documented divergence the rest of the DPC set designs around:
; some implementations re-use their register-read path for $F000-$F007 and
; decrement the fetcher whose number matches the low address bits (and re-check
; its flag), so polling the generator at $F002 silently walks DF2's pointer. Every
; other DPC test avoids the low window to stay deterministic; this test aims at
; exactly that quirk and asserts the patent decode. Pitfall II's own polling hides
; the difference, so the edge is untested on hardware.
;
;   CODE $01 = baseline: DF2 data read wrong (expected f($155) — plumbing)
;        $02 = four random-number reads ($F002) moved DF2's pointer (the next data
;              read must be f($154), the patent decode; a fetcher-decrementing
;              window read leaves the pointer at $150 and returns f($150))
;        $03 = the same, against the flag: after re-parking with Top set for
;              a masked read, four random-number reads must not have re-evaluated
;              or moved anything — the masked read returns f($31) with the flag
;              still set from its Top edge
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8               ; touch -> select program bank 0 (mirror of $1FF8)

; DPC register file, addressed through the $F000-$F07F mirror (+x picks DFx).
RNG2     = $F002              ; RNG value read; per the patent touches no fetcher
                              ;   (the quirk under test decrements DF2 here)
DATA     = $F008              ; read DFx data, unmasked; decrements the pointer
MASKED   = $F010              ; read DFx data AND flag; also decrements
TOP      = $F040              ; write DFx Top (also clears the flag)
BOTTOM   = $F048              ; write DFx Bottom
CLOW     = $F050              ; write DFx counter low (bits 7-0)
CHIGH    = $F058              ; write DFx counter high (bits 10-8)

V1       = $90                ; captured readbacks
V2       = $91
V3       = $92

ENTRY    = $F080              ; reset target, byte-identical in both banks

        MAC ENTRYSTUB
        bit HOTSPOT0
        jmp Main
        ENDM

; ---------------------------------------------------------------- bank 0 (home)
        SEG BANK0
        ORG $0000
        RORG $F000
        ds 128                 ; $F000-$F07F: DPC register window, no code/vectors
        ENTRYSTUB              ; ENTRY ($F080)
Main:
        CLEAN_START
        TEST_BEGIN

        ; --- cell 01: baseline plumbing — DF2 parked and read once
        lda #$55
        sta CLOW+2             ; DF2 counter low  = $55
        lda #$01
        sta CHIGH+2            ; DF2 counter high = $01 -> c = $155
        lda DATA+2             ; output f($155)=$40, pointer -> $154
        sta V1
        ASSERT_EQ V1, $40, $01

        ; --- cell 02: four RNG reads must not move DF2's pointer
        lda RNG2               ; RNG read (value discarded) — patent: no fetcher
        lda RNG2               ;   strobe fires for $000-$007
        lda RNG2
        lda RNG2
        lda DATA+2             ; patent decode: pointer still $154 -> f($154)=$41
        sta V2                 ;   (a fetcher-decrementing window read walked it
                               ;    to $150 and returns f($150)=$45 instead)
        ASSERT_EQ V2, $41, $02

        ; --- cell 03: nor may they disturb the flag latch
        lda #$32
        sta TOP+2              ; Top = $32 (the write clears the flag)
        lda #$10
        sta BOTTOM+2           ; Bottom = $10
        lda #$00
        sta CHIGH+2
        lda #$33
        sta CLOW+2             ; c = $033, one above Top
        lda DATA+2             ; low $33 (flag clear), pointer -> $32
        lda MASKED+2           ; low $32 == Top: flag sets, output f($32), ptr -> $31
        lda RNG2               ; four more RNG reads: per the patent neither the
        lda RNG2               ;   pointer nor the flag latch moves
        lda RNG2
        lda RNG2
        lda MASKED+2           ; flag still set, pointer still $31 -> f($31)=$32
        sta V3
        ASSERT_EQ V3, $32, $03

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1
        SEG BANK1
        ORG $1000
        RORG $F000
        ds 128                 ; register-window shadow (never CPU-visible)
        ENTRYSTUB              ; byte-identical entry at $F080
        ORG $1FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ------------------------------------------------- 2K display ROM + 256B pad
; File offset o carries f($7FF - o), so a fetcher at counter c returns
; display[$7FF - c] = f(c), f(c) = (c ^ (c >> 4)) & $FF. The trailing 256
; bytes bring the image to the canonical 10496-byte DPC size.
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
