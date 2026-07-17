; frame.asm — shared frame scaffolding for screenshot (frame-capture) tests.
;
; A screenshot test sets up its TIA state, then builds a standard field for the
; assembled region: 3 lines VSYNC, then VBLANK / visible / overscan line counts
; from region.h (NTSC 37/192/30, PAL & SECAM 45/228/36). The vertical structure
; is identical across tests; only the visible section differs. These subroutines
; provide the constant parts so each test's source is just "set up the picture +
; render VISIBLE_LINES visible lines".
;
; Usage (see roms/tia-render/*.asm):
;   MainLoop:
;           jsr vertical_sync       ; 3 VSYNC lines
;           jsr vblank_lines        ; VBLANK_LINES lines, beam on afterwards
;           ; --- VISIBLE_LINES visible lines (test-specific) ---
;           ldx #VISIBLE_LINES
;   .vis:   sta WSYNC               ; (static picture: registers already latched)
;           dex
;           bne .vis
;           jsr overscan_lines      ; OVERSCAN_LINES lines, beam off
;           jmp MainLoop
;
; The jsr/rts overhead lands in HBLANK and is absorbed by the next WSYNC, so
; line counts and the visible image are unaffected.

        include "region.h"      ; VISIBLE_LINES / VBLANK_LINES / OVERSCAN_LINES

; 3-line vertical sync.
vertical_sync:
        lda #$02
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #$00
        sta VSYNC
        rts

; VBLANK lines (NTSC 37 / PAL 45); leaves the beam on for the visible section.
vblank_lines:
        lda #$02
        sta VBLANK
        ldx #VBLANK_LINES
.vbl:
        sta WSYNC
        dex
        bne .vbl
        lda #$00
        sta VBLANK
        rts

; overscan lines (NTSC 30 / PAL 36) with the beam off.
overscan_lines:
        lda #$02
        sta VBLANK
        ldx #OVERSCAN_LINES
.osl:
        sta WSYNC
        dex
        bne .osl
        lda #$00
        sta VBLANK
        rts
