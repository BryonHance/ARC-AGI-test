"""Python bindings for the labeling core, used by the tkinter UI.

A thin adapter: every rule lives in app.mojo. Python imports this file with
`import mojo.importer; import labeling`.
"""
from std.os import abort
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
import app


@export
def PyInit_labeling() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("labeling")
        m.def_function[grid_addresses]("grid_addresses", docstring="(split, pair, side) of every Grid in a task file")
        _ = (
            m.add_type[Labeling]("Labeling")
            .def_py_init[Labeling.py_init]()
            .def_method[Labeling.rows]("rows")
            .def_method[Labeling.cols]("cols")
            .def_method[Labeling.cells]("cells")
            .def_method[Labeling.background]("background")
            .def_method[Labeling.background_source]("background_source")
            .def_method[Labeling.set_background]("set_background")
            .def_method[Labeling.objects]("objects")
            .def_method[Labeling.unclaimed]("unclaimed")
            .def_method[Labeling.reconstruct]("reconstruct")
            .def_method[Labeling.propose]("propose")
            .def_method[Labeling.add_object]("add_object")
            .def_method[Labeling.remove_object]("remove_object")
            .def_method[Labeling.state]("state")
            .def_method[Labeling.note]("note")
            .def_method[Labeling.flag]("flag")
            .def_method[Labeling.unflag]("unflag")
            .def_method[Labeling.save]("save")
        )
        return m.finalize()
    except e:
        abort(String("error creating labeling module:", e))


def grid_addresses(task_path: PythonObject) raises -> PythonObject:
    var task = app.load_task(app.get_path(String(task_path)))
    var result = Python.list()
    for split in ["train", "test"]:
        var count = len(task.train) if split == "train" else len(task.test)
        for pair in range(count):
            for side in ["input", "output"]:
                result.append(Python.tuple(split, pair, side))
    return result


def _to_list(values: List[Int]) raises -> PythonObject:
    var result = Python.list()
    for v in values:
        result.append(v)
    return result


def _from_list(values: PythonObject) raises -> List[Int]:
    var result = List[Int]()
    for v in values:
        result.append(Int(py=v))
    return result^


struct Labeling(Movable, Writable):
    """One Grid's Decomposition, plus where it is saved."""
    var id: app.GridId
    var root: String
    var d: app.Decomposition

    def __init__(out self, var id: app.GridId, var root: String, var d: app.Decomposition):
        self.id = id^
        self.root = root^
        self.d = d^

    @staticmethod
    def py_init(out self: Labeling, args: PythonObject, kwargs: PythonObject) raises:
        """Labeling(root, task_path, dataset, split, pair, side): loads any saved Decomposition."""
        if len(args) != 6:
            raise Error("Labeling(root, task_path, dataset, split, pair, side)")
        var task_path = app.get_path(String(args[1]))
        var split = String(args[3])
        var pair = Int(py=args[4])
        var side = String(args[5])
        var task_id = task_path.name().removesuffix(".json")
        var id = app.GridId(dataset=String(args[2]), task=String(task_id), split=split, pair=pair, side=side)
        var grid = app.load_task(task_path).grid(split, pair, side)
        var root = String(args[0])
        self = Self(id.copy(), root, app.load(root, id, grid))

    def write_to(self, mut writer: Some[Writer]):
        t"Labeling({self.id.stem()}, {self.d.state()})".write_to(writer)

    def write_repr_to(self, mut writer: Some[Writer]):
        self.write_to(writer)

    @staticmethod
    def rows(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return self_ptr[].d.grid.rows

    @staticmethod
    def cols(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return self_ptr[].d.grid.cols

    @staticmethod
    def cells(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return _to_list(self_ptr[].d.grid.cells)

    @staticmethod
    def background(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return self_ptr[].d.background

    @staticmethod
    def background_source(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return self_ptr[].d.background_source

    @staticmethod
    def set_background(py_self: PythonObject, color: PythonObject) raises:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        self_ptr[].d.set_background(Int(py=color))

    @staticmethod
    def objects(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        var result = Python.list()
        for obj in self_ptr[].d.objects:
            result.append(_to_list(obj))
        return result

    @staticmethod
    def unclaimed(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return _to_list(self_ptr[].d.unclaimed())

    @staticmethod
    def reconstruct(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return _to_list(app.reconstruct(self_ptr[].d).cells)

    @staticmethod
    def propose(py_self: PythonObject, row: PythonObject, col: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        ref d = self_ptr[].d
        return _to_list(app.propose(d.grid, Int(py=row), Int(py=col), d.claimed(), d.background))

    @staticmethod
    def add_object(py_self: PythonObject, cells: PythonObject) raises:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        self_ptr[].d.add_object(_from_list(cells))

    @staticmethod
    def remove_object(py_self: PythonObject, index: PythonObject) raises:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        self_ptr[].d.remove_object(Int(py=index))

    @staticmethod
    def state(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return self_ptr[].d.state()

    @staticmethod
    def note(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return self_ptr[].d.note

    @staticmethod
    def flag(py_self: PythonObject, note: PythonObject) raises:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        self_ptr[].d.flag(String(note))

    @staticmethod
    def unflag(py_self: PythonObject) raises:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        self_ptr[].d.unflag()

    @staticmethod
    def save(py_self: PythonObject) raises:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        app.save(self_ptr[].d, self_ptr[].id, self_ptr[].root)
