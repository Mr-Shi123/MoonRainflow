///|
/// A rectangular histogram, with integer half-cycle units in each cell.
pub struct Spectrum {
  priv ranges : Array[Double]
  priv means : Array[Double]
  priv cells : Array[Int64]
  priv mut total : Int64
  priv mut outside : Int64
}

///|
fn validate_edges(axis : String, a : Array[Double]) -> Unit raise RainError {
  guard a.length() >= 2 else {
    raise InvalidEdges(axis + ": need at least two edges")
  }
  for i, x in a {
    guard !x.is_inf() && !x.is_nan() else {
      raise InvalidEdges(axis + ": non-finite edge")
    }
    guard i == 0 || x > a[i - 1] else {
      raise InvalidEdges(axis + ": edges must increase")
    }
  }
}

///|
/// Both arrays are copied. Allows at most one million cells.
pub fn Spectrum::new(
  range_edges : Array[Double],
  mean_edges : Array[Double],
) -> Spectrum raise RainError {
  validate_edges("range", range_edges)
  validate_edges("mean", mean_edges)
  guard range_edges[0] >= 0.0 else {
    raise InvalidEdges("range: negative first edge")
  }
  let nr = range_edges.length() - 1
  let nm = mean_edges.length() - 1
  guard nr <= 1_000_000 / nm else {
    raise InvalidEdges("grid exceeds 1000000 cells")
  }
  {
    ranges: range_edges.copy(),
    means: mean_edges.copy(),
    cells: Array::make(nr * nm, 0L),
    total: 0L,
    outside: 0L,
  }
}

///|
// Half-open bins, except that the very last edge is inclusive.
fn bin(edges : Array[Double], x : Double) -> Int32 {
  let last = edges.length() - 1
  if x < edges[0] || x > edges[last] {
    return -1
  }
  let mut lo = 0
  let mut hi = last
  while hi - lo > 1 {
    let mid = lo + (hi - lo) / 2
    if x < edges[mid] {
      hi = mid
    } else {
      lo = mid
    }
  }
  lo
}

///|
/// Add a cycle emitted by Counter or extract. Outside both axes still
/// contributes its weight only once. Overflow leaves all counts unchanged.
pub fn Spectrum::add(self : Spectrum, c : Cycle) -> Unit raise RainError {
  let units = c.half_units.to_int64()
  guard self.total <= 9223372036854775807L - units else { raise CountLimit }
  let row = bin(self.ranges, c.range)
  let col = bin(self.means, c.mean)
  if row < 0 || col < 0 {
    self.outside += units
  } else {
    let i = row * (self.means.length() - 1) + col
    self.cells[i] = self.cells[i] + units
  }
  self.total += units
}

///|
/// Accumulate another spectrum with identical range and mean edges into this
/// one. This combines counts from independent loading histories. Merging a
/// spectrum with itself doubles its weights. On error all counts stay intact.
pub fn Spectrum::merge(
  self : Spectrum,
  other : Spectrum,
) -> Unit raise RainError {
  guard self.ranges == other.ranges && self.means == other.means else {
    raise InvalidEdges("merge requires identical range and mean edges")
  }
  // Every cell and the outside weight are nonnegative parts of the total.
  // If the combined total fits, each individual sum fits as well.
  guard self.total <= 9223372036854775807L - other.total else {
    raise CountLimit
  }
  for i, units in other.cells {
    self.cells[i] = self.cells[i] + units
  }
  self.outside += other.outside
  self.total += other.total
}

///|
/// Return an independent snapshot, indexed [range bin][mean bin].
pub fn Spectrum::matrix(self : Spectrum) -> Array[Array[Int64]] {
  let width = self.means.length() - 1
  Array::makei(self.ranges.length() - 1, row => {
    Array::makei(width, col => self.cells[row * width + col])
  })
}

///|
/// Sum the matrix across mean bins, in half-cycle units per range bin.
/// Returns an independent snapshot in range-edge order. Cycles outside
/// either axis are excluded, as in matrix(), and remain in outside_units().
pub fn Spectrum::range_units(self : Spectrum) -> Array[Int64] {
  let width = self.means.length() - 1
  Array::makei(self.ranges.length() - 1, row => {
    let mut units = 0L
    for col in 0..<width {
      units += self.cells[row * width + col]
    }
    units
  })
}

///|
/// Sum the matrix across range bins, in half-cycle units per mean bin.
/// Returns an independent snapshot in mean-edge order. Cycles outside
/// either axis are excluded, as in matrix(), and remain in outside_units().
pub fn Spectrum::mean_units(self : Spectrum) -> Array[Int64] {
  let width = self.means.length() - 1
  let units = Array::make(width, 0L)
  for row in 0..<(self.ranges.length() - 1) {
    for col in 0..<width {
      units[col] = units[col] + self.cells[row * width + col]
    }
  }
  units
}

///|
pub fn Spectrum::outside_units(self : Spectrum) -> Int64 {
  self.outside
}

///|
pub fn Spectrum::total_units(self : Spectrum) -> Int64 {
  self.total
}
