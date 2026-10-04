"""Check the ABAP fixture's wire format and quoted rule against real Git/LFS."""
import re
import subprocess
import tempfile
from pathlib import Path


def git(directory, *args):
    return subprocess.run(
        ["git", "-C", str(directory), *args], check=True,
        capture_output=True, encoding="utf-8",
    ).stdout


fixture = Path("src/zcl_bpc_git_lfs.clas.testclasses.abap").read_text(encoding="utf-8")
rule = re.search(r"text CS '([^']+filter=lfs diff=lfs merge=lfs -text)'", fixture).group(1)
expected_hash = re.search(r"exp = '([a-f0-9]{64})'", fixture).group(1)

with tempfile.TemporaryDirectory(prefix="bpcgit-lfs-check-") as temporary:
    directory = Path(temporary)
    git(directory, "init", "--quiet")
    (directory / "workbook.bin").write_bytes(b"abc")
    actual_pointer = git(directory, "lfs", "pointer", "--file=workbook.bin")
    assert actual_pointer == (
        "version https://git-lfs.github.com/spec/v1\n"
        f"oid sha256:{expected_hash}\nsize 3\n"
    ), actual_pointer
    (directory / ".gitattributes").write_text("*.txt text\n" + rule + "\n", encoding="utf-8")
    workbook = "M/EEXCEL/INPUT SCHEDULES/[Plan].XLSX"
    actual = git(directory, "check-attr", "-z", "filter", "diff", "merge", "text", "--", workbook).split("\0")
    assert actual[:-1] == [
        workbook, "filter", "lfs", workbook, "diff", "lfs",
        workbook, "merge", "lfs", workbook, "text", "unset",
    ], actual
    other = "M/EEXCEL/INPUT SCHEDULES/P.XLSX"
    assert git(directory, "check-attr", "-z", "filter", "--", other).split("\0")[2] == "unspecified"
    assert git(directory, "check-attr", "-z", "text", "--", "note.txt").split("\0")[2] == "set"

print("Git LFS pointer and exact filename attributes compatibility checks passed")
