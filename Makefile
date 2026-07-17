# Atari 2600 test suite — build each test ROM for every TV standard with dasm.
DASM     ?= dasm
INC       = include
SYSINC    = /usr/include/dasm/atari2600
DFLAGS    = -f3 -I$(INC) -I$(SYSINC)

SRCS      = $(wildcard roms/cpu/*.asm) $(wildcard roms/riot/*.asm) \
            $(wildcard roms/tia-render/*.asm) $(wildcard roms/tia-timing/*.asm) \
            $(wildcard roms/collision/*.asm) $(wildcard roms/cartridge/*.asm) \
            $(wildcard roms/harness/*.asm)
# Every source builds one binary per TV standard: an NTSC 262-line field, and
# PAL and SECAM 312-line fields (region.h selects the line counts, and the
# result-screen palette, via -DPAL / -DSECAM). Self-test verdicts are
# region-independent, but each binary renders a real frame of its own shape.
ROMS      = $(SRCS:.asm=_ntsc.a26) $(SRCS:.asm=_pal.a26) $(SRCS:.asm=_secam.a26)
SHARED    = $(INC)/result.h $(INC)/result_screen.asm $(INC)/frame.asm $(INC)/region.h

# dasm leaves partial output behind on assembly errors, which make would
# otherwise treat as a fresh build on the next run
.DELETE_ON_ERROR:

.PHONY: all clean
all: $(ROMS)

# Supercharger (AR) tests are not raw ROMs: dasm emits one 2K RAM-bank image,
# which build_ar.py replicates into the 3 RAM banks and wraps in the checksummed
# 8448-byte "fastload" load image emulator loaders verify (see scripts/build_ar.py).
# These more-specific patterns win over the generic ones below for ar-*.asm.
AR_BUILD  = ./scripts/build_ar.py $@.bank --start 0xF100 --config 0x04 --replicate 3 -o$@ && rm -f $@.bank
roms/cartridge/ar-%_ntsc.a26: roms/cartridge/ar-%.asm $(SHARED) scripts/build_ar.py
	$(DASM) $< $(DFLAGS) -o$@.bank
	$(AR_BUILD)

roms/cartridge/ar-%_pal.a26: roms/cartridge/ar-%.asm $(SHARED) scripts/build_ar.py
	$(DASM) $< $(DFLAGS) -DPAL -o$@.bank
	$(AR_BUILD)

roms/cartridge/ar-%_secam.a26: roms/cartridge/ar-%.asm $(SHARED) scripts/build_ar.py
	$(DASM) $< $(DFLAGS) -DSECAM -o$@.bank
	$(AR_BUILD)

# Pattern rules span the subsystem dirs (% matches e.g. tia-render/playfield).
roms/%_ntsc.a26: roms/%.asm $(SHARED)
	$(DASM) $< $(DFLAGS) -o$@

roms/%_pal.a26: roms/%.asm $(SHARED)
	$(DASM) $< $(DFLAGS) -DPAL -o$@

roms/%_secam.a26: roms/%.asm $(SHARED)
	$(DASM) $< $(DFLAGS) -DSECAM -o$@

clean:
	rm -f roms/*/*.a26 roms/*/*.lst
