# MoonRainflow

[中文说明](README.zh-CN.md) · [API](pkg.generated.mbti)

MoonRainflow counts rainflow cycles in a single load history. It reports the range, mean, weight and original endpoints of each excursion, and can accumulate a range-by-mean spectrum as samples arrive. The library is MoonBit with no third-party runtime dependencies; the file/pipe CLI calls the same compiled library.

## Replay a published example

```sh
moon run cmd/demo --target wasm-gc
```

Nine reversals arrive in three blocks. Samples 4 and 5 enclose a full cycle from −1 to 3 (range 4, mean 1). The seven records comprise one full and six half cycles, or four equivalent cycles. With range edges `[0,4,8]` and mean edges `[-1,0,1]`, the half-unit matrix is `[[1,0],[1,5]]`, with one more half unit outside the grid.

## Process a file

From this directory, with MoonBit (tested with moonc 0.10.19) and Node 22.12+:

```sh
moon build --target js --release cmd/bridge
node cmd/rainflow.mjs examples/mathworks-nine.txt
node cmd/rainflow.mjs measurements.txt > cycles.csv
```

Input is one decimal number per UTF-8 line, including scientific notation. Blank lines are ignored. With no path or with `-`, the CLI reads stdin. CSV columns are `start_index,end_index,range,mean,half_units`. The last field is 1 for a half cycle and 2 for a full cycle; range is the full peak-to-valley distance, not amplitude. A failing stream returns nonzero and reports the physical line for a bad sample; any rows already emitted remain in the output.

### Export cycles above a minimum range

```sh
node cmd/rainflow.mjs --min-range 4 examples/mathworks-nine.txt > large-cycles.csv
```

`--min-range R` keeps cycles whose range is **greater than or equal to** R. The threshold is a finite, nonnegative decimal in the same units as the input; scientific notation and `--min-range=R` are also accepted. Place the option before or after the input path, or omit the path to filter stdin. The default is 0, which preserves the original output. In the example, six records remain: the range-3 half cycle is excluded, while both range-4 records are retained.

All samples still enter the rainflow counter and undergo validation. Filtering selects the exported records after counting, preserving their original sample indices, means, weights and settlement order. Matching cycles are streamed as they become available. If none match, the output contains only the CSV header.

### Check processing totals

Add `--summary` to print a summary to stderr after successful completion. It works with files or stdin and can appear before or after the path:

```sh
node cmd/rainflow.mjs --summary --min-range 4 examples/mathworks-nine.txt > cycles.csv
```

The CSV goes to `cycles.csv`, while the terminal shows:

```text
Samples: 9
Counted cycles: 7 records; 4 equivalent cycles
Exported cycles: 6 records; 3.5 equivalent cycles
```

`Samples` counts accepted measurements, excluding blank lines. `Counted cycles` includes all settled and final residual cycles before filtering; `Exported cycles` includes only records kept by `--min-range`. Record counts and equivalent cycles are distinct: a half-cycle record contributes 0.5 equivalent cycles. Totals use exact integer half-cycle units, including when the count exceeds JavaScript's safe integer range. CSV remains streamed to stdout. Failed runs report the error without a completed summary. Omit `--summary` for the original CSV-only behavior.

## Library

See the [executable MoonBit example](cmd/demo/main.mbt) and [package import](cmd/demo/moon.pkg). For a batch, call `@rain.extract(samples)`. For streaming, use one `Counter::new()` per continuous signal, collect the arrays returned by every `push(value)` or `push_chunk(values)`, then append `finish()` once at the end. The chunk layout does not affect the results; finishing each chunk separately does. Invalid chunks are rejected atomically. A second finish returns no cycles; appending to a finished counter raises an error.

Indices are zero-based Int64 sample indices. Flat runs use the first occurrence, including the trailing plateau. A constant history has no cycles. The three-point rule closes equal as well as larger incoming ranges. Inner pairs are full cycles; boundary pairs and the final unclosed adjacent excursions count as halves. Records are emitted in settlement order. Inputs must be finite and within ±1e300. The library does not infer timestamps, periodically wrap the signal, apply a noise filter, or predict fatigue life.

Feed returned cycles to `Spectrum::new(range_edges, mean_edges).add(c)`. Both axes must be finite and strictly increasing, range edges nonnegative. Each bin includes its lower edge; only the last also includes its upper edge. A cycle outside either axis contributes just once to `outside_units()`. `matrix()` returns an independent snapshot in half-cycle units, indexed by range then mean. Its sum plus outside units equals `total_units()`. The grid limit is one million cells.

Counting is amortized O(n) in samples. The stream does not retain all measurements or settled cycles; the unresolved reversal stack can still grow to O(n). Binning takes O(log R + log M) time per record.

### Preview a live record without ending it

`counter.preview_finish()` returns the cycles that `finish()` would emit at this moment, while leaving the counter open for further samples. Cycles already returned by `push` or `push_chunk` are excluded.

```moonbit
let counter = @rain.Counter::new()
let confirmed = counter.push_chunk([0.0, 5.0, 1.0]) // No settled cycles yet.
let provisional = counter.preview_finish() // Two half cycles: ranges 5 and 4.
confirmed.append(counter.push(6.0))
confirmed.append(counter.finish())
// confirmed: a full cycle of range 4, then a half cycle of range 6.
```

For an "ends now" view, combine the previously confirmed cycles with the current preview. Replace the preview on each refresh; accumulate only the actual `push`, `push_chunk` and `finish` results into a permanent spectrum. Later samples can change the provisional cycles and their weights. The returned array is an independent snapshot; repeated previews do not consume samples or change subsequent counting. A preview after `finish()` is empty. Each call copies the pending reversal state, with time and extra memory proportional to the number of pending reversals.

### Get one-dimensional distributions

Use `range_units()` or `mean_units()` to plot totals along one axis without copying the full matrix and summing it yourself:

```moonbit
let grid = @rain.Spectrum::new([0.0, 4.0, 8.0], [-1.0, 0.0, 1.0])
for cycle in @rain.extract([-2.0, 1.0, -3.0, 5.0, -1.0, 3.0, -4.0, 4.0, -2.0]) {
  grid.add(cycle)
}
let by_range = grid.range_units() // [1L, 6L]
let by_mean = grid.mean_units()   // [2L, 5L]
```

Each result is an independent array in the corresponding bin order, in integer half-cycle units. Both summarize only the cells inside the two-dimensional grid: cycles outside **either** axis remain in `outside_units()`. The sum of either array plus `outside_units()` equals `total_units()`. Each call scans the grid in O(R × M) time and allocates only its result array, O(R) or O(M).

### Combine independent test runs

Count each run separately so the jump between runs cannot create a spurious cycle. If you already have one spectrum per run, `combined.merge(run)` adds its bins and outside weight to the combined spectrum. Both grids must use identical edges on both axes. Incompatible edges or an Int64 count overflow leave the accumulated result intact.

```moonbit
let ranges = [0.0, 5.0]
let means = [-5.0, 5.0, 105.0]
let combined = @rain.Spectrum::new(ranges, means)
for samples in [[0.0, 4.0], [100.0, 104.0]] {
  let run = @rain.Spectrum::new(ranges, means)
  for cycle in @rain.extract(samples) { run.add(cycle) }
  combined.merge(run)
}
// combined.matrix() == [[1L, 1L]]: one half cycle in each mean bin.
```

## Verification and provenance

```sh
moon fmt --check
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon build --target js --release cmd/bridge --deny-warn
node --test scripts/cli.test.mjs
```

Checks include the [MathWorks nine-reversal table](https://www.mathworks.com/help/signal/ref/rainflow.html), all 256 partitions of that input, all 3,280 ternary histories up to length seven (total variation, plateau anchors and endpoints), bin conservation, one-dimensional distributions and their snapshot isolation, and streaming CLI behavior. For an optional external check, install `rainflow==3.2.0` in an isolated Python environment, build the JS bridge, and run `python scripts/check_reference.py`. It compares 100 deterministic histories and 3,540 cycle records with [Python rainflow](https://github.com/iamlikeme/rainflow), including order and indices. Adjacent ties are tested separately because plateau index conventions differ.

Independent implementation of a published counting method, licensed under [Apache-2.0](LICENSE). Python rainflow (MIT) is an optional test oracle. No standards certification is claimed.
