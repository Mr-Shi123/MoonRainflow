///|
test "cycle summary distinguishes records from weighted equivalent cycles" {
  let summary = @moonrainflow.CycleSummary::new()
  for cycle in @moonrainflow.extract(reference_input()) {
    summary.add(cycle)
  }
  let totals = summary.snapshot()
  assert_eq(totals.records, 7L)
  assert_eq(totals.half_records, 6L)
  assert_eq(totals.full_records, 1L)
  assert_eq(totals.half_units, 8L)
  assert_true(totals.min_range == Some(3.0))
  assert_true(totals.max_range == Some(9.0))
  assert_true(totals.min_mean == Some(-1.0))
  assert_true(totals.max_mean == Some(1.0))
  assert_eq(totals.equivalent_cycles(), "4")
  assert_eq(
    totals.to_csv(),
    "records,half_records,full_records,half_units,equivalent_cycles,min_range,max_range,min_mean,max_mean\n7,6,1,8,4,3,9,-1,1\n",
  )
}

///|
test "empty cycle summaries preserve absent extrema in CSV" {
  let summary = @moonrainflow.CycleSummary::new()
  summary.add_chunk([])
  summary.merge(@moonrainflow.CycleSummary::new())
  let totals = summary.snapshot()
  assert_eq(totals.records, 0L)
  assert_eq(totals.half_records, 0L)
  assert_eq(totals.full_records, 0L)
  assert_eq(totals.half_units, 0L)
  assert_true(totals.min_range is None && totals.max_range is None)
  assert_true(totals.min_mean is None && totals.max_mean is None)
  assert_eq(totals.equivalent_cycles(), "0")
  assert_eq(
    totals.to_csv(),
    "records,half_records,full_records,half_units,equivalent_cycles,min_range,max_range,min_mean,max_mean\n0,0,0,0,0,,,,\n",
  )
}

///|
test "summary chunks match individual adds and snapshots remain independent" {
  let cycles = @moonrainflow.extract(reference_input())
  let individual = @moonrainflow.CycleSummary::new()
  for cycle in cycles {
    individual.add(cycle)
  }
  for split in 0..<(cycles.length() + 1) {
    let chunked = @moonrainflow.CycleSummary::new()
    chunked.add_chunk(cycles[:split])
    let snapshot = chunked.snapshot()
    let saved = snapshot.to_csv()
    chunked.add_chunk(cycles[split:])
    assert_eq(chunked.snapshot().to_csv(), individual.snapshot().to_csv())
    assert_eq(snapshot.to_csv(), saved)
  }
}

///|
test "summary merge combines independent runs without changing its source" {
  let combined = @moonrainflow.CycleSummary::new()
  combined.add_chunk(@moonrainflow.extract([-20.0, -18.0]))
  let run = @moonrainflow.CycleSummary::new()
  run.add_chunk(@moonrainflow.extract(reference_input()))
  let saved = run.snapshot().to_csv()
  combined.merge(run)
  assert_eq(run.snapshot().to_csv(), saved)
  let totals = combined.snapshot()
  assert_eq(totals.records, 8L)
  assert_eq(totals.half_records, 7L)
  assert_eq(totals.full_records, 1L)
  assert_eq(totals.half_units, 9L)
  assert_true(totals.min_range == Some(2.0))
  assert_true(totals.max_range == Some(9.0))
  assert_true(totals.min_mean == Some(-19.0))
  assert_true(totals.max_mean == Some(1.0))
  assert_eq(totals.equivalent_cycles(), "4.5")
  let copy = @moonrainflow.CycleSummary::new()
  copy.merge(combined)
  combined.merge(@moonrainflow.CycleSummary::new())
  assert_eq(copy.snapshot().to_csv(), combined.snapshot().to_csv())
}

///|
test "summary self merge doubles counts and preserves extrema" {
  let summary = @moonrainflow.CycleSummary::new()
  summary.add_chunk(@moonrainflow.extract(reference_input()))
  summary.merge(summary)
  let totals = summary.snapshot()
  assert_eq(totals.records, 14L)
  assert_eq(totals.half_records, 12L)
  assert_eq(totals.full_records, 2L)
  assert_eq(totals.half_units, 16L)
  assert_true(totals.min_range == Some(3.0))
  assert_true(totals.max_range == Some(9.0))
  assert_true(totals.min_mean == Some(-1.0))
  assert_true(totals.max_mean == Some(1.0))
}

///|
fn summary_near_limit() -> @moonrainflow.CycleSummary raise @moonrainflow.RainError {
  let summary = @moonrainflow.CycleSummary::new()
  let half = @moonrainflow.extract([0.0, 2.0])[0]
  // 62 doublings with a unit appended make 2^62 - 1; one more
  // doubling leaves exactly one half-cycle unit of Int64 capacity.
  for _ in 0..<62 {
    summary.merge(summary)
    summary.add(half)
  }
  summary.merge(summary)
  summary
}

///|
test "overflow late in a summary chunk preserves all counts and extrema" {
  let summary = summary_near_limit()
  let before = summary.snapshot().to_csv()
  let wider = @moonrainflow.extract([-30.0, 10.0])[0]
  let full = @moonrainflow.extract(reference_input())[2]
  assert_true(
    (Ok(summary.add_chunk([wider, full])) catch { e => Err(e) })
    is Err(@moonrainflow.CountLimit),
  )
  assert_eq(summary.snapshot().to_csv(), before)
  summary.add(wider)
  let at_limit = summary.snapshot().to_csv()
  assert_true(
    (Ok(summary.add(full)) catch { e => Err(e) })
    is Err(@moonrainflow.CountLimit),
  )
  assert_eq(summary.snapshot().to_csv(), at_limit)
}

///|
test "overflowing summary merge preserves both summaries" {
  let summary = summary_near_limit()
  let other = @moonrainflow.CycleSummary::new()
  other.add_chunk(@moonrainflow.extract(reference_input()))
  let saved = summary.snapshot().to_csv()
  let source = other.snapshot().to_csv()
  assert_true(
    (Ok(summary.merge(other)) catch { e => Err(e) })
    is Err(@moonrainflow.CountLimit),
  )
  assert_eq(summary.snapshot().to_csv(), saved)
  assert_eq(other.snapshot().to_csv(), source)
  assert_true(
    (Ok(summary.merge(summary)) catch { e => Err(e) })
    is Err(@moonrainflow.CountLimit),
  )
  assert_eq(summary.snapshot().to_csv(), saved)
}

///|
test "equivalent cycle text retains exact halves above Double precision" {
  let summary = summary_near_limit()
  assert_eq(summary.snapshot().half_units, 9223372036854775806L)
  assert_eq(summary.snapshot().equivalent_cycles(), "4611686018427387903")
  summary.add(@moonrainflow.extract([0.0, 2.0])[0])
  let totals = summary.snapshot()
  assert_eq(totals.half_units, 9223372036854775807L)
  assert_eq(totals.equivalent_cycles(), "4611686018427387903.5")
  assert_eq(
    totals.to_csv(),
    "records,half_records,full_records,half_units,equivalent_cycles,min_range,max_range,min_mean,max_mean\n9223372036854775807,9223372036854775807,0,9223372036854775807,4611686018427387903.5,2,2,1,1\n",
  )
}
