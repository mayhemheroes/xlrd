#!/usr/bin/env python3
"""Oracle driver for mayhem/test.sh — open an .xls workbook and print a fixed set of
``KEY=value`` lines (a known-answer dump of tests/samples/profiles.xls).

This exercises the SAME read path the fuzzer drives (xlrd.open_workbook -> sheet/cell decode)
and prints decoded values, so a neutered/no-op program produces no/garbled output and the
test.sh assertions fail. Invoked via the /mayhem/run-cli ELF launcher (a non-system executable,
so the verify-repo sabotage neuter applies to it).
"""
import sys

import xlrd


def main():
    book = xlrd.open_workbook(sys.argv[1])
    names = ",".join(book.sheet_names())
    sheet = book.sheet_by_index(0)
    print(f"BIFF={book.biff_version}")
    print(f"NSHEETS={book.nsheets}")
    print(f"SHEETNAMES={names}")
    print(f"SHEET0NAME={sheet.name}")
    print(f"NROWS={sheet.nrows}")
    print(f"NCOLS={sheet.ncols}")
    print(f"A1={sheet.cell_value(0, 0)}")
    print(f"B1={sheet.cell_value(0, 1)}")
    print(f"A2={sheet.cell_value(1, 0)}")


if __name__ == "__main__":
    main()
