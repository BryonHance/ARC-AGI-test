from std.pathlib import Path
from std.python import Python, PythonObject

comptime NUM_COLORS = 10

@fieldwise_init
struct Grid(Copyable, Movable):
    var rows: Int
    var cols: Int
    var cells: List[Int]

def background(grid: Grid) -> Int:
    var counts = List[Int](length=NUM_COLORS, fill=0)
    for c in grid.cells:
        counts[c] += 1
    var best = 0
    for color in range(NUM_COLORS):
        if counts[color] > counts[best]:
            best = color
    return best

def propose(grid: Grid, row: Int, col: Int, claimed: List[Bool], bg: Int) raises -> List[Int]:
    """Flood fill from (row, col) through non-background cells. Returns cell indices in reading order."""
    if row < 0 or row >= grid.rows or col < 0 or col >= grid.cols:
        raise Error(t"Cell ({row}, {col}) is outside the grid")
    var start = row * grid.cols + col
    if claimed[start] or grid.cells[start] == bg:
        return List[Int]()
    var seen = List[Bool](length=len(grid.cells), fill=False)
    var stack: List[Int] = [start]
    seen[stack[0]] = True
    while stack:
        var i = stack.pop()
        var r = i // grid.cols
        var c = i % grid.cols
        for d in [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]:
            var nr = r + d[0]
            var nc = c + d[1]
            if nr < 0 or nr >= grid.rows or nc < 0 or nc >= grid.cols:
                continue
            var n = nr * grid.cols + nc
            if seen[n] or claimed[n] or grid.cells[n] == bg:
                continue
            seen[n] = True
            stack.append(n)
    var cells = List[Int]()
    for i in range(len(seen)):
        if seen[i]:
            cells.append(i)
    return cells^

def _first_cell(cells: List[Int]) -> Int:
    var first = cells[0]
    for i in cells:
        first = min(first, i)
    return first

def _sort_reading_order(mut objects: List[List[Int]]):
    """Insertion sort by each Object's first cell in reading order."""
    for i in range(1, len(objects)):
        var j = i
        while j > 0 and _first_cell(objects[j]) < _first_cell(objects[j - 1]):
            objects.swap_elements(j, j - 1)
            j -= 1

struct Decomposition(Copyable, Movable):
    var grid: Grid
    var background: Int
    var background_source: String
    var objects: List[List[Int]]
    var flagged: Bool
    var note: String

    def __init__(out self, grid: Grid):
        self.grid = grid.copy()
        self.background = background(grid)
        self.background_source = "most_common"
        self.objects = List[List[Int]]()
        self.flagged = False
        self.note = ""

    def __init__(out self, grid: Grid, *, background: Int) raises:
        if background < 0 or background >= NUM_COLORS:
            raise Error(t"Background {background} is not a color")
        self.grid = grid.copy()
        self.background = background
        self.background_source = "labeler"
        self.objects = List[List[Int]]()
        self.flagged = False
        self.note = ""

    def add_object(mut self, cells: List[Int]) raises:
        if len(cells) == 0:
            raise Error("An object needs at least one cell")
        var claimed = self.claimed()
        for i in cells:
            if i < 0 or i >= len(self.grid.cells):
                raise Error(t"Cell {i} is outside the grid")
            if claimed[i]:
                raise Error(t"Cell {i} already belongs to an object")
            if self.grid.cells[i] == self.background:
                raise Error(t"Cell {i} is background")
            claimed[i] = True  # also catches a cell repeated within this object
        self.objects.append(cells.copy())
        _sort_reading_order(self.objects)

    def remove_object(mut self, index: Int):
        _ = self.objects.pop(index)

    def claimed(self) -> List[Bool]:
        var claimed = List[Bool](length=len(self.grid.cells), fill=False)
        for obj in self.objects:
            for i in obj:
                claimed[i] = True
        return claimed^

    def unclaimed(self) -> List[Int]:
        """Non-background cells not yet in any object, in reading order."""
        var claimed = self.claimed()
        var cells = List[Int]()
        for i in range(len(self.grid.cells)):
            if not claimed[i] and self.grid.cells[i] != self.background:
                cells.append(i)
        return cells^

    def is_complete(self) -> Bool:
        return len(self.unclaimed()) == 0

    def flag(mut self, note: String):
        self.flagged = True
        self.note = note

    def unflag(mut self):
        self.flagged = False
        self.note = ""

    def state(self) -> String:
        if self.flagged:
            return "flagged"
        if self.is_complete():
            return "complete"
        if len(self.objects) > 0:
            return "in_progress"
        return "unlabeled"

def reconstruct(d: Decomposition) -> Grid:
    """Background plus every Object in its original colors."""
    var cells = List[Int](length=len(d.grid.cells), fill=d.background)
    for obj in d.objects:
        for i in obj:
            cells[i] = d.grid.cells[i]
    return Grid(rows=d.grid.rows, cols=d.grid.cols, cells=cells^)

def get_path(p: String)raises -> Path:
    var path = Path(p)
    if not path.exists():
        raise Error(t"Invalid path: {p}")
    return path

def read_file(p: Path) raises -> String:
    try:
        return p.read_text()
    except:
        raise Error(t"Failed to read file: {p}")

@fieldwise_init
struct Pair(Copyable, Movable):
    var input: Grid
    var output: Grid

@fieldwise_init
struct Task(Copyable, Movable):
    var train: List[Pair]
    var test: List[Pair]

    def grid(self, split: String, pair: Int, side: String) raises -> Grid:
        if split != "train" and split != "test":
            raise Error(t"Unknown split: {split}")
        if side != "input" and side != "output":
            raise Error(t"Unknown side: {side}")
        ref pairs = self.train if split == "train" else self.test
        if pair < 0 or pair >= len(pairs):
            raise Error(t"No {split} pair {pair}")
        var p = pairs[pair].copy()
        return p.input.copy() if side == "input" else p.output.copy()

def _to_grid(rows: PythonObject) raises -> Grid:
    if len(rows) == 0 or len(rows[0]) == 0:
        raise Error("Grid is empty")
    var cols = len(rows[0])
    var cells = List[Int]()
    for row in rows:
        if len(row) != cols:
            raise Error("Grid rows have different lengths")
        for c in row:
            var color = Int(py=c)
            if color < 0 or color >= NUM_COLORS:
                raise Error(t"Color {color} is outside 0-9")
            cells.append(color)
    return Grid(rows=len(rows), cols=cols, cells=cells^)

def _to_pairs(pairs: PythonObject) raises -> List[Pair]:
    var result = List[Pair]()
    for p in pairs:
        result.append(Pair(input=_to_grid(p["input"]), output=_to_grid(p["output"])))
    return result^

def load_task(p: Path) raises -> Task:
    var data = Python.import_module("json").loads(read_file(p))
    return Task(train=_to_pairs(data["train"]), test=_to_pairs(data["test"]))

@fieldwise_init
struct GridId(Copyable, Movable):
    var dataset: String
    var task: String
    var split: String
    var pair: Int
    var side: String

    def stem(self) -> String:
        """File name stem, e.g. 12345678_train0_in."""
        var side = "in" if self.side == "input" else "out"
        return String(t"{self.task}_{self.split}{self.pair}_{side}")

    def dir(self, root: String) -> Path:
        return Path(root) / self.dataset / self.task

def _grid_json(d: Decomposition, id: GridId) raises -> PythonObject:
    """Metadata shared by decomposition and object files."""
    var doc = Python.dict()
    doc["dataset"] = id.dataset
    doc["task"] = id.task
    doc["split"] = id.split
    doc["pair"] = id.pair
    doc["side"] = id.side
    doc["grid_size"] = Python.list(d.grid.rows, d.grid.cols)
    doc["background"] = d.background
    doc["background_source"] = d.background_source
    return doc

def _object_json(d: Decomposition, id: GridId, index: Int) raises -> PythonObject:
    """Cropped bounding box (-1 outside the Object) plus its offset in the Grid."""
    ref cells = d.objects[index]
    var cols = d.grid.cols
    var r0 = d.grid.rows
    var c0 = cols
    var r1 = 0
    var c1 = 0
    for i in cells:
        r0 = min(r0, i // cols)
        r1 = max(r1, i // cols)
        c0 = min(c0, i % cols)
        c1 = max(c1, i % cols)
    var crop = Python.list()
    for _ in range(r1 - r0 + 1):
        var row = Python.list()
        for _ in range(c1 - c0 + 1):
            row.append(-1)
        crop.append(row)
    for i in cells:
        crop[i // cols - r0][i % cols - c0] = d.grid.cells[i]
    var used = List[Bool](length=NUM_COLORS, fill=False)
    for i in cells:
        used[d.grid.cells[i]] = True
    var colors = Python.list()
    for color in range(NUM_COLORS):
        if used[color]:
            colors.append(color)
    var obj = _grid_json(d, id)
    obj["object"] = index + 1
    obj["colors"] = colors
    obj["cell_count"] = len(cells)
    obj["offset"] = Python.list(r0, c0)
    obj["crop"] = crop
    return obj

def save(d: Decomposition, id: GridId, root: String) raises:
    var json = Python.import_module("json")
    var os = Python.import_module("os")
    var dir = id.dir(root)
    os.makedirs(String(dir), exist_ok=True)
    var prefix = id.stem() + "_obj"
    for name in dir.listdir():
        if String(name).startswith(prefix):
            os.remove(String(dir / name))
    var names = Python.list()
    for n in range(len(d.objects)):
        var num = String(n + 1)
        if n + 1 < 10:
            num = "0" + num
        var name = String(t"{id.stem()}_obj{num}.json")
        (dir / name).write_text(String(json.dumps(_object_json(d, id, n))))
        names.append(name)
    var doc = _grid_json(d, id)
    doc["state"] = d.state()
    doc["note"] = d.note
    doc["objects"] = names
    (dir / (id.stem() + ".json")).write_text(String(json.dumps(doc)))

def load(root: String, id: GridId, grid: Grid) raises -> Decomposition:
    var json = Python.import_module("json")
    var dir = id.dir(root)
    var path = dir / (id.stem() + ".json")
    if not path.exists():
        return Decomposition(grid)
    var doc = json.loads(read_file(path))
    if Int(py=doc["grid_size"][0]) != grid.rows or Int(py=doc["grid_size"][1]) != grid.cols:
        raise Error(t"Saved grid size does not match {grid.rows}x{grid.cols} grid: {path}")
    var d = Decomposition(grid, background=Int(py=doc["background"]))
    d.background_source = String(py=doc["background_source"])
    for name in doc["objects"]:
        var obj = json.loads(read_file(dir / String(py=name)))
        var r0 = Int(py=obj["offset"][0])
        var c0 = Int(py=obj["offset"][1])
        var cells = List[Int]()
        var crop = obj["crop"]
        for r in range(len(crop)):
            for c in range(len(crop[r])):
                var color = Int(py=crop[r][c])
                if color >= 0:
                    var i = (r0 + r) * grid.cols + c0 + c
                    if grid.cells[i] != color:
                        raise Error(t"Saved color does not match grid at cell {i}: {name}")
                    cells.append(i)
        d.add_object(cells)
    if String(py=doc["state"]) == "flagged":
        d.flag(String(py=doc["note"]))
    return d^
