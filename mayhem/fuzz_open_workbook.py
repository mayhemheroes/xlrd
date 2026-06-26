#!/usr/bin/env python3
"""Atheris fuzz harness for xlrd's workbook reader (xlrd.open_workbook).

Feeds the fuzzer-provided bytes to ``xlrd.open_workbook`` via the in-memory ``file_contents``
argument (no temp file, so nothing is written to the read-only image) and swallows the parse
errors a malformed spreadsheet is *expected* to raise, so only an unexpected failure (an uncaught
exception / crash inside xlrd) is reported.

Atheris is a libFuzzer engine: run with libFuzzer flags it iterates; run with a single file
argument it replays that input once (standalone reproducer). The ELF ``launcher`` (see launcher.c)
exec's ``python3`` on this file, forwarding every argument unchanged.
"""
import logging
import os
import struct
import sys
import warnings
import zipfile

import atheris

# Instrument the whole xlrd package so Atheris gets edge coverage of the reader.
with atheris.instrument_imports():
    import xlrd
    import xlrd.biffh
    import xlrd.compdoc

# xlrd is chatty on garbage input — silence diagnostics so the fuzzer runs fast.
logging.disable(logging.CRITICAL)
warnings.filterwarnings("ignore")
_NULL = open(os.devnull, "w")


@atheris.instrument_func
def TestOneInput(data):
    # Empty bytes are FALSY, so xlrd ignores file_contents and falls back to filename=None
    # (-> TypeError). That is a quirk of the truthiness check, not an xlrd defect, so skip it.
    if not data:
        return -1
    try:
        xlrd.open_workbook(file_contents=bytes(data), logfile=_NULL)
    except (
        xlrd.XLRDError,
        xlrd.biffh.XLRDError,
        xlrd.compdoc.CompDocError,
        zipfile.BadZipFile,
        struct.error,
        LookupError,
        AttributeError,
        OSError,
        ValueError,
        IndexError,
        KeyError,
        AssertionError,
        UnicodeDecodeError,
        NotImplementedError,
        MemoryError,
        OverflowError,
    ):
        # Expected ways a malformed spreadsheet is rejected — not defects.
        # ``struct.error`` is xlrd unpacking a truncated BIFF record;
        # ``LookupError`` is an unknown/unsupported codepage encoding;
        # ``AttributeError`` is xlrd reading records out of order on garbage input.
        return -1


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
