"""The addon as it was at a git ref, for comparing against the working copy (samelook.py, bench.py --ref)."""
import io
import os
import subprocess
import tarfile
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def export(ref, folder="SmoothAnimatedBars"):
    """Extracts folder at ref into a new temporary directory and returns the folder's path there."""
    data = subprocess.run(["git", "archive", "--format=tar", ref, folder], cwd=ROOT, check=True,
                          capture_output=True).stdout
    out = tempfile.mkdtemp(prefix="sab-" + ref.replace("/", "_").replace("~", "_") + "-")
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        tar.extractall(out)
    return os.path.join(out, folder)
