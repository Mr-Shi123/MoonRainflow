"""Optional differential check against the unmodified PyPI rainflow 3.2.0."""
import csv
import io
import random
import subprocess
from importlib.metadata import version
from pathlib import Path

import rainflow


def main():
    if version("rainflow") != "3.2.0":
        raise SystemExit("Use rainflow==3.2.0 for this comparison.")
    root = Path(__file__).resolve().parents[1]
    rng = random.Random(1049)
    histories = [[-2, 1, -3, 5, -1, 3, -4, 4, -2], [0, 1, 0, 1, 0],
                 list(range(128)), list(reversed(range(128)))]
    # Ties between adjacent samples have deliberately different index policies
    # across libraries. Avoid those ties in the differential domain; MoonBit
    # separately tests the first sample of a plateau, flat and two-point input.
    for case in range(96):
        history = [rng.randint(-32, 32)]
        for _ in range(3 + case * 2):
            x = rng.randint(-32, 32)
            history.append(x if x != history[-1] else x + 1)
        histories.append(history)
    records = 0
    for i, history in enumerate(histories):
        expected = [(a, b, span, mid, int(2 * count))
                    for span, mid, count, a, b in rainflow.extract_cycles(history)]
        completed = subprocess.run(
            ["node", "cmd/rainflow.mjs", "-"], cwd=root, check=True,
            input="".join(f"{x}\n" for x in history), text=True, capture_output=True,
        )
        got = [(int(r["start_index"]), int(r["end_index"]), float(r["range"]),
                float(r["mean"]), int(r["half_units"]))
               for r in csv.DictReader(io.StringIO(completed.stdout))]
        if got != expected:
            raise SystemExit(f"History {i} disagrees:\ninput={history}\ngot={got}\nexpected={expected}")
        records += len(got)
    print(f"Matched {len(histories)} histories and {records} cycle records against rainflow 3.2.0.")


if __name__ == "__main__":
    main()
