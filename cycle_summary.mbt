///|
/// Immutable statistics for emitted cycle records. Counts include every
/// record, independently of any Spectrum bin limits. Empty bounds are None.
pub struct CycleTotals {
  records : Int64
  half_records : Int64
  full_records : Int64
  half_units : Int64
  min_range : Double?
  max_range : Double?
  min_mean : Double?
  max_mean : Double?
}

///|
/// Constant-space statistics for cycles emitted by Counter or extract.
/// Append settled cycles once; provisional preview cycles are not final.
pub struct CycleSummary {
  priv mut totals : CycleTotals
}

///|
pub fn CycleSummary::new() -> CycleSummary {
  {
    totals: {
      records: 0L,
      half_records: 0L,
      full_records: 0L,
      half_units: 0L,
      min_range: None,
      max_range: None,
      min_mean: None,
      max_mean: None,
    },
  }
}

///|
fn summary_min(a : Double?, b : Double?) -> Double? {
  match (a, b) {
    (None, _) => b
    (_, None) => a
    (Some(x), Some(y)) => Some(if x < y { x } else { y })
  }
}

///|
fn summary_max(a : Double?, b : Double?) -> Double? {
  match (a, b) {
    (None, _) => b
    (_, None) => a
    (Some(x), Some(y)) => Some(if x > y { x } else { y })
  }
}

///|
fn CycleSummary::accumulate(
  self : CycleSummary,
  added : CycleTotals,
) -> Unit raise RainError {
  let current = self.totals
  // Each nonnegative record count is bounded by half_units. A valid
  // combined weight therefore guarantees that every count sum fits.
  guard current.half_units <= 9223372036854775807L - added.half_units else {
    raise CountLimit
  }
  self.totals = {
    records: current.records + added.records,
    half_records: current.half_records + added.half_records,
    full_records: current.full_records + added.full_records,
    half_units: current.half_units + added.half_units,
    min_range: summary_min(current.min_range, added.min_range),
    max_range: summary_max(current.max_range, added.max_range),
    min_mean: summary_min(current.min_mean, added.min_mean),
    max_mean: summary_max(current.max_mean, added.max_mean),
  }
}

///|
/// Add one emitted cycle. Overflow leaves counts and bounds unchanged.
pub fn CycleSummary::add(
  self : CycleSummary,
  cycle : Cycle,
) -> Unit raise RainError {
  self.accumulate({
    records: 1L,
    half_records: if cycle.half_units == 1 {
      1L
    } else {
      0L
    },
    full_records: if cycle.half_units == 2 {
      1L
    } else {
      0L
    },
    half_units: cycle.half_units.to_int64(),
    min_range: Some(cycle.range),
    max_range: Some(cycle.range),
    min_mean: Some(cycle.mean),
    max_mean: Some(cycle.mean),
  })
}

///|
/// Atomic append: even an overflow late in the chunk leaves this summary
/// unchanged. Staging uses constant memory, without retaining cycle records.
pub fn CycleSummary::add_chunk(
  self : CycleSummary,
  cycles : ArrayView[Cycle],
) -> Unit raise RainError {
  let staged = CycleSummary::new()
  for cycle in cycles {
    staged.add(cycle)
  }
  self.accumulate(staged.totals)
}

///|
/// Combine independently counted histories. The source is unchanged;
/// merging a summary with itself doubles its counts. Overflow is atomic.
pub fn CycleSummary::merge(
  self : CycleSummary,
  other : CycleSummary,
) -> Unit raise RainError {
  self.accumulate(other.totals)
}

///|
/// Return immutable totals that remain unchanged by subsequent additions.
pub fn CycleSummary::snapshot(self : CycleSummary) -> CycleTotals {
  self.totals
}

///|
/// Format exact equivalent cycles as an integer or a decimal ending in .5.
/// Integer arithmetic preserves half cycles even above Double precision.
pub fn CycleTotals::equivalent_cycles(self : CycleTotals) -> String {
  let whole = self.half_units / 2L
  if self.half_units % 2L == 0L {
    "\{whole}"
  } else {
    "\{whole}.5"
  }
}

///|
/// Export a header and one data row, both terminated by LF. Counts are
/// exact integers; absent bounds are empty CSV fields, never zeroes.
pub fn CycleTotals::to_csv(self : CycleTotals) -> String {
  let fields = [
    "\{self.records}",
    "\{self.half_records}",
    "\{self.full_records}",
    "\{self.half_units}",
    self.equivalent_cycles(),
    match self.min_range {
      Some(value) => "\{value}"
      None => ""
    },
    match self.max_range {
      Some(value) => "\{value}"
      None => ""
    },
    match self.min_mean {
      Some(value) => "\{value}"
      None => ""
    },
    match self.max_mean {
      Some(value) => "\{value}"
      None => ""
    },
  ]
  "records,half_records,full_records,half_units,equivalent_cycles,min_range,max_range,min_mean,max_mean\n" +
  fields.join(",") +
  "\n"
}
