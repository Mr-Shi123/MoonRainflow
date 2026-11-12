///|
fn reference_input() -> Array[Double] {
  [-2.0, 1.0, -3.0, 5.0, -1.0, 3.0, -4.0, 4.0, -2.0]
}

///|
test "nine reversals reproduce the seven published MathWorks records" {
  let cycles = @moonrainflow.extract(reference_input())
  let expected : Array[(Int64, Int64, Double, Double, Int)] = [
    (0L, 1L, 3.0, -0.5, 1), (1L, 2L, 4.0, -1.0, 1),
    (4L, 5L, 4.0, 1.0, 2), (2L, 3L, 8.0, 1.0, 1),
    (3L, 6L, 9.0, 0.5, 1), (6L, 7L, 8.0, 0.0, 1),
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
test "constant and short input, plateaus and equal excursions" {
  for a in [[], [2.0], [3.0,3.0,3.0]] {
    assert_eq(@moonrainflow.extract(a).length(), 0)
  }
  let a = @moonrainflow.extract([2.0,2.0,5.0,5.0,5.0,2.0,2.0])
  assert_eq(a.length(), 2)
  assert_true(a[0].start_index == 0L && a[0].end_index == 2L && a[0].half_units == 1)
  assert_true(a[1].start_index == 2L && a[1].end_index == 5L && a[1].half_units == 1)
  let b = @moonrainflow.extract([0.0,1.0,2.0,3.0])
  assert_true(b.length() == 1 && b[0].range == 3.0 && b[0].end_index == 3L)
}
