; hmove-rewrite-race — a motion-register rewrite racing the END of the HMOVE
; ripple sequence, the single-cycle boundary that jams Cosmic Ark's starfield.
;
; The TIA (the console's video chip) nudges its movable objects with HMOVE.
; Writing that strobe register (the write itself triggers the action; the value
; is ignored) loads a 4-bit "ripple" counter to 15 and arms a "more movement"
; latch for every object; the counter then counts down one step at a time, and
; on a fixed clock phase of each step (call it the STUFF phase) every
; still-armed object is handed one extra motion clock — nudging it left one
; colour clock. A per-object comparator clears the latch on the step where
; the ripple reaches the object's stored amount — the motion register's high
; nibble with its low three bits inverted (HMM0 for missile 0): $70 collects
; all fifteen stuffs, $80 none. HMOVE also
; stretches horizontal blank eight clocks, withholding eight ordinary motion
; clocks, so the net move spans +7 (seven left) down to -8 (eight right).
;
; The subtlety this test isolates: the comparator does not read one fixed value.
; While the ripple is still descending, each pulse's comparison reads the motion
; value as it stood at the PREVIOUS step, not the live register; only the final
; latch-releasing comparison, after the counter has run out, reads the value
; latched at the stuff phase. So a rewrite of HMM0 that lands in the one-step gap
; between those two sample points can dodge every remaining ripple value and
; never satisfy the clearing comparison — the latch sticks, and the TIA keeps
; stuffing every line, one clock per 4 colour clocks across horizontal blank:
; the -17 px/line drift of the Cosmic Ark starfield.
;
; Cosmic Ark arms HMM0=$70, strobes HMOVE three CPU cycles into a fresh scanline
; (write cycle 3), then rewrites HMM0=$60 twenty-one cycles later — just as the
; ripple reaches its last compare. One cycle EARLIER and the $60 match still
; lands: fourteen stuffs, a clean 6-px move. One cycle LATER and the $70
; sequence has already taken its last sample, so the rewrite is a no-op: a clean
; 7-px move. AT the boundary the match never fires and the latch jams.
; (hmove-stuck-latch jams a rewrite safely mid-window, clear of this edge — a
; model can pass that and still collapse the starfield here.)
;
; The test sweeps the rewrite across sixteen bands, stepping the $60 write over
; write cycles 20..35. The frame reads as a needle: a 1px white missile on
; black, re-parked at x=101 then HMOVE'd once in each 12-line band.
;
;   bands 0-3    cycles 20-23   settle x=95   the $60 lands in time: 14 stuffs
;   band 4       cycle 24       jam           Cosmic Ark's boundary: no match
;   bands 5-15   cycles 25-35   settle x=94   rewrite too late: $70's 15 stuffs
;
; The jam band staircases left 17px per line, wrapping, with a 4-row beat of
; normal, doubled and swallowed rows, until the $80 release freezes the dot's
; last two rows at x=113 (hardware-measured: real PAL console, 2026-07-16). Were
; both comparisons instead to read one shared stuff-phase capture, the racing
; latch would clear a step too readily and the jam would slip late, to band 5.
;
; Verdict: the captured frame vs hmove-rewrite-race_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

BAND    = $80                   ; current band 0..15 (rewrite cycle 20+BAND)
ODD     = $82                   ; BAND & 1 (adds the odd rewrite cycle)
VEC     = $84                   ; RAM pointer for the computed jmp (2 bytes)

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; black field
        lda #$0E
        sta COLUP0              ; white missile (missile takes COLUP0)
        lda #$02
        sta ENAM0               ; missile enabled throughout

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ldx #0
.bandloop:
        stx BAND

        ; line 1: precompute the rewrite sled entry (VEC = SledEnd - BAND/2,
        ; ODD = BAND&1 -> sta HMM0's write lands at write cycle 20 + BAND)
        sta WSYNC
        lda BAND
        and #$01
        sta ODD
        lda BAND
        lsr
        sta VEC                 ; scratch: BAND/2
        lda #<SledEnd
        sec
        sbc VEC
        sta VEC
        lda #>SledEnd
        sbc #0
        sta VEC+1
        lda #$70
        sta HMM0                ; arm the 15-pulse value

        ; line 2: park M0 at x=101 (write cycle 55)
        sta WSYNC
        SLEEP 52
        sta RESM0

        ; line 3: the race — HMOVE at write cycle 3, then the $60 rewrite
        ; at the band's cycle
        sta WSYNC
        sta HMOVE               ; write cycle 3: start the ripple sequence
        lda #$60                ; the value that races the last compare
        ldx ODD
        bne .go                 ; +1 cycle on odd bands (branch taken)
.go:
        jmp (VEC)               ; enter the sled so sta HMM0 lands at 20 + band
Sled:
        REPEAT 7
        nop
        REPEND
SledEnd:
        nop
        sta HMM0                ; write cycle 20 + BAND

        ; lines 4..11: observe — settled column vs -17 px/line staircase
        ldy #8
.obs:
        sta WSYNC
        dey
        bne .obs

        ; line 12: release any stuck latch so the bands stay independent
        sta WSYNC
        lda #$80
        sta HMM0

        ldx BAND
        inx
        cpx #16
        bne .bandloop

        IFCONST FIELD_50HZ
        lda #$00
        sta ENAM0
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        lda #$02
        sta ENAM0
        ENDIF

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
