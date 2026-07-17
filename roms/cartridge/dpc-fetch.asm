; dpc-fetch — the DPC's eight display fetchers and how they read the 2K graphics
; ROM. This is the reference header for the fetcher mechanism; the other dpc-*
; tests point here instead of repeating it.
;
; The DPC ("Display Processor Chip") is the custom chip in Pitfall II: Lost
; Caverns. It holds a 2K graphics ROM and eight address generators called
; "fetchers" (DF0-DF7), and it sits next to an 8K F8-banked program ROM whose
; chip-enable it controls.
;
; A fetcher is an 11-bit counter that counts down. The CPU cannot read the
; graphics ROM directly. It reads a fetcher's data port; the chip returns the
; graphics byte the counter points at, then decrements the counter. So reading
; a data port has a side effect: it moves the pointer on by one. The order is
; fixed — form the output byte from the current count, then decrement.
;
; The chip has no clock and no read/write line. It decides to decrement purely
; from the address of the read: any read in $008-$03F, seen by the CPU through
; the $F008-$F03F mirror (a mirror is a second address range that reaches the
; same registers).
;
; The graphics ROM is stored backwards. A fetcher holding value c returns the
; file byte at offset ($7FF - (c AND $7FF)). This ROM fills the 2K block so that
; the byte a fetcher returns for counter c is a fixed function of c:
;
;       f(c) = (c XOR (c >> 4)) AND $FF
;
; Two properties make faults visible: neighbouring counter values give different
; bytes (a stuck pointer shows up), and f(0)=$00 differs from f($7FF)=$80 (the
; 11-bit wrap shows up). The expected values below are f(c) for each cell's
; counter.
;
; Registers live at $1000-$107F, reached through the $F000-$F07F mirror. The
; chip is outside the F8-banked program ROM (see dpc-bank).
;
;   read  $F008+x   data (unmasked)      returns byte, then decrements
;   read  $F010+x   data AND flag        returns byte, then decrements (flag: dpc-flag)
;   write $F050+x   counter low  (bits 7-0)
;   write $F058+x   counter high (bits 10-8)
;
;   CODE $01 = DF0 read 1 wrong (expected f($155), the byte at counter $155)
;        $02 = DF0 read 2 wrong (expected f($154): pointer did not decrement once)
;        $03 = DF0 read 3 wrong (expected f($153): pointer did not decrement again)
;        $04 = 11-bit wrap wrong (counter $000 read then wrap to $7FF)
;        $05 = fetchers not independent (a DF0/DF1 read moved the other's pointer)
;        $06 = the read formats do not share one pointer (unmasked vs masked)
;        $07 = counter-high did not select the 2K page (DF3 counter $534)
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: DPC

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

HOTSPOT0 = $FFF8               ; touch -> select program bank 0 (mirror of $1FF8)
HOTSPOT1 = $FFF9               ; touch -> select program bank 1 (mirror of $1FF9)

; DPC register file, addressed through the $F000-$F07F mirror (+x picks DFx).
; These windows are the core every implementation shares: no read of $F000-$F007
; (the random-number/music window), no music (counter-high writes keep D4/D5=0),
; and none of the transformed read windows (see dpc-swizzle, dpc-shift).
DATA     = $F008              ; read DFx data, unmasked; decrements the pointer
MASKED   = $F010             ; read DFx data AND flag; also decrements
TOP      = $F040             ; write DFx Top   (start count)
BOTTOM   = $F048             ; write DFx Bottom (end count)
CLOW     = $F050             ; write DFx counter low  (bits 7-0)
CHIGH    = $F058             ; write DFx counter high (bits 10-8; DF4=$F05C, DF5-7=$F05D-F)

V1       = $90               ; captured readbacks
V2       = $91
V3       = $92
V4       = $93

ENTRY    = $F080             ; reset target, byte-identical in both banks (clear of $F000-$F07F)

; Byte-identical entry in both banks: force bank 0 (power-on bank is undefined),
; then run Main (which lives in bank 0). Touching $FFF8 switches the bank on the
; next bus cycle, so the following jmp is fetched from the newly-paged bank 0.
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

        ; --- cells 01-03: one fetcher, three reads, pointer decrements each read
        lda #$55
        sta CLOW+0             ; DF0 counter low  = $55
        lda #$01
        sta CHIGH+0            ; DF0 counter high = $01  -> c = $155
        lda DATA+0             ; read 1: output f($155), then pointer -> $154
        sta V1
        lda DATA+0             ; read 2: output f($154), then pointer -> $153
        sta V2
        lda DATA+0             ; read 3: output f($153), then pointer -> $152
        sta V3
        ASSERT_EQ V1, $40, $01 ; f($155)
        ASSERT_EQ V2, $41, $02 ; f($154) — proves one decrement
        ASSERT_EQ V3, $46, $03 ; f($153) — proves a second decrement

        ; --- cell 04: 11-bit wrap 0 -> $7FF
        lda #$00
        sta CLOW+0
        sta CHIGH+0            ; DF0 c = $000
        lda DATA+0             ; output f(0)=$00, pointer 0 -> wraps to $7FF
        sta V1
        lda DATA+0             ; output f($7FF)=$80 (distinct from f(0): wrap is real)
        sta V2
        ASSERT_EQ V1, $00, $04
        ASSERT_EQ V2, $80, $04

        ; --- cell 05: DF0 and DF1 are independent pointers
        lda #$20
        sta CLOW+0
        lda #$00
        sta CHIGH+0           ; DF0 c = $020
        lda #$C4
        sta CLOW+1
        lda #$03
        sta CHIGH+1           ; DF1 c = $3C4
        lda DATA+0            ; DF0 -> f($020)=$22, DF0 pointer -> $01F
        sta V1
        lda DATA+1           ; DF1 -> f($3C4)=$F8, DF1 pointer -> $3C3
        sta V2
        lda DATA+0           ; DF0 -> f($01F)=$1E (DF1's reads left DF0 alone)
        sta V3
        lda DATA+1          ; DF1 -> f($3C3)=$FF (DF0's reads left DF1 alone)
        sta V4
        ASSERT_EQ V1, $22, $05
        ASSERT_EQ V2, $F8, $05
        ASSERT_EQ V3, $1E, $05
        ASSERT_EQ V4, $FF, $05

        ; --- cell 06: all read formats share one pointer (unmasked + masked)
        ; Set DF2 Top = counter-low so the flag is guaranteed set on the first
        ; read (low == Top); Bottom out of the way so it stays set. Reads through
        ; two different windows must return consecutive bytes off the same pointer.
        lda #$C8
        sta TOP+2            ; write Top (also clears the flag)
        lda #$00
        sta BOTTOM+2         ; Bottom = $00 (won't be reached here)
        lda #$C8
        sta CLOW+2
        lda #$00
        sta CHIGH+2          ; DF2 c = $0C8, low == Top
        lda DATA+2           ; unmasked: flag sets at low==Top, output f($C8)=$C4, ptr->$C7
        sta V1
        lda MASKED+2         ; masked: flag still set -> data f($C7)=$CB, ptr->$C6
        sta V2
        lda DATA+2           ; unmasked: f($C6)=$CA — the masked read advanced the same ptr
        sta V3
        ASSERT_EQ V1, $C4, $06
        ASSERT_EQ V2, $CB, $06
        ASSERT_EQ V3, $CA, $06

        ; --- cell 07: counter-high selects the 2K page (bits 10-8)
        lda #$34
        sta CLOW+3
        lda #$05
        sta CHIGH+3          ; DF3 c = $534
        lda DATA+3           ; f($534)=$67 — high byte $05 reached page 5 of the ROM
        sta V1
        ASSERT_EQ V1, $67, $07

        PASS_TEST

        include "frame.asm"
        include "result_screen.asm"

        ORG $0FFC
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ---------------------------------------------------------------- bank 1 (data)
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
; display[$7FF - c] = f(c). The trailing 256 bytes bring the image to the
; canonical 10496-byte size by which a DPC image is recognised.
        SEG DISPLAY
        ORG $2000
DPCDATA:
        REPEAT 2048
            .byte ((($7FF - (. - DPCDATA)) ^ (($7FF - (. - DPCDATA)) >> 4)) & $FF)
        REPEND
        ORG $2800
        ds 256, $00
