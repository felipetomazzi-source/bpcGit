"""Normalise files under src/ to the byte format abapGit writes.

- Metadata XML (contains "<abapGit "): UTF-8 BOM, CRLF, one trailing CRLF.
- ABAP source (*.abap): no BOM, CRLF, exactly one trailing CRLF.
- WAPA content (*.wapa.* except *.wapa.xml): no BOM, every line padded with
  spaces to 255 characters, lines joined with CRLF, plus one final padded
  empty line (no trailing CRLF).

Usage: python tools/abapgit_fmt.py [--check]
Idempotent; --check only reports files that would change.
"""
import sys
from pathlib import Path

BOM = b"\xef\xbb\xbf"
WAPA_WIDTH = 255


def lines_of(data):
    if data.startswith(BOM):
        data = data[len(BOM):]
    return data.decode("utf-8").replace("\r\n", "\n").split("\n")


def fmt_metadata(data):
    lines = lines_of(data)
    while lines and lines[-1] == "":
        lines.pop()
    return BOM + ("\r\n".join(lines) + "\r\n").encode("utf-8")


def fmt_abap(data):
    lines = [l.rstrip() for l in lines_of(data)]
    while lines and lines[-1] == "":
        lines.pop()
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


def fmt_wapa(data, name):
    lines = [l.rstrip(" ") for l in lines_of(data)]
    # SAP keeps a final padded empty line only if the uploaded source ended
    # with a newline; preserve whichever form the file already has.
    ends_with_newline = len(lines) > 1 and lines[-1] == ""
    while lines and lines[-1] == "":
        lines.pop()
    for i, l in enumerate(lines, 1):
        if len(l) > WAPA_WIDTH:
            raise SystemExit(f"{name}:{i} is {len(l)} chars, max {WAPA_WIDTH}")
    if ends_with_newline:
        lines.append("")
    return "\r\n".join(l.ljust(WAPA_WIDTH) for l in lines).encode("utf-8")


def main():
    check = "--check" in sys.argv
    root = Path(__file__).resolve().parent.parent / "src"
    changed = []
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        data = p.read_bytes()
        if p.suffix == ".abap":
            new = fmt_abap(data)
        elif ".wapa." in p.name and not p.name.endswith(".wapa.xml"):
            new = fmt_wapa(data, p.name)
        elif p.suffix == ".xml" and b"<abapGit " in data:
            new = fmt_metadata(data)
        else:
            continue
        if new != data:
            changed.append(p.name)
            if not check:
                p.write_bytes(new)
    for n in changed:
        print(("would change: " if check else "formatted: ") + n)
    if check and changed:
        sys.exit(1)


if __name__ == "__main__":
    main()
