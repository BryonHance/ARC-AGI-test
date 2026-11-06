from std.pathlib import Path
from std.python import Python, PythonObject
from std.tempfile import mkdtemp
from std.testing import assert_equal, assert_raises, TestSuite
import app

comptime FILE = "./data/test_training/12345678.json"
comptime JSON_STR = '{"train": [{"input": [[0, 1], [2, 3]], "output": [[1, 2], [3, 4]]}, {"input": [[0, 4], [0, 0]], "output":[[0, 5], [0, 0]]}], "test": [{"input": [[4, 5], [6, 7]], "output": [[5, 6], [7, 8]]}]}'

def test_get_path() raises:
    var p = app.get_path(FILE)
    assert_equal(p.is_file(), True)

def test_get_path_invalid() raises:
    with assert_raises():
        _ = app.get_path("dummy")

def test_read_file() raises:
    var p = app.get_path(FILE)
    assert_equal(app.read_file(p), JSON_STR)


def test_background_is_most_common_color() raises:
    var grid = app.Grid(rows=2, cols=3, cells=[3, 3, 3, 0, 5, 5])
    assert_equal(app.background(grid), 3)


def test_background_tie_goes_to_lowest_color() raises:
    var grid = app.Grid(rows=2, cols=2, cells=[7, 2, 2, 7])
    assert_equal(app.background(grid), 2)


def test_propose_stops_at_background() raises:
    # 1 1 0
    # 0 0 0
    # 0 0 2
    var grid = app.Grid(rows=3, cols=3, cells=[1, 1, 0, 0, 0, 0, 0, 0, 2])
    var claimed = List[Bool](length=9, fill=False)
    assert_equal(app.propose(grid, 0, 0, claimed, 0), [0, 1])


def test_propose_follows_diagonals() raises:
    # 4 0 0
    # 0 4 0
    # 0 0 4
    var grid = app.Grid(rows=3, cols=3, cells=[4, 0, 0, 0, 4, 0, 0, 0, 4])
    var claimed = List[Bool](length=9, fill=False)
    assert_equal(app.propose(grid, 0, 0, claimed, 0), [0, 4, 8])


def test_propose_stops_at_claimed_cells() raises:
    # 1 1 2 2, with the two 1s already claimed by an Object
    var grid = app.Grid(rows=1, cols=4, cells=[1, 1, 2, 2])
    var claimed: List[Bool] = [True, True, False, False]
    assert_equal(app.propose(grid, 0, 3, claimed, 0), [2, 3])


def test_propose_crosses_colors() raises:
    # 0 1 0
    # 0 2 3
    var grid = app.Grid(rows=2, cols=3, cells=[0, 1, 0, 0, 2, 3])
    var claimed = List[Bool](length=6, fill=False)
    assert_equal(app.propose(grid, 0, 1, claimed, 0), [1, 4, 5])


def test_propose_from_background_or_claimed_cell_is_empty() raises:
    # 1 1 0 2, with the two 1s already claimed by an Object
    var grid = app.Grid(rows=1, cols=4, cells=[1, 1, 0, 2])
    var claimed: List[Bool] = [True, True, False, False]
    assert_equal(app.propose(grid, 0, 2, claimed, 0), List[Int]())
    assert_equal(app.propose(grid, 0, 0, claimed, 0), List[Int]())


def test_all_background_grid_is_complete_with_zero_objects() raises:
    var grid = app.Grid(rows=2, cols=2, cells=[0, 0, 0, 0])
    var d = app.Decomposition(grid)
    assert_equal(len(d.objects), 0)
    assert_equal(d.is_complete(), True)


def test_grid_is_complete_once_every_non_background_cell_is_claimed() raises:
    # 1 1 0
    # 0 0 2
    var grid = app.Grid(rows=2, cols=3, cells=[1, 1, 0, 0, 0, 2])
    var d = app.Decomposition(grid)
    assert_equal(d.unclaimed(), [0, 1, 5])
    assert_equal(d.is_complete(), False)

    d.add_object([0, 1])
    assert_equal(d.unclaimed(), [5])
    assert_equal(d.is_complete(), False)

    d.add_object([5])
    assert_equal(d.is_complete(), True)


def test_cell_cannot_belong_to_two_objects() raises:
    # 1 1 2
    # 0 0 0
    var grid = app.Grid(rows=2, cols=3, cells=[1, 1, 2, 0, 0, 0])
    var d = app.Decomposition(grid)
    d.add_object([0, 1])
    with assert_raises():
        d.add_object([1, 2])
    assert_equal(len(d.objects), 1)


def test_background_cell_cannot_belong_to_an_object() raises:
    var grid = app.Grid(rows=1, cols=3, cells=[1, 0, 0])
    var d = app.Decomposition(grid)
    with assert_raises():
        d.add_object([0, 1])
    assert_equal(len(d.objects), 0)


def test_removing_an_object_frees_its_cells() raises:
    # 1 0 2
    # 0 0 0
    var grid = app.Grid(rows=2, cols=3, cells=[1, 0, 2, 0, 0, 0])
    var d = app.Decomposition(grid)
    d.add_object([0])
    d.add_object([2])
    d.remove_object(0)
    assert_equal(d.unclaimed(), [0])
    assert_equal(d.objects[0], [2])


def test_background_defaults_to_most_common_color() raises:
    var grid = app.Grid(rows=1, cols=3, cells=[3, 3, 0])
    var d = app.Decomposition(grid)
    assert_equal(d.background, 3)
    assert_equal(d.background_source, "most_common")


def test_labeler_can_override_background() raises:
    # Green (3) covers most cells, but the Labeler says black (0) is Background.
    var grid = app.Grid(rows=1, cols=3, cells=[3, 3, 0])
    var d = app.Decomposition(grid, background=0)
    assert_equal(d.background, 0)
    assert_equal(d.background_source, "user")
    assert_equal(d.unclaimed(), [0, 1])


def test_reconstruction_shows_only_claimed_objects_on_background() raises:
    # 1 1 0
    # 0 0 2
    var grid = app.Grid(rows=2, cols=3, cells=[1, 1, 0, 0, 0, 2])
    var d = app.Decomposition(grid)
    d.add_object([5])
    var r = app.reconstruct(d)
    assert_equal(r.rows, 2)
    assert_equal(r.cols, 3)
    assert_equal(r.cells, [0, 0, 0, 0, 0, 2])


def test_complete_reconstruction_matches_original() raises:
    # Green (3) covers most cells, but the Labeler says black (0) is Background.
    var grid = app.Grid(rows=1, cols=3, cells=[3, 3, 0])
    var d = app.Decomposition(grid, background=0)
    d.add_object([0, 1])
    assert_equal(d.is_complete(), True)
    assert_equal(app.reconstruct(d).cells, [3, 3, 0])


def test_load_task_reads_a_grid() raises:
    var task = app.load_task(app.get_path(FILE))
    var g = task.grid("train", 0, "input")
    assert_equal(g.rows, 2)
    assert_equal(g.cols, 2)
    assert_equal(g.cells, [0, 1, 2, 3])


def test_load_task_addresses_grids_by_split_pair_and_side() raises:
    var task = app.load_task(app.get_path(FILE))
    assert_equal(len(task.train), 2)
    assert_equal(len(task.test), 1)
    assert_equal(task.grid("train", 1, "output").cells, [0, 5, 0, 0])
    assert_equal(task.grid("test", 0, "input").cells, [4, 5, 6, 7])
    assert_equal(task.grid("test", 0, "output").cells, [5, 6, 7, 8])


def test_unknown_split_or_side_raises() raises:
    var task = app.load_task(app.get_path(FILE))
    with assert_raises():
        _ = task.grid("tset", 0, "input")
    with assert_raises():
        _ = task.grid("train", 0, "inptu")


def test_load_task_rejects_ragged_rows() raises:
    with assert_raises():
        _ = app.load_task(app.get_path("./data/test_training/ragged.json"))


def test_save_writes_decomposition_file_at_grid_path() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="training", task="12345678", split="train", pair=0, side="input")
    var d = app.Decomposition(app.Grid(rows=1, cols=3, cells=[1, 0, 0]))
    app.save(d, id, root)
    assert_equal((Path(root) / "training/12345678/12345678_train0_in.json").exists(), True)


def test_saved_decomposition_loads_back() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="training", task="12345678", split="test", pair=0, side="output")
    # 3 3 0
    # 0 2 0
    var grid = app.Grid(rows=2, cols=3, cells=[3, 3, 0, 0, 2, 0])
    var d = app.Decomposition(grid, background=0)
    d.add_object([0, 1])
    d.add_object([4])
    app.save(d, id, root)

    var loaded = app.load(root, id, grid)
    assert_equal(loaded.background, 0)
    assert_equal(loaded.background_source, "user")
    assert_equal(len(loaded.objects), 2)
    assert_equal(loaded.objects[0], [0, 1])
    assert_equal(loaded.objects[1], [4])


def read_json(path: Path) raises -> PythonObject:
    return Python.import_module("json").loads(path.read_text())


def test_object_file_holds_cropped_shape_and_offset() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="training", task="12345678", split="train", pair=1, side="output")
    # 5 0 0
    # 5 5 0
    # 0 0 7
    var d = app.Decomposition(app.Grid(rows=3, cols=3, cells=[5, 0, 0, 5, 5, 0, 0, 0, 7]))
    d.add_object([0, 3, 4])
    d.add_object([8])
    app.save(d, id, root)

    var dir = Path(root) / "training/12345678"
    var l_shape = read_json(dir / "12345678_train1_out_obj01.json")
    assert_equal(String(l_shape["offset"]), "[0, 0]")
    assert_equal(String(l_shape["shape"]), "[[5, -1], [5, 5]]")
    var dot = read_json(dir / "12345678_train1_out_obj02.json")
    assert_equal(String(dot["offset"]), "[2, 2]")
    assert_equal(String(dot["shape"]), "[[7]]")


def test_object_file_carries_grid_and_object_metadata() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="evaluation", task="abcdef01", split="test", pair=0, side="input")
    # 4 6 0
    # 0 4 0
    var d = app.Decomposition(app.Grid(rows=2, cols=3, cells=[4, 6, 0, 0, 4, 0]))
    d.add_object([0, 1, 4])
    app.save(d, id, root)

    var obj = read_json(Path(root) / "evaluation/abcdef01/abcdef01_test0_in_obj01.json")
    assert_equal(String(obj["dataset"]), "evaluation")
    assert_equal(String(obj["task"]), "abcdef01")
    assert_equal(String(obj["split"]), "test")
    assert_equal(Int(py=obj["pair"]), 0)
    assert_equal(String(obj["side"]), "input")
    assert_equal(String(obj["grid_size"]), "[2, 3]")
    assert_equal(Int(py=obj["object"]), 1)
    assert_equal(String(obj["colors"]), "[4, 6]")
    assert_equal(Int(py=obj["cell_count"]), 3)
    assert_equal(Int(py=obj["background"]), 0)
    assert_equal(String(obj["background_source"]), "most_common")


def test_state_follows_labeling_progress() raises:
    # 1 0 2
    # 0 0 0
    var d = app.Decomposition(app.Grid(rows=2, cols=3, cells=[1, 0, 2, 0, 0, 0]))
    assert_equal(d.state(), "unlabeled")
    d.add_object([0])
    assert_equal(d.state(), "in_progress")
    d.add_object([2])
    assert_equal(d.state(), "complete")


def test_flagged_grid_stays_flagged_until_cleared() raises:
    # 1 0 2
    # 0 0 0
    var d = app.Decomposition(app.Grid(rows=2, cols=3, cells=[1, 0, 2, 0, 0, 0]))
    d.add_object([0])
    d.flag("Is the 2 noise or part of the 1?")
    assert_equal(d.state(), "flagged")
    assert_equal(d.note, "Is the 2 noise or part of the 1?")
    d.unflag()
    assert_equal(d.state(), "in_progress")
    assert_equal(d.note, "")


def test_decomposition_file_records_state_and_flag_survives_reload() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="training", task="12345678", split="train", pair=0, side="input")
    # 1 0 2
    # 0 0 0
    var grid = app.Grid(rows=2, cols=3, cells=[1, 0, 2, 0, 0, 0])
    var d = app.Decomposition(grid)
    d.add_object([0])
    d.flag("Is the 2 noise?")
    app.save(d, id, root)

    var doc = read_json(Path(root) / "training/12345678/12345678_train0_in.json")
    assert_equal(String(doc["state"]), "flagged")
    assert_equal(String(doc["note"]), "Is the 2 noise?")
    assert_equal(String(doc["objects"]), "['12345678_train0_in_obj01.json']")

    var loaded = app.load(root, id, grid)
    assert_equal(loaded.state(), "flagged")
    assert_equal(loaded.note, "Is the 2 noise?")


def test_objects_are_numbered_in_reading_order() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="training", task="12345678", split="train", pair=0, side="input")
    # 0 0 7
    # 5 0 0
    # 0 0 0
    var d = app.Decomposition(app.Grid(rows=3, cols=3, cells=[0, 0, 7, 5, 0, 0, 0, 0, 0]))
    d.add_object([3])  # the Labeler clicked the lower object first
    d.add_object([2])
    app.save(d, id, root)

    var dir = Path(root) / "training/12345678"
    assert_equal(String(read_json(dir / "12345678_train0_in_obj01.json")["offset"]), "[0, 2]")
    assert_equal(String(read_json(dir / "12345678_train0_in_obj02.json")["offset"]), "[1, 0]")


def test_resaving_removes_files_of_deleted_objects() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="training", task="12345678", split="train", pair=0, side="input")
    # 0 0 7
    # 5 0 0
    # 0 0 0
    var d = app.Decomposition(app.Grid(rows=3, cols=3, cells=[0, 0, 7, 5, 0, 0, 0, 0, 0]))
    d.add_object([2])
    d.add_object([3])
    app.save(d, id, root)
    d.remove_object(0)
    app.save(d, id, root)

    var dir = Path(root) / "training/12345678"
    assert_equal(String(read_json(dir / "12345678_train0_in_obj01.json")["offset"]), "[1, 0]")
    assert_equal((dir / "12345678_train0_in_obj02.json").exists(), False)


def test_resaving_leaves_other_grids_files_alone() raises:
    var root = mkdtemp()
    var input_id = app.GridId(dataset="training", task="12345678", split="train", pair=1, side="input")
    var output_id = app.GridId(dataset="training", task="12345678", split="train", pair=1, side="output")
    var other_pair_id = app.GridId(dataset="training", task="12345678", split="train", pair=10, side="input")
    var d = app.Decomposition(app.Grid(rows=1, cols=3, cells=[5, 0, 0]))
    d.add_object([0])
    app.save(d, output_id, root)
    app.save(d, other_pair_id, root)
    app.save(d, input_id, root)

    var dir = Path(root) / "training/12345678"
    assert_equal((dir / "12345678_train1_out_obj01.json").exists(), True)
    assert_equal((dir / "12345678_train10_in_obj01.json").exists(), True)


def test_loading_a_never_saved_grid_gives_a_fresh_decomposition() raises:
    var root = mkdtemp()
    var id = app.GridId(dataset="training", task="12345678", split="train", pair=0, side="input")
    var grid = app.Grid(rows=1, cols=3, cells=[5, 0, 0])
    var d = app.load(root, id, grid)
    assert_equal(d.state(), "unlabeled")
    assert_equal(d.background, 0)
    assert_equal(d.background_source, "most_common")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()