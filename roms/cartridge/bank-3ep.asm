; bank-3ep — 3E+ rebuilds 3E around four independently banked 1K segments, so a
; program can mix ROM and RAM anywhere in the 4K window.
;
; 3E+ is a homebrew board, an evolution of the 3E RAM board (itself a RAM-bearing
; Tigervision descendant). It has no commercial title.
;
; The cartridge answers every access with address line A12 high: the 4K window
; $F000-$FFFF. 3E+ divides it into four 1K segments, each independently pointing
; at a ROM or RAM bank:
;   segment 0  $F000-$F3FF        segment 2  $F800-$FBFF
;   segment 1  $F400-$F7FF        segment 3  $FC00-$FFFF
;
; A single hotspot write both picks a segment and banks it (a hotspot is an
; address the board watches; touching it switches banks). The written value packs
; both: the top two bits are the segment number, the low six are the bank number.
; Which hotspot decides ROM or RAM:
;   write value (segment<<6)|bank to $3F  ->  that 1K ROM bank into that segment
;   write value (segment<<6)|bank to $3E  ->  that 512-byte RAM bank into it
; ROM banks are 1K, RAM banks 512 bytes. Unlike 3E, no segment is fixed — all
; four move — which lets the ROM image be any multiple of 1K without the board
; knowing its size.
;
; RAM is split into a read port and a write port. The cartridge edge has no
; read/write signal, so the board tells the direction from which address you
; touch. 3E+ puts the read port low within each segment: a RAM bank reads at the
; segment base and is written 512 bytes higher (segment 0: read $F000-$F1FF,
; write $F200-$F3FF; the other three follow the same shape). The test never reads
; a write port.
;
; Startup contract: only segment 3 has a defined power-on bank. It holds the reset
; vector at $FFFC, so it is set to ROM bank 0 at power-on and the machine can
; boot; the reset vector lives in the first 1K of the image.
;
;   CODE $01 = the startup contract is broken — segment 3 (the reset-vector
;              segment) is not ROM bank 0 at power-on
;        $02 = value (0<<6)|2 did not bank ROM bank 2 into segment 0
;        $03 = value (1<<6)|3 did not bank ROM bank 3 into segment 1
;        $04 = value (2<<6)|4 did not bank ROM bank 4 into segment 2
;        $05 = value (3<<6)|5 did not bank ROM bank 5 into segment 3 (via the hop)
;        $06 = segments are not independent — banking segment 1 disturbed the
;              bank showing in segment 0
;        $07 = RAM into a segment failed — a byte written to segment 0's write
;              port ($F3FF) did not read back at its read port ($F1FF)
;        $08 = two RAM banks in one segment are not distinct memory — a write to
;              RAM bank 1 bled into RAM bank 0
;        $09 = a mixed mapping failed — with segment 0 holding RAM, the ROM bank
;              in segment 1 did not keep its signature
;        $0A = selecting ROM back into the RAM segment did not evict the RAM —
;              the ROM signature did not return to segment 0
;
; The power-on state of segments 0-2 is contested and deliberately not asserted.
; The published spec says all four segments hold bank 0 at reset; some
; implementations instead leave 0-2 on arbitrary banks. The test asserts only the
; guaranteed part (segment 3 = bank 0, CODE $01) and selects every other segment's
; bank before reading it; segments 0-2 are untested on hardware.
;
; Self-test: verdict in RESULT ($80); region-independent.
; mapper: 3E+

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "result.h"

SIGOFF  = $3F0                  ; in-bank signature offset (read at <segbase>+$3F0)
S0SIG   = $F000+SIGOFF          ; segment 0 signature address ($F3F0)
S1SIG   = $F400+SIGOFF          ; segment 1 ($F7F0)
S2SIG   = $F800+SIGOFF          ; segment 2 ($FBF0)
S3SIG   = $FC00+SIGOFF          ; segment 3 ($FFF0)
S0_RD   = $F1FF                 ; segment 0 RAM read  port, cell 511 (base+$1FF)
S0_WR   = $F3FF                 ; segment 0 RAM write port, cell 511 (base+$200+$1FF)

; probe result cells (harness owns $80-$89; scratch lives at $90+)
ST3    = $90                    ; startup: segment 3 signature
WSEG0  = $91                    ; walk: segment 0 bank signature
WSEG1  = $92                    ; walk: segment 1
WSEG2  = $93                    ; walk: segment 2
WSEG3  = $94                    ; walk: segment 3 (via the hop)
INDEP  = $95                    ; segment 0 sig after banking segment 1 (independence)
RAMC   = $96                    ; segment 0 RAM cell 511 read back
RAMD   = $97                    ; segment 0 RAM bank 0 cell 511 after writing bank 1
MIX    = $98                    ; segment 1 ROM sig while segment 0 is RAM
EVICT  = $99                    ; segment 0 sig after re-selecting ROM (RAM evicted)

; ==================================================================== bank 0 (kernel)
; RORG $FC00: the kernel executes from segment 3 and is kept there all run. Its
; reset vector at $FFFC is fetched from segment 3 at power-on (segment 3 = bank 0),
; so the entry and vectors must live in this first 1K of the image.
        SEG BANK0
        ORG $0000
        RORG $FC00
ENTRY:
        CLEAN_START
        TEST_BEGIN

        jsr PROBE               ; all bus experiments; results -> console RAM $90+

        ; page the result screen (ROM bank 1) into segment 0, then assert — no
        ; assertion runs from a segment that was mid-experiment.
        lda #$01                ; (seg0<<6)|bank1 = $01 : segment 0 = display bank
        sta $3F

        ASSERT_EQ ST3,   $B0, $01       ; startup: segment 3 = bank 0
        ASSERT_EQ WSEG0, $B2, $02       ; walk segment 0 -> bank 2
        ASSERT_EQ WSEG1, $B3, $03       ; walk segment 1 -> bank 3
        ASSERT_EQ WSEG2, $B4, $04       ; walk segment 2 -> bank 4
        ASSERT_EQ WSEG3, $B5, $05       ; walk segment 3 -> bank 5 (hop)
        ASSERT_EQ INDEP, $B2, $06       ; segment 0 undisturbed by a segment-1 bank
        ASSERT_EQ RAMC,  $C7, $07       ; RAM read-low path (write $F3FF / read $F1FF)
        ASSERT_EQ RAMD,  $C7, $08       ; RAM bank 0 intact after writing RAM bank 1
        ASSERT_EQ MIX,   $B6, $09       ; ROM in segment 1 while segment 0 is RAM
        ASSERT_EQ EVICT, $B2, $0A       ; ROM back in segment 0 evicts the RAM

        PASS_TEST

; -------------------------------------------------------------------- PROBE
; Runs entirely from the kernel (segment 3). Repages segments 0/1/2 freely;
; reaches segment 3 only through the hop. Leaves every result in console RAM.
PROBE:
        ; cell $01 data — read segment 3's startup bank before touching anything
        lda S3SIG               ; segment 3 signature at power-on -> bank 0's $B0
        sta ST3

        ; cells $02-$04 — bank distinct ROM banks into segments 0, 1, 2
        lda #$02                ; (0<<6)|2
        sta $3F                 ; segment 0 = ROM bank 2
        lda S0SIG
        sta WSEG0
        lda #$43                ; (1<<6)|3
        sta $3F                 ; segment 1 = ROM bank 3
        lda S1SIG
        sta WSEG1
        lda #$84                ; (2<<6)|4
        sta $3F                 ; segment 2 = ROM bank 4
        lda S2SIG
        sta WSEG2

        ; cell $05 — segment 3 is the kernel's own segment; hop to a bank-0 copy
        ; in segment 0, bank segment 3 from there, then hop home.
        lda #$00                ; (0<<6)|0 : mirror bank 0 into segment 0
        sta $3F
        jmp hop_s3-$0C00        ; jump to the segment-0 alias of the hop body
                                ;   (bank 0 in segment 0 sits $0C00 below segment 3)
hop_s3:                         ; RORG $FCxx; executes at its $F0xx alias post-hop
        lda #$C5                ; (3<<6)|5
        sta $3F                 ; segment 3 = ROM bank 5 (safe: PC is in segment 0)
        lda S3SIG               ; read segment 3 -> bank 5's $B5
        sta WSEG3
        lda #$C0                ; (3<<6)|0
        sta $3F                 ; segment 3 = ROM bank 0 (kernel restored)
        jmp hop_home            ; back to segment-3 execution
hop_home:

        ; cell $06 — independence: bank segment 1, confirm segment 0 unchanged
        lda #$02                ; segment 0 = ROM bank 2
        sta $3F
        lda #$46                ; (1<<6)|6 : segment 1 = ROM bank 6
        sta $3F
        lda S0SIG               ; segment 0 still bank 2 -> $B2
        sta INDEP

        ; cell $07 — RAM into segment 0 (read-low, 512-byte bank); far cell 511
        ; covers the port split and offset alignment together.
        lda #$00                ; $3E value (0<<6)|0 : segment 0 = RAM bank 0
        sta $3E
        lda #$C7
        sta S0_WR               ; write cell 511 through the write port ($F3FF)
        lda S0_RD               ; read  cell 511 through the read  port ($F1FF)
        sta RAMC

        ; cell $08 — a second RAM bank in the same segment is distinct memory
        lda #$01                ; (0<<6)|1 : segment 0 = RAM bank 1
        sta $3E
        lda #$3C
        sta S0_WR               ; RAM bank 1 cell 511 = $3C
        lda #$00                ; (0<<6)|0 : back to RAM bank 0
        sta $3E
        lda S0_RD               ; cell 511 -> still $C7 (bank 1's write did not bleed)
        sta RAMD

        ; cell $09 — mixed: segment 0 is RAM, segment 1 is ROM bank 6; the ROM
        ; signature in segment 1 must be intact alongside the RAM.
        lda S1SIG               ; segment 1 ROM sig -> $B6
        sta MIX

        ; cell $0A — re-selecting ROM into segment 0 evicts the RAM
        lda #$02                ; (0<<6)|2 : segment 0 = ROM bank 2
        sta $3F
        lda S0SIG               ; ROM signature back -> $B2
        sta EVICT

        rts

        ; the TJ3E signature — the board designer's tag that 3E+ detection
        ; fingerprints. Pure data; never executed.
        .byte "TJ3E"

        ORG $0000+SIGOFF                ; kernel bank signature, read at $FFF0
        RORG $FC00+SIGOFF
        .byte $B0

        ORG $03FC                       ; reset vectors at the top of bank 0
        RORG $FFFC
        .word ENTRY
        .word ENTRY

; ================================================================= bank 1 (display)
; The result screen, paged into segment 0 for the assertion phase (RORG $F000).
; assert_eq / pass_result / fail_result and the hex font all resolve here; the
; kernel jsr/jmps into them once this bank is mapped.
        SEG BANK1
        ORG $0400
        RORG $F000
        include "result_screen.asm"
        ORG $0400+$3FF
        RORG $F3FF
        .byte $FF                       ; pad bank 1 to its 1K boundary

; ============================================================ banks 2-7 (ROM signatures)
; Pure data ROM banks used by the walk / independence / mixed cells. Each opens
; non-uniform (dodge a phantom-Superchip fingerprint) and carries its signature
; at in-bank offset $3F0.
        MAC DATABANK3EP                 ; {1}=file base, {2}=signature byte
        ORG {1}
        RORG $F000
        ds 128, $A0
        ds 128, $B0
        ds (SIGOFF-256), $FF
        .byte {2}                       ; signature at in-bank offset $3F0
        ds ($400-SIGOFF-1), $FF         ; pad to the 1K boundary
        ENDM

        SEG BANK2
        DATABANK3EP $0800, $B2
        SEG BANK3
        DATABANK3EP $0C00, $B3
        SEG BANK4
        DATABANK3EP $1000, $B4
        SEG BANK5
        DATABANK3EP $1400, $B5
        SEG BANK6
        DATABANK3EP $1800, $B6
        SEG BANK7
        DATABANK3EP $1C00, $B7
