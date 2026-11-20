///|
fn report_spectrum() -> @moonrainflow.Spectrum raise @moonrainflow.RainError {
  let spectrum = @moonrainflow.Spectrum::new([0.0, 4.0, 8.0], [
    -2.0, 0.0, 1.0, 2.0,
  ])
  for samples in [reference_input(), [-0.5, 0.5], [0.0, 2.0], [0.0, 2.0]] {
    for cycle in @moonrainflow.extract(samples) {
      spectrum.add(cycle)
    }
  }
  // Includes a full cycle in the last cell and one outside half cycle.
  // The six cells are [1, 1, 2] and [1, 1, 4], totaling ten half units.
  spectrum
}

///|
test "coarsen combines rectangular cells exactly and keeps outside weight" {
  let source = report_spectrum()
  let coarse = source.coarsen([0.0, 8.0], [-2.0, 1.0, 2.0])
  assert_true(coarse.matrix() == [[4L, 6L]])
  assert_eq(coarse.total_units(), 11L)
  assert_eq(coarse.outside_units(), 1L)
  assert_true(source.matrix() == [[1L, 1L, 2L], [1L, 1L, 4L]])
  assert_eq(source.total_units(), 11L)
}

///|
test "each coarsening axis can be changed independently" {
  let source = report_spectrum()
  let ranges_only = source.coarsen([0.0, 8.0], [-2.0, 0.0, 1.0, 2.0])
  let means_only = source.coarsen([0.0, 4.0, 8.0], [-2.0, 1.0, 2.0])
  assert_true(ranges_only.matrix() == [[2L, 2L, 6L]])
  assert_true(means_only.matrix() == [[2L, 2L], [2L, 4L]])
  assert_eq(ranges_only.total_units(), 11L)
  assert_eq(means_only.outside_units(), 1L)
}

///|
test "coarsen all cells into one without including outside counts" {
  let coarse = report_spectrum().coarsen([0.0, 8.0], [-2.0, 2.0])
  assert_true(coarse.matrix() == [[10L]])
  assert_eq(coarse.total_units(), 11L)
  assert_eq(coarse.outside_units(), 1L)
}

///|
test "identity coarsening and supplied edge arrays are independent copies" {
  let source = report_spectrum()
  let ranges = [0.0, 4.0, 8.0]
  let means = [-2.0, 0.0, 1.0, 2.0]
  let copy = source.coarsen(ranges, means)
  ranges[1] = 5.0
  means[1] = 0.5
  copy.merge(copy)
  assert_true(copy.range_edges() == [0.0, 4.0, 8.0])
  assert_true(copy.mean_edges() == [-2.0, 0.0, 1.0, 2.0])
  assert_true(copy.matrix() == [[2L, 2L, 4L], [2L, 2L, 8L]])
  assert_true(source.matrix() == [[1L, 1L, 2L], [1L, 1L, 4L]])
  assert_eq(source.outside_units(), 1L)
  source.merge(source)
  source.merge(source)
  assert_eq(source.total_units(), 44L)
  assert_eq(copy.total_units(), 22L)
  assert_eq(copy.outside_units(), 2L)
}

///|
test "coarsening preserves internal and inclusive final edge membership" {
  let source = @moonrainflow.Spectrum::new([0.0, 4.0, 8.0], [
    -2.0, 0.0, 1.0, 2.0,
  ])
  for samples in [[-2.5, -1.5], [-2.0, 2.0], [-1.0, 3.0], [-2.0, 6.0]] {
    source.add(@moonrainflow.extract(samples)[0])
  }
  assert_true(source.matrix() == [[1L, 0L, 0L], [0L, 1L, 2L]])
  let coarse = source.coarsen([0.0, 4.0, 8.0], [-2.0, 1.0, 2.0])
  assert_true(coarse.matrix() == [[1L, 0L], [1L, 2L]])
  coarse.add(@moonrainflow.extract([-2.0, 6.0])[0])
  assert_true(coarse.matrix() == [[1L, 0L], [1L, 3L]])
  assert_eq(coarse.outside_units(), 0L)
}

///|
test "coarsening rejects refinement nonmatching edges and changed endpoints" {
  let source = report_spectrum()
  for
    ranges in [
      [0.0, 2.0, 4.0, 8.0],
      [0.0, 3.0, 8.0],
      [1.0, 8.0],
      [0.0, 7.0],
      [0.0, 9.0],
      [-1.0, 8.0],
    ] {
    let result = Ok(source.coarsen(ranges, [-2.0, 2.0])) catch { e => Err(e) }
    assert_true(result is Err(@moonrainflow.InvalidEdges(_)))
  }
  for
    means in [
      [-2.0, 0.0, 0.5, 1.0, 2.0],
      [-2.0, 0.5, 2.0],
      [-1.0, 2.0],
      [-2.0, 1.0],
      [-3.0, 2.0],
      [-2.0, 3.0],
    ] {
    let result = Ok(source.coarsen([0.0, 8.0], means)) catch { e => Err(e) }
    assert_true(result is Err(@moonrainflow.InvalidEdges(_)))
  }
  assert_true(source.matrix() == [[1L, 1L, 2L], [1L, 1L, 4L]])
  assert_eq(source.total_units(), 11L)
}

///|
test "coarsening validates short nonfinite and unordered axes" {
  let source = report_spectrum()
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  for edges in [[], [0.0], [0.0, 0.0], [2.0, 1.0], [0.0, nan], [0.0, inf]] {
    assert_true(
      (Ok(source.coarsen(edges, [-2.0, 2.0])) catch { e => Err(e) })
      is Err(@moonrainflow.InvalidEdges(_)),
    )
    assert_true(
      (Ok(source.coarsen([0.0, 8.0], edges)) catch { e => Err(e) })
      is Err(@moonrainflow.InvalidEdges(_)),
    )
  }
  assert_eq(source.total_units(), 11L)
}

///|
test "empty and entirely outside spectra coarsen without inventing counts" {
  let source = @moonrainflow.Spectrum::new([0.0, 1.0, 2.0], [-1.0, 0.0, 1.0])
  let empty = source.coarsen([0.0, 2.0], [-1.0, 1.0])
  assert_true(empty.matrix() == [[0L]])
  assert_eq(empty.total_units(), 0L)
  assert_eq(empty.outside_units(), 0L)
  source.add(@moonrainflow.extract([10.0, 20.0])[0])
  let outside = source.coarsen([0.0, 2.0], [-1.0, 1.0])
  assert_true(outside.matrix() == [[0L]])
  assert_eq(outside.total_units(), 1L)
  assert_eq(outside.outside_units(), 1L)
}

///|
test "coarsened independent histories can merge with exact half unit weights" {
  let source = report_spectrum()
  let left = source.coarsen([0.0, 8.0], [-2.0, 1.0, 2.0])
  let right = source.coarsen([0.0, 8.0], [-2.0, 1.0, 2.0])
  left.merge(right)
  assert_true(left.matrix() == [[8L, 12L]])
  assert_eq(left.outside_units(), 2L)
  assert_eq(left.total_units(), 22L)
  assert_true(right.matrix() == [[4L, 6L]])
}

///|
test "report rows include zero cells in range then mean order" {
  let source = @moonrainflow.Spectrum::new([0.0, 4.0, 8.0], [
    -2.0, 0.0, 1.0, 2.0,
  ])
  for cycle in @moonrainflow.extract(reference_input()) {
    source.add(cycle)
  }
  let rows = source.rows()
  let expected : Array[(Int32, Int32, Double, Double, Double, Double, Int64)] = [
    (0, 0, 0.0, 4.0, -2.0, 0.0, 1L),
    (0, 1, 0.0, 4.0, 0.0, 1.0, 0L),
    (0, 2, 0.0, 4.0, 1.0, 2.0, 0L),
    (1, 0, 4.0, 8.0, -2.0, 0.0, 1L),
    (1, 1, 4.0, 8.0, 0.0, 1.0, 1L),
    (1, 2, 4.0, 8.0, 1.0, 2.0, 4L),
  ]
  assert_eq(rows.length(), 6)
  for i, row in rows {
    let (ri, mi, rl, ru, ml, mu, units) = expected[i]
    assert_eq(row.range_index, ri)
    assert_eq(row.mean_index, mi)
    assert_eq(row.range_lower, rl)
    assert_eq(row.range_upper, ru)
    assert_eq(row.mean_lower, ml)
    assert_eq(row.mean_upper, mu)
    assert_eq(row.half_units, units)
  }
}

///|
test "report rows and edge accessors do not expose mutable spectrum state" {
  let source = report_spectrum()
  let rows = source.rows()
  let ranges = source.range_edges()
  let means = source.mean_edges()
  source.merge(source)
  assert_eq(rows[5].half_units, 4L)
  rows[0] = rows[5]
  ranges[0] = 99.0
  means[0] = 99.0
  assert_eq(source.rows()[0].half_units, 2L)
  assert_eq(source.rows()[0].range_index, 0)
  assert_true(source.range_edges() == [0.0, 4.0, 8.0])
  assert_true(source.mean_edges() == [-2.0, 0.0, 1.0, 2.0])
}

///|
test "CSV exports complete numeric rows and keeps outside units separate" {
  let source = @moonrainflow.Spectrum::new([0.5, 4.5], [-1.5, 0.5, 2.5])
  source.add(@moonrainflow.extract([0.0, 2.0])[0])
  source.add(@moonrainflow.extract(reference_input())[2])
  source.add(@moonrainflow.extract([10.0, 20.0])[0])
  let expected = "range_index,mean_index,range_lower,range_upper,mean_lower,mean_upper,half_units\n" +
    "0,0,0.5,4.5,-1.5,0.5,0\n" +
    "0,1,0.5,4.5,0.5,2.5,3\n"
  assert_eq(source.to_csv(), expected)
  assert_eq(source.outside_units(), 1L)
  assert_eq(source.total_units(), 4L)
}
