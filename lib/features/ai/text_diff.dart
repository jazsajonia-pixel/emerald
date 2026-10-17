enum DiffOp { same, added, removed }

class DiffLine {
  const DiffLine(this.op, this.text);
  final DiffOp op;
  final String text;
}

/// Line-based diff (LCS). Falls back to "all removed / all added" for very
/// large inputs to bound memory use.
List<DiffLine> diffLines(
  String before,
  String after, {
  int maxCells = 4000000,
}) {
  final a = before.split('\n');
  final b = after.split('\n');
  if (a.length * b.length > maxCells) {
    return [
      for (final l in a) DiffLine(DiffOp.removed, l),
      for (final l in b) DiffLine(DiffOp.added, l),
    ];
  }
  final n = a.length, m = b.length;
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffOp.same, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(DiffLine(DiffOp.removed, a[i++]));
    } else {
      out.add(DiffLine(DiffOp.added, b[j++]));
    }
  }
  while (i < n) {
    out.add(DiffLine(DiffOp.removed, a[i++]));
  }
  while (j < m) {
    out.add(DiffLine(DiffOp.added, b[j++]));
  }
  return out;
}
