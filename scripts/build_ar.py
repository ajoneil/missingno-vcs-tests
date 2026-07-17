#!/usr/bin/env python3
"""build_ar — assemble a Supercharger (AR) single-load "fastload" image.

The Starpath Supercharger is not a ROM board: it is 6K of RAM (three 2K banks)
plus a 2K BIOS, and a real cart is loaded off cassette tape. Emulators accept a
pre-digitised "fastload" .bin instead of audio — a byte-exact snapshot of what
the BIOS would have streamed into RAM, wrapped in the header the BIOS writes
once a tape finishes. This script turns a raw dasm binary (code assembled to run
from Supercharger RAM) into that image so the AR test ROMs can be built the same
way every other test is: dasm -> a loadable `.a26`.

The container format is the community-documented Starpath fastload layout,
the one emulator loaders parse and checksum-verify.

Image layout (one 8448-byte load block; multi-load is n blocks, not needed here):

  offset 0x0000 .. 0x17FF   6144 bytes  RAM image: 24 pages -> the 3 RAM banks
  offset 0x1800 .. 0x1FFF   2048 bytes  BIOS placeholder (never loaded; zero)
  offset 0x2000 .. 0x20FF    256 bytes  header:
      [0]      start address low        (BIOS JMPs here once loaded)
      [1]      start address high
      [2]      control (config) byte    -> the control register at launch
      [3]      page count (<= 24)       how many 256-byte pages to load to RAM
      [4]      header checksum          bytes 0..7 must sum to 0x55
      [5]      multiload index          0 for a single-load tape
      [6],[7]  progress-bar speed       cosmetic; 0
      [16..]   page table, one byte per RAM page:
                   bits 0-1 = 2K RAM bank (0-2), bits 2-4 = 256-byte page in bank
      [64..]   per-page checksums: page-data-sum + table-entry + checksum == 0x55

The control byte:
  D7-D5 write-pulse delay (unused, 0)   D4-D2 bank config (0-7, see the table in
  roms/cartridge/ar-config.asm)         D1 RAM write-enable (1=on)
                                        D0 ROM power (0=ROM on, 1=ROM off)

Loaders read only `page count` pages, but some verify all 24 page checksums up
front and silently rewrite any that fail — so this always emits a full, correct
24-entry page table and checksum table, even when fewer pages carry content,
keeping the on-disk image canonical rather than loader-patched.

  scripts/build_ar.py --start 0xF100 --config 0x0D game.bin -o game.a26
"""
import argparse, sys

BANK_SIZE = 0x800          # 2K per RAM bank
NUM_BANKS = 3              # 6K RAM = 3 banks
RAM_BYTES = BANK_SIZE * NUM_BANKS          # 0x1800 = 6144
PAGE_SIZE = 0x100
NUM_PAGES = RAM_BYTES // PAGE_SIZE          # 24
DATA_SIZE = 0x2000         # 8192: RAM image + 2K BIOS placeholder
HEADER_SIZE = 0x100        # 256
LOAD_SIZE = DATA_SIZE + HEADER_SIZE         # 8448
CK_BASE = 0x55             # every header/page checksum sums to this


def contiguous_page_table():
    """Default layout: pack the binary linearly across the banks — data page j
    lives at bank j//8, page (j%8) within that bank (the conventional linear
    map emulator loaders assume)."""
    return [(((j % 8) << 2) | (j // 8)) & 0xFF for j in range(NUM_PAGES)]


def replicate_banks(binary, n):
    """Tile one bank's content (<=2K) into n identical 2K RAM banks. AR test code
    that must survive a bank switch of the *lower* window (which is always RAM,
    never ROM) lives byte-identically in every bank — the same trick the F8 STUB
    uses, generalised to the Supercharger's three banks."""
    if len(binary) > BANK_SIZE:
        raise ValueError(f"--replicate: bank content is {len(binary)} bytes; max {BANK_SIZE} (2K)")
    bank = binary + bytes(BANK_SIZE - len(binary))
    return bank * n


def build_image(binary, start, config, multiload=0, page_table=None):
    if len(binary) > RAM_BYTES:
        raise ValueError(f"binary is {len(binary)} bytes; max {RAM_BYTES} (6K RAM)")
    page_table = page_table or contiguous_page_table()
    if len(page_table) != NUM_PAGES:
        raise ValueError(f"page table must have {NUM_PAGES} entries")

    # data area: RAM image (zero-padded to 6K) then the 2K BIOS placeholder
    data = bytearray(DATA_SIZE)
    data[0:len(binary)] = binary

    # how many pages actually carry content (the rest are zero, but still get a
    # valid table entry + checksum so strict up-front 24-page verifies pass)
    num_pages = (len(binary) + PAGE_SIZE - 1) // PAGE_SIZE
    if num_pages == 0:
        num_pages = 1

    header = bytearray(HEADER_SIZE)
    header[0] = start & 0xFF
    header[1] = (start >> 8) & 0xFF
    header[2] = config & 0xFF
    header[3] = num_pages
    header[5] = multiload & 0xFF
    header[6] = 0
    header[7] = 0

    # header checksum: bytes 0..7 must sum to 0x55 (CartAR.cxx:422,
    # fastload_block.go:80-84). Byte 4 is the free variable.
    partial = sum(header[i] for i in (0, 1, 2, 3, 5, 6, 7)) & 0xFF
    header[4] = (CK_BASE - partial) & 0xFF

    # page table + per-page checksums for all 24 pages
    for j in range(NUM_PAGES):
        entry = page_table[j]
        header[0x10 + j] = entry
        page = data[j * PAGE_SIZE:(j + 1) * PAGE_SIZE]
        # page-data-sum + table-entry + checksum-byte == 0x55
        # (CartAR.cxx:440-442, fastload_block.go:86-92)
        header[0x40 + j] = (CK_BASE - (sum(page) & 0xFF) - entry) & 0xFF

    image = bytes(data) + bytes(header)
    assert len(image) == LOAD_SIZE
    return image


def main():
    ap = argparse.ArgumentParser(description="assemble a Supercharger fastload image")
    ap.add_argument("binary", help="raw dasm binary (<=6K), assembled to run from AR RAM")
    ap.add_argument("--start", required=True, type=lambda s: int(s, 0),
                    help="start address the BIOS JMPs to once loaded, e.g. 0xF100")
    ap.add_argument("--config", required=True, type=lambda s: int(s, 0),
                    help="control (config) byte applied at launch, e.g. 0x0D")
    ap.add_argument("--multiload", type=lambda s: int(s, 0), default=0,
                    help="multiload index (0 for a single-load tape)")
    ap.add_argument("--replicate", type=int, default=0, metavar="N",
                    help="tile a single <=2K bank image into N identical RAM banks")
    ap.add_argument("-o", "--out", required=True, help="output .a26 (8448 bytes)")
    args = ap.parse_args()

    with open(args.binary, "rb") as f:
        binary = f.read()

    if args.replicate:
        try:
            binary = replicate_banks(binary, args.replicate)
        except ValueError as e:
            print(f"build_ar: {e}", file=sys.stderr)
            return 1

    try:
        image = build_image(binary, args.start, args.config, args.multiload)
    except ValueError as e:
        print(f"build_ar: {e}", file=sys.stderr)
        return 1

    with open(args.out, "wb") as f:
        f.write(image)
    return 0


if __name__ == "__main__":
    sys.exit(main())
