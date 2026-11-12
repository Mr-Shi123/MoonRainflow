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
