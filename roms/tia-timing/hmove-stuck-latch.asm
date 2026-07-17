; hmove-stuck-latch — a mid-sequence HMxx rewrite can jam the HMOVE motion
; latch so the TIA keeps nudging an object every line with no further HMOVE (the
; Cosmic Ark starfield); only the right later value frees it again.
;
; The TIA has five movable objects — two players, two missiles, and the ball —
; and gives each a 4-bit horizontal-motion register (HMP0, HMM0, ...). Writing
; the strobe register HMOVE starts a short sequence during horizontal blank.
; A 4-bit counter loads to 15 and ripples down one step at a time. While an
; object's "more movement" latch is set, each step stuffs one extra motion
; clock into that object, nudging it one colour clock left. The latch clears
; on the step where the ripple counter reaches the object's stored HM value
; (the register's top nibble with its low three bits inverted); after that the
; object sits still. Left to run, every latch clears within the sequence, and
; each object ends up shifted by its programmed amount.
;
; The jam works because the comparison that clears a latch reads the HM
; register a couple of colour clocks before the pulse it governs. Rewrite HMxx
; mid-sequence to a value whose clear step has already gone by, and the
; comparator never matches on any remaining step — the latch is still set when
; the sequence ends. Here HMM0 is armed to $70 (clear step 15 pulses in) and
; HMOVE is strobed at write cycle 3. At write cycle 19, some 11 pulses in,
; HMM0 is rewritten to $00, whose clear step (8 pulses in) has already passed.
; The latch jams: from then on the TIA stuffs one extra clock into the missile
; every line, once per 4 colour clocks across horizontal blank — a steady
; drift of 17 colour clocks left per line, with no further HMOVE. (The
; single-cycle boundary where a rewrite instead races the final comparison is
; hmove-rewrite-race.)
;
; Freeing the jam needs no HMOVE. A later HMxx write releases the latch at
; once if its clear step equals the ripple counter's resting state, %1111.
; Only values with top nibble 8 have that property ($80 here: top nibble 8,
; low three bits inverted, giving %1111); the $70 rewrite does not release it.
; On the release line the object freezes a few colour clocks left of its last
; drift position. (The drift also carries a 4-line fine structure — 2-pixel /
; invisible / normal rows — set by the dot's residue against the stuffed-pulse
; grid; see hmove-stuck-grid.)
;
; The picture: a 1-clock-wide white missile (M0) parks at x=101; the latch
; jams and the dot staircases left 17 px/line, wrapping, for 63 lines; the $70
; rewrite changes nothing for 62 more lines; the $80 rewrite freezes it into a
; constant column at x=27 for the last 63 lines (hardware-measured: real PAL
; console, 2026-07-16).
;
; Verdict: the captured frame vs hmove-stuck-latch_<region>.png.

        processor 6502
        include "vcs.h"
        include "macro.h"
        include "region.h"    ; FIELD_50HZ / VISIBLE_LINES for the pad guard

        org $F000

Reset:
        CLEAN_START

        lda #$00
        sta COLUBK              ; background: black field
        lda #$0E
        sta COLUP0              ; missile 0: white
        lda #$02
        sta ENAM0               ; enable M0 (1 colour clock wide)

MainLoop:
        jsr vertical_sync
        jsr vblank_lines

        ; line 1: park M0 at x=101 and arm the motion register HMM0 = $70
        sta WSYNC               ; align to a fresh scanline
        lda #$70
        sta HMM0                ; arm: $70 would clear 15 pulses in
        SLEEP 47
        sta RESM0               ; strobe at write cycle 55 -> M0 lands at x=101

        ; line 2: jam the latch — HMOVE at write cycle 3, HMM0=$00 at cycle 19
        sta WSYNC
        sta HMOVE               ; write cycle 3: start the ripple sequence
        lda #$00
        SLEEP 11
        sta HMM0                ; write cycle 19: $00's clear step (8) long past
                                ; -> comparator never matches: latch stuck

        ; phase A: 63 lines of runaway drift, 17 px/line left, wrapping
        ldy #63
.pa:
        sta WSYNC
        dey
        bne .pa

        ; a $70 rewrite (no HMOVE) must not release the latch: $70's clear step
        ; is not the resting state, so the stuffed pulses keep coming
        sta WSYNC
        lda #$70
        sta HMM0
        ldy #62                 ; phase B: the drift continues regardless
.pb:
        sta WSYNC
        dey
        bne .pb

        ; a $80 rewrite (no HMOVE) releases it at once: $80's clear step is the
        ; ripple's resting state (%1111), so the latch clears immediately
        sta WSYNC
        lda #$80
        sta HMM0
        ldy #63                 ; phase C: frozen column to the frame's end
.pc:
        sta WSYNC
        dey
        bne .pc

        IFCONST FIELD_50HZ             ; 50 Hz fields have more visible lines: blank the extra
        lda #$00                ; ones so the picture keeps its NTSC shape
        sta ENAM0               ; disable M0 during the padding lines
        ldx #(VISIBLE_LINES-192)
.pad:
        sta WSYNC
        dex
        bne .pad
        lda #$02
        sta ENAM0               ; re-enable M0 for the next field
        ENDIF

        jsr overscan_lines
        jmp MainLoop

        include "frame.asm"

        org $FFFC
        .word Reset
        .word Reset
