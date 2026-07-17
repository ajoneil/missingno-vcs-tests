; region.h — per-TV-standard frame geometry and result-screen colours.
;
; Assemble with -DPAL or -DSECAM for a 50 Hz, 312-line field; with neither for
; an NTSC 60 Hz, 262-line field. The per-line timing is identical on every
; standard (228 colour clocks = 76 CPU cycles); only the line COUNTS differ, so
; one test source builds for any standard:
;
;            VSYNC  VBLANK  visible  overscan  total   field
;   NTSC       3      37      192       30       262    60 Hz
;   PAL        3      45      228       36       312    50 Hz
;   SECAM      3      45      228       36       312    50 Hz
;
; SECAM shares PAL's line geometry — it is a 50 Hz, 312-line-per-field system
; like PAL — but differs in COLOUR. A SECAM console ignores the TIA colour
; byte's hue nibble entirely and drives one of only 8 fixed colours from the
; luminance bits (3..1) alone, so two codes that differ only in hue paint
; the SAME colour on SECAM. Anything that leans on hue to tell two things apart
; must instead separate them by LUMINANCE to stay legible — see the colours
; below.
;
; Self-tests' verdicts are region-independent, but each region's binary renders
; a true field of that region's height (screenshot tests need it; self-tests get
; it for free from the shared frame/result screens).
;
; Included by frame.asm and result_screen.asm — and directly by some tests. Many
; tests pull in both of those, so the guard makes a second include a no-op.

        IFNCONST REGION_H
REGION_H = 1

; --- field geometry ---------------------------------------------------------
; PAL and SECAM share the 50 Hz, 312-line field; NTSC is 60 Hz, 262 lines.
        IFCONST PAL
FIELD_50HZ = 1
        ENDIF
        IFCONST SECAM
FIELD_50HZ = 1
        ENDIF

        IFCONST FIELD_50HZ
VISIBLE_LINES  = 228
VBLANK_LINES   = 45
OVERSCAN_LINES = 36
        ELSE
VISIBLE_LINES  = 192
VBLANK_LINES   = 37
OVERSCAN_LINES = 30
        ENDIF

; --- result-screen colours --------------------------------------------------
; The PASS/FAIL screen (result_screen.asm) colour-codes five things: a green
; pass field, a red fail field, and three digit rows on the fail screen — CODE,
; OBSERVED, EXPECTED. The hue nibble maps to a DIFFERENT colour wheel on each
; standard, so "green" is a different code per region: NTSC green is hue $C but
; PAL green is hue $5 (on a PAL console $C paints violet), and PAL hue $1 is
; grey, not yellow. SECAM has no hue at all — a SECAM console decodes only the
; luminance bits into 8 fixed colours — so there the three digit colours sit on
; DISTINCT luminance steps (7/6/5 -> SECAM white/yellow/cyan) and pass/fail on
; well-separated luma (4/2 -> green/red), keeping every digit brighter than the
; fail background. (Hardware-confirmed on a real PAL console, 2026-07-16: the
; NTSC green code $C8 paints violet there.)
        IFCONST SECAM
COL_PASS     = $08      ; luma 4 -> SECAM green
COL_FAIL     = $04      ; luma 2 -> SECAM red
COL_CODE     = $0E      ; luma 7 -> SECAM white
COL_OBSERVED = $0C      ; luma 6 -> SECAM yellow
COL_EXPECTED = $0A      ; luma 5 -> SECAM cyan
        ELSE
        IFCONST PAL
COL_PASS     = $58      ; PAL green (hue 5)
COL_FAIL     = $64      ; PAL red (hue 6)
COL_CODE     = $0E      ; white
COL_OBSERVED = $2E      ; PAL yellow (hue 2)
COL_EXPECTED = $7E      ; PAL cyan (hue 7)
        ELSE
COL_PASS     = $C8      ; NTSC green (hue C)
COL_FAIL     = $44      ; NTSC red (hue 4)
COL_CODE     = $0E      ; white
COL_OBSERVED = $1E      ; NTSC yellow (hue 1)
COL_EXPECTED = $BE      ; NTSC cyan (hue B)
        ENDIF
        ENDIF

; COL_FIELD — the capture-safe bright surface: green at luma 4 on every
; standard (the same values as COL_PASS, shared rationale). Screenshot tests
; that need a large lit surface use this instead of white or grey: a bright
; ACHROMATIC field is pure DC luma and RF capture tuners drop lock on it
; (hardware-measured 2026-07-16: solid $0E white and solid $08 grey = static;
; the solid green pass screens at the same luminance = solid lock), while a
; saturated field keeps colour-subcarrier energy in the signal. Luma 4 also
; leaves room above (digits/white details) and below (red/blue objects) on
; SECAM's luma-only decode.
        IFCONST SECAM
COL_FIELD    = $08      ; luma 4 -> SECAM green
        ELSE
        IFCONST PAL
COL_FIELD    = $58      ; PAL green (hue 5), luma 4
        ELSE
COL_FIELD    = $C8      ; NTSC green (hue C), luma 4
        ENDIF
        ENDIF

        ENDIF   ; REGION_H
