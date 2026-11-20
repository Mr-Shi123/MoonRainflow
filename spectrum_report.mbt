///|
/// A snapshot of one histogram cell, including zero-weight cells.
/// Bounds are half-open except for each axis's inclusive final upper edge.
pub struct SpectrumCell {
  range_index : Int32
  mean_index : Int32
  range_lower : Double
  range_upper : Double
  mean_lower : Double
  mean_upper : Double
  half_units : Int64
}

///|
/// Return an independent copy of the range boundaries.
pub fn Spectrum::range_edges(self : Spectrum) -> Array[Double] {
  self.ranges.copy()
}

///|
/// Return an independent copy of the mean boundaries.
pub fn Spectrum::mean_edges(self : Spectrum) -> Array[Double] {
  self.means.copy()
}

///|
/// Return every cell in range-major, then mean-major order. Outside weight
/// has no cell coordinates and remains available through outside_units().
pub fn Spectrum::rows(self : Spectrum) -> Array[SpectrumCell] {
  let width = self.means.length() - 1
  Array::makei(self.cells.length(), i => {
    let row = i / width
    let col = i % width
    {
      range_index: row,
      mean_index: col,
      range_lower: self.ranges[row],
      range_upper: self.ranges[row + 1],
      mean_lower: self.means[col],
      mean_upper: self.means[col + 1],
      half_units: self.cells[i],
    }
  })
}

///|
/// Export the same numeric records as rows(), with a header and a trailing
/// newline. Counts remain integer half-cycle units; outside weight is separate.
pub fn Spectrum::to_csv(self : Spectrum) -> String {
  let lines = [
    "range_index,mean_index,range_lower,range_upper,mean_lower,mean_upper,half_units",
  ]
  for row in self.rows() {
    lines.push(
      "\{row.range_index},\{row.mean_index},\{row.range_lower},\{row.range_upper},\{row.mean_lower},\{row.mean_upper},\{row.half_units}",
    )
  }
  lines.join("\n") + "\n"
}

///|
// Both axes have already passed validate_edges. Each old bin is assigned
// once, and each requested boundary must coincide with an old boundary.
fn coarsen_axis(
  axis : String,
  source : Array[Double],
  requested : Array[Double],
) -> Array[Int32] raise RainError {
  guard source[0] == requested[0] &&
    source[source.length() - 1] == requested[requested.length() - 1] else {
    raise InvalidEdges(axis + ": coarsening must preserve outer endpoints")
  }
  let mapping = Array::make(source.length() - 1, 0)
  let mut old_bin = 0
  for new_bin in 0..<(requested.length() - 1) {
    let upper = requested[new_bin + 1]
    while old_bin < mapping.length() && source[old_bin] < upper {
      mapping[old_bin] = new_bin
      old_bin += 1
    }
    guard source[old_bin] == upper else {
      raise InvalidEdges(
        "\{axis}: coarsening edge \{upper} is not an existing edge",
      )
    }
  }
  mapping
}

///|
/// Aggregate adjacent bins exactly into a new, independent spectrum.
/// Requested axes must be existing-edge subsequences with unchanged outer
/// endpoints. No bin is split, and total and outside weights are preserved.
/// Runs in O(source cells + axis edges) time.
pub fn Spectrum::coarsen(
  self : Spectrum,
  range_edges : Array[Double],
  mean_edges : Array[Double],
) -> Spectrum raise RainError {
  let result = Spectrum::new(range_edges, mean_edges)
  let rows = coarsen_axis("range", self.ranges, result.ranges)
  let cols = coarsen_axis("mean", self.means, result.means)
  let old_width = self.means.length() - 1
  let new_width = result.means.length() - 1
  for old_row, new_row in rows {
    for old_col, new_col in cols {
      let destination = new_row * new_width + new_col
      // Each sum is a subset of the already validated nonnegative total.
      result.cells[destination] = result.cells[destination] +
        self.cells[old_row * old_width + old_col]
    }
  }
  result.total = self.total
  result.outside = self.outside
  result
}
