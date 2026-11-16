///|
test "matrix uses explicit edges and counts half units without rounding" {
  let r = [0.0, 4.0, 8.0]
  let m = [-1.0, 0.0, 1.0]
  let s = @moonrainflow.Spectrum::new(r, m)
  r[1] = 100.0
  m[0] = 100.0
  for c in @moonrainflow.extract(reference_input()) {
    s.add(c)
  }
  let cells = s.matrix()
  assert_true(cells == [[1L, 0L], [1L, 5L]])
  assert_eq(s.outside_units(), 1L)
  assert_eq(s.total_units(), 8L)
  cells[1][1] = 999L
  assert_eq(s.matrix()[1][1], 5L)
}

///|
test "full cycle outside both axes counted once, weight two" {
  let s = @moonrainflow.Spectrum::new([0.0, 1.0], [20.0, 30.0])
  let cycles = @moonrainflow.extract(reference_input())
  s.add(cycles[2])
  assert_eq(s.outside_units(), 2L)
  assert_eq(s.total_units(), 2L)
  assert_true(s.matrix() == [[0L]])
}

///|
test "merge aggregates separately counted histories and preserves the source" {
  let ranges = [0.0, 4.0, 8.0]
  let means = [-1.0, 0.0, 1.0]
  let combined = @moonrainflow.Spectrum::new(ranges, means)
  for cycle in @moonrainflow.extract([0.0, 2.0]) {
    combined.add(cycle)
  }
  let run = @moonrainflow.Spectrum::new(ranges.copy(), means.copy())
  for cycle in @moonrainflow.extract(reference_input()) {
    run.add(cycle)
  }
  combined.merge(run)
  assert_true(combined.matrix() == [[1L, 1L], [1L, 5L]])
  assert_eq(combined.outside_units(), 1L)
  assert_eq(combined.total_units(), 9L)
  assert_true(run.matrix() == [[1L, 0L], [1L, 5L]])
  assert_eq(run.outside_units(), 1L)
  assert_eq(run.total_units(), 8L)
}

///|
test "merge rejects different edge values even on equally sized grids" {
  let target = @moonrainflow.Spectrum::new([0.0, 4.0], [-1.0, 1.0])
  let cycles = @moonrainflow.extract([0.0, 2.0])
  target.add(cycles[0])
  for
    other in [
      @moonrainflow.Spectrum::new([0.0, 5.0], [-1.0, 1.0]),
      @moonrainflow.Spectrum::new([0.0, 4.0], [0.0, 1.0]),
    ] {
    other.add(cycles[0])
    let result = Ok(target.merge(other)) catch { e => Err(e) }
    assert_true(result is Err(@moonrainflow.InvalidEdges(_)))
    assert_true(target.matrix() == [[1L]])
    assert_eq(target.total_units(), 1L)
  }
}

///|
test "self merge doubles weights and an overflowing merge is atomic" {
  let grid = @moonrainflow.Spectrum::new([0.0, 2.0], [-1.0, 1.0])
  for cycle in @moonrainflow.extract([0.0, 1.0, -4.0]) {
    grid.add(cycle)
  }
  for _ in 0..<61 {
    grid.merge(grid)
  }
  let result = Ok(grid.merge(grid)) catch { e => Err(e) }
  assert_true(result is Err(@moonrainflow.CountLimit))
  assert_true(grid.matrix() == [[1L << 61]])
  assert_eq(grid.outside_units(), 1L << 61)
  assert_eq(grid.total_units(), 1L << 62)
}

///|
test "invalid bin schemas rejected before allocation" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  for edges in [[], [1.0], [2.0, 2.0], [3.0, 2.0], [0.0, nan], [0.0, inf]] {
    assert_true(
      (Ok(@moonrainflow.Spectrum::new(edges, [0.0, 1.0])) catch { e => Err(e) })
      is Err(_),
    )
    assert_true(
      (Ok(@moonrainflow.Spectrum::new([0.0, 1.0], edges)) catch { e => Err(e) })
      is Err(_),
    )
  }
  assert_true(
    (Ok(@moonrainflow.Spectrum::new([-1.0, 1.0], [0.0, 1.0])) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let many = Array::makei(1002, i => i.to_double())
  assert_true(
    (Ok(@moonrainflow.Spectrum::new(many, many)) catch { e => Err(e) })
    is Err(_),
  )
}
