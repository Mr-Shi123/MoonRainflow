///|
fn reference_input() -> Array[Double] {
  [-2.0, 1.0, -3.0, 5.0, -1.0, 3.0, -4.0, 4.0, -2.0]
}

///|
test "nine reversals reproduce the seven published MathWorks records" {
  let cycles = @moonrainflow.extract(reference_input())
  let expected : Array[(Int64, Int64, Double, Double, Int32)] = [
    (0L, 1L, 3.0, -0.5, 1),
    (1L, 2L, 4.0, -1.0, 1),
    (4L, 5L, 4.0, 1.0, 2),
    (2L, 3L, 8.0, 1.0, 1),
    (3L, 6L, 9.0, 0.5, 1),
    (6L, 7L, 8.0, 0.0, 1),
    (7L, 8L, 6.0, 1.0, 1),
  ]
  assert_eq(cycles.length(), expected.length())
  for i, c in cycles {
    let (start, end, span, mid, units) = expected[i]
    assert_true(c.start_index == start && c.end_index == end)
    assert_true(c.range == span && c.mean == mid && c.half_units == units)
  }
}

///|
test "all 256 chunk layouts reproduce batch cycles in order" {
  let a = reference_input()
  let want = @moonrainflow.extract(a)
  for mask in 0..<256 {
    let stream = @moonrainflow.Counter::new()
    let got = []
    let chunk = []
    for i, x in a {
      chunk.push(x)
      if i == a.length() - 1 || (mask & (1 << i)) != 0 {
        got.append(stream.push_chunk(chunk))
        chunk.clear()
      }
    }
    got.append(stream.finish())
    assert_true(got == want)
    assert_eq(stream.finish().length(), 0)
  }
}

///|
test "finish previews match every prefix without changing subsequent counting" {
  for
    samples in [
      reference_input(),
      [],
      [2.0],
      [3.0, 3.0, 3.0],
      [0.0, 1.0, 2.0, 3.0],
      [2.0, 2.0, 5.0, 5.0, 5.0, 2.0, 2.0],
      [0.0, 1.0, 0.0, 1.0, 0.0],
      [0.0, 1.0e20, 1.0, 2.0e20],
      [0.0, -1.0e20, -1.0, -2.0e20],
    ] {
    for split in 0..<(samples.length() + 1) {
      let stream = @moonrainflow.Counter::new()
      let settled = stream.push_chunk(samples[:split])
      let preview : Array[@moonrainflow.Cycle] = stream.preview_finish()
      let at_end = settled.copy()
      at_end.append(preview)
      assert_true(at_end == @moonrainflow.extract(samples[:split]))
      assert_true(stream.preview_finish() == preview)
      preview.clear()
      settled.append(stream.push_chunk(samples[split:]))
      settled.append(stream.finish())
      assert_true(settled == @moonrainflow.extract(samples))
    }
  }
}

///|
test "previewed halves can become a full cycle while the snapshot stays unchanged" {
  let stream = @moonrainflow.Counter::new()
  assert_eq(stream.push_chunk([0.0, 5.0, 1.0]).length(), 0)
  let preview = stream.preview_finish()
  assert_eq(preview.length(), 2)
  assert_true(preview[0].start_index == 0L && preview[0].end_index == 1L)
  assert_true(preview[0].range == 5.0 && preview[0].half_units == 1)
  assert_true(preview[1].start_index == 1L && preview[1].end_index == 2L)
  assert_true(preview[1].range == 4.0 && preview[1].half_units == 1)
  let snapshot = preview.copy()
  let completed = stream.push(6.0)
  completed.append(stream.finish())
  assert_eq(completed.length(), 2)
  assert_true(completed[0].start_index == 1L && completed[0].end_index == 2L)
  assert_true(completed[0].range == 4.0 && completed[0].half_units == 2)
  assert_true(completed[1].start_index == 0L && completed[1].end_index == 3L)
  assert_true(completed[1].range == 6.0 && completed[1].half_units == 1)
  assert_true(preview == snapshot)
}

///|
test "preview of a finished counter stays empty and does not reopen it" {
  let stream = @moonrainflow.Counter::new()
  assert_eq(stream.push_chunk([0.0, 1.0]).length(), 0)
  assert_eq(stream.finish().length(), 1)
  assert_eq(stream.preview_finish().length(), 0)
  assert_eq(stream.preview_finish().length(), 0)
  assert_true(
    (Ok(stream.push(2.0)) catch { e => Err(e) })
    is Err(@moonrainflow.ClosedCounter),
  )
}

///|
test "constant and short input, plateaus and equal excursions" {
  for a in [[], [2.0], [3.0, 3.0, 3.0]] {
    assert_eq(@moonrainflow.extract(a).length(), 0)
  }
  let a = @moonrainflow.extract([2.0, 2.0, 5.0, 5.0, 5.0, 2.0, 2.0])
  assert_eq(a.length(), 2)
  assert_true(
    a[0].start_index == 0L && a[0].end_index == 2L && a[0].half_units == 1,
  )
  assert_true(
    a[1].start_index == 2L && a[1].end_index == 5L && a[1].half_units == 1,
  )
  let b = @moonrainflow.extract([0.0, 1.0, 2.0, 3.0])
  assert_true(b.length() == 1 && b[0].range == 3.0 && b[0].end_index == 3L)
}

///|
test "chunk error reports global index and leaves previous input intact" {
  let stream = @moonrainflow.Counter::new()
  let out = stream.push(-2.0)
  let bad = Ok(stream.push_chunk([1.0, -3.0, 5.0, 0.0 / 0.0])) catch {
    e => Err(e)
  }
  assert_true(bad is Err(@moonrainflow.InvalidSample(4L)))
  for invalid in [1.0 / 0.0, -1.0 / 0.0, 1.0e301, -1.0e301] {
    assert_true(
      (Ok(stream.push(invalid)) catch { e => Err(e) })
      is Err(@moonrainflow.InvalidSample(1L)),
    )
  }
  out.append(stream.push_chunk(reference_input()[1:]))
  out.append(stream.finish())
  assert_true(out == @moonrainflow.extract(reference_input()))
  assert_true(
    (Ok(stream.push(0.0)) catch { e => Err(e) })
    is Err(@moonrainflow.ClosedCounter),
  )
  assert_true(
    (Ok(stream.push_chunk([])) catch { e => Err(e) })
    is Err(@moonrainflow.ClosedCounter),
  )
}

///|
test "valid extremes yield finite range and mean" {
  let a = @moonrainflow.extract([-1.0e300, 1.0e300])
  assert_eq(a.length(), 1)
  assert_eq(a[0].range, 2.0e300)
  assert_eq(a[0].mean, 0.0)
}

///|
test "rounding at high dynamic range must not prematurely close a cycle" {
  for sign in [-1.0, 1.0] {
    let history = [0.0, sign * 1.0e20, sign, sign * 2.0e20]
    let rows = @moonrainflow.extract(history)
    assert_eq(rows.length(), 2)
    assert_true(
      rows[0].start_index == 1L &&
      rows[0].end_index == 2L &&
      rows[0].half_units == 2,
    )
    assert_true(
      rows[1].start_index == 0L &&
      rows[1].end_index == 3L &&
      rows[1].half_units == 1,
    )
  }
}

///|
test "every short ternary history conserves variation and traces source endpoints" {
  let mut combinations = 1
  for n in 0..<8 {
    for code in 0..<combinations {
      let xs : Array[Double] = []
      let mut v = code
      for _ in 0..<n {
        xs.push((v % 3 - 1).to_double())
        v = v / 3
      }
      let mut raw = 0.0
      for i in 1..<xs.length() {
        raw += (xs[i] - xs[i - 1]).abs()
      }
      let mut counted_variation = 0.0
      for cycle in @moonrainflow.extract(xs) {
        let a = cycle.start_index.to_int()
        let b = cycle.end_index.to_int()
        assert_true(a >= 0 && a < b && b < n)
        assert_true(a == 0 || xs[a - 1] != xs[a])
        assert_true(b == 0 || xs[b - 1] != xs[b])
        assert_true(cycle.half_units == 1 || cycle.half_units == 2)
        assert_true(cycle.range > 0.0 && cycle.range == (xs[a] - xs[b]).abs())
        assert_eq(cycle.mean, (xs[a] + xs[b]) / 2.0)
        counted_variation += cycle.range * cycle.half_units.to_double()
      }
      assert_eq(counted_variation, raw)
    }
    combinations *= 3
  }
}
