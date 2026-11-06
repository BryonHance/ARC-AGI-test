"""Tkinter UI for decomposing ARC Grids into Objects.

A thin layer over the Mojo core (app.mojo, via the labeling.mojo binding).
Vocabulary follows GLOSSARY.md.
"""
import json
import sys
import tkinter as tk
from pathlib import Path
from tkinter import ttk

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

import mojo.importer  # noqa: E402,F401  (installs the .mojo import hook)
import labeling  # noqa: E402

DATASETS = ("training", "evaluation")
OBJECTS_ROOT = REPO / "objects"
COLORS = ("#000000", "#0074D9", "#FF4136", "#2ECC40", "#FFDC00",
          "#AAAAAA", "#F012BE", "#FF851B", "#7FDBFF", "#870C25")
NOT_DONE = ("unlabeled", "in_progress")
MAX_CANVAS = 480
PROPOSAL_OUTLINE = "#FFFFFF"
SELECTED_OUTLINE = "#FFDC00"
BORDER = "#FFFFFF"
UNCLAIMED_MARK = "#FF00FF"


class GridRef:
    """Where one Grid lives: its task file plus split, pair and side."""

    def __init__(self, dataset, task_path, split, pair, side):
        self.dataset, self.task_path = dataset, task_path
        self.split, self.pair, self.side = split, pair, side

    @property
    def task(self):
        return self.task_path.stem

    @property
    def stem(self):
        return f"{self.task}_{self.split}{self.pair}_{'in' if self.side == 'input' else 'out'}"

    def saved_state(self):
        path = OBJECTS_ROOT / self.dataset / self.task / f"{self.stem}.json"
        if not path.exists():
            return "unlabeled"
        return json.loads(path.read_text())["state"]

    def open(self):
        return labeling.Labeling(str(OBJECTS_ROOT), str(self.task_path), self.dataset,
                                 self.split, self.pair, self.side)

    def __str__(self):
        return f"{self.task}  {self.split} {self.pair}  {self.side}"


def build_queue(dataset):
    """Every Grid in a Dataset: tasks by id, then train before test, input before output."""
    queue = []
    for task_path in sorted((REPO / "data" / dataset).glob("*.json")):
        for split, pair, side in labeling.grid_addresses(str(task_path)):
            queue.append(GridRef(dataset, task_path, split, pair, side))
    return queue


class LabelingApp:
    def __init__(self, root):
        self.root = root
        root.title("ARC Object Labeling")
        self.queues = {}
        self.states = {}
        self.index = 0
        self.grid = None          # labeling.Labeling for the current Grid
        self.proposal = set()     # cells of the Object being built, before confirming
        self.selected = None      # index of the Object highlighted in the list
        self._build_widgets()
        self.switch_dataset()

    # ---- layout -------------------------------------------------------------

    def _build_widgets(self):
        top = ttk.Frame(self.root, padding=6)
        top.pack(fill="x")
        ttk.Label(top, text="Dataset").pack(side="left")
        self.dataset_var = tk.StringVar(value=DATASETS[0])
        ds = ttk.Combobox(top, textvariable=self.dataset_var, values=DATASETS, state="readonly", width=11)
        ds.pack(side="left", padx=4)
        ds.bind("<<ComboboxSelected>>", lambda e: self.switch_dataset())
        self.held_out = ttk.Label(top, text="", foreground="#C00")
        self.held_out.pack(side="left", padx=6)
        ttk.Button(top, text="◀ Prev", command=self.prev_grid).pack(side="left", padx=2)
        ttk.Button(top, text="Next ▶", command=self.next_grid).pack(side="left", padx=2)
        ttk.Label(top, text="Task").pack(side="left", padx=(12, 2))
        self.jump_var = tk.StringVar()
        jump = ttk.Entry(top, textvariable=self.jump_var, width=10)
        jump.pack(side="left")
        jump.bind("<Return>", lambda e: self.jump_to_task())
        ttk.Button(top, text="Go", command=self.jump_to_task).pack(side="left", padx=2)
        self.progress = ttk.Label(top, text="")
        self.progress.pack(side="right")

        self.title = ttk.Label(self.root, text="", font=("TkDefaultFont", 12, "bold"), padding=(6, 0))
        self.title.pack(fill="x")

        body = ttk.Frame(self.root, padding=6)
        body.pack(fill="both", expand=True)

        left = ttk.Frame(body)
        left.pack(side="left", padx=4)
        ttk.Label(left, text="Grid — click to propose an Object, click cells to add/remove, Enter to confirm, Esc to cancel").pack()
        self.grid_canvas = tk.Canvas(left, width=MAX_CANVAS, height=MAX_CANVAS, bg="#333", highlightthickness=0)
        self.grid_canvas.pack()
        self.grid_canvas.bind("<Button-1>", self.on_grid_click)

        middle = ttk.Frame(body)
        middle.pack(side="left", padx=4)
        ttk.Label(middle, text="Reconstruction — magenta × marks unclaimed cells").pack()
        self.recon_canvas = tk.Canvas(middle, width=MAX_CANVAS, height=MAX_CANVAS, bg="#333", highlightthickness=0)
        self.recon_canvas.pack()

        side = ttk.Frame(body)
        side.pack(side="left", fill="y", padx=4)

        ttk.Label(side, text="Objects").pack(anchor="w")
        self.object_list = tk.Listbox(side, height=12, width=28, exportselection=False)
        self.object_list.pack(fill="x")
        self.object_list.bind("<<ListboxSelect>>", self.on_object_select)
        ttk.Button(side, text="Delete object", command=self.delete_object).pack(fill="x", pady=2)

        ttk.Separator(side).pack(fill="x", pady=6)
        self.background_label = ttk.Label(side, text="")
        self.background_label.pack(anchor="w")
        bg_row = ttk.Frame(side)
        bg_row.pack(fill="x")
        self.background_var = tk.StringVar()
        ttk.Combobox(bg_row, textvariable=self.background_var, values=[str(c) for c in range(10)],
                     state="readonly", width=4).pack(side="left")
        ttk.Button(bg_row, text="Set background", command=self.set_background).pack(side="left", padx=4)

        ttk.Separator(side).pack(fill="x", pady=6)
        ttk.Label(side, text="Flag note").pack(anchor="w")
        self.note_var = tk.StringVar()
        ttk.Entry(side, textvariable=self.note_var, width=30).pack(fill="x")
        flag_row = ttk.Frame(side)
        flag_row.pack(fill="x", pady=2)
        ttk.Button(flag_row, text="Flag", command=self.flag).pack(side="left", expand=True, fill="x")
        ttk.Button(flag_row, text="Unflag", command=self.unflag).pack(side="left", expand=True, fill="x")

        ttk.Label(side, text="Flagged Grids (double-click to open)").pack(anchor="w", pady=(8, 0))
        self.flagged_list = tk.Listbox(side, height=8, width=28)
        self.flagged_list.pack(fill="both", expand=True)
        self.flagged_list.bind("<Double-Button-1>", self.on_flagged_open)

        self.status = ttk.Label(self.root, text="", relief="sunken", anchor="w", padding=4)
        self.status.pack(fill="x", side="bottom")

        self.root.bind("<Return>", lambda e: self.confirm_proposal())
        self.root.bind("<Escape>", lambda e: self.cancel_proposal())

    # ---- navigation ---------------------------------------------------------

    @property
    def dataset(self):
        return self.dataset_var.get()

    @property
    def queue(self):
        return self.queues[self.dataset]

    def switch_dataset(self):
        if self.dataset not in self.queues:
            self.set_status(f"Loading {self.dataset} tasks…")
            self.root.update_idletasks()
            self.queues[self.dataset] = build_queue(self.dataset)
            self.states[self.dataset] = [ref.saved_state() for ref in self.queues[self.dataset]]
        self.held_out.config(text="HELD OUT: ground truth for scoring only, never train on it"
                             if self.dataset == "evaluation" else "")
        self.open_index(self.first_not_done(0))

    def first_not_done(self, start):
        states = self.states[self.dataset]
        for offset in range(len(states)):
            i = (start + offset) % len(states)
            if states[i] in NOT_DONE:
                return i
        return start % len(states)

    def next_grid(self):
        self.open_index(self.first_not_done(self.index + 1))

    def prev_grid(self):
        self.open_index((self.index - 1) % len(self.queue))

    def jump_to_task(self):
        task = self.jump_var.get().strip().lower()
        for i, ref in enumerate(self.queue):
            if ref.task == task:
                self.open_index(i)
                return
        self.set_status(f"No task {task!r} in {self.dataset}")

    def on_flagged_open(self, _event):
        picked = self.flagged_list.curselection()
        if picked:
            self.open_index(self.flagged_indices[picked[0]])

    def open_index(self, i):
        self.index = i
        try:
            self.grid = self.queue[i].open()
        except Exception as e:
            self.grid = None
            self.set_status(f"Could not open {self.queue[i]}: {e}")
            return
        self.proposal = set()
        self.selected = None
        self.note_var.set(self.grid.note())
        self.set_status("")
        self.refresh()

    # ---- labeling actions ---------------------------------------------------

    def cell_at(self, event):
        size = self.cell_size()
        r, c = event.y // size, event.x // size
        if 0 <= r < self.grid.rows() and 0 <= c < self.grid.cols():
            return r, c
        return None

    def on_grid_click(self, event):
        if self.grid is None:
            return
        rc = self.cell_at(event)
        if rc is None:
            return
        r, c = rc
        i = r * self.grid.cols() + c
        owner = self.owner_of(i)
        if self.proposal:
            if owner is None and self.grid.cells()[i] != self.grid.background():
                self.proposal ^= {i}
            else:
                self.set_status("Only unclaimed, non-background cells can join the proposal")
        elif owner is not None:
            self.select_object(owner)
        else:
            self.proposal = set(self.grid.propose(r, c))
            if not self.proposal:
                self.set_status("That cell is Background")
        self.refresh()

    def confirm_proposal(self):
        if not self.proposal:
            return
        if self.mutate(lambda: self.grid.add_object(sorted(self.proposal))):
            self.proposal = set()

    def cancel_proposal(self):
        self.proposal = set()
        self.refresh()

    def on_object_select(self, _event):
        picked = self.object_list.curselection()
        self.selected = picked[0] if picked else None
        self.refresh(keep_list=True)

    def select_object(self, index):
        self.selected = index
        self.object_list.selection_clear(0, "end")
        self.object_list.selection_set(index)

    def delete_object(self):
        if self.selected is None:
            self.set_status("Select an Object to delete")
            return
        index = self.selected
        if self.mutate(lambda: self.grid.remove_object(index)):
            self.selected = None

    def set_background(self):
        if self.background_var.get() == "":
            return
        color = int(self.background_var.get())
        self.mutate(lambda: self.grid.set_background(color))

    def flag(self):
        self.mutate(lambda: self.grid.flag(self.note_var.get()))

    def unflag(self):
        if self.mutate(self.grid.unflag):
            self.note_var.set("")

    def mutate(self, action):
        """Apply a change through the core, save, and redraw. Core errors go to the status bar."""
        if self.grid is None:
            return False
        try:
            action()
            self.grid.save()
        except Exception as e:
            self.set_status(str(e))
            self.refresh()
            return False
        self.states[self.dataset][self.index] = self.grid.state()
        self.set_status("Saved")
        self.refresh()
        return True

    # ---- drawing ------------------------------------------------------------

    def owner_of(self, cell):
        for n, obj in enumerate(self.grid.objects()):
            if cell in obj:
                return n
        return None

    def cell_size(self):
        return max(4, min(32, MAX_CANVAS // max(self.grid.rows(), self.grid.cols())))

    def refresh(self, keep_list=False):
        self.update_header()
        self.update_flagged()
        if self.grid is None:
            return
        objects = self.grid.objects()
        if not keep_list:
            self.object_list.delete(0, "end")
            cells = self.grid.cells()
            for n, obj in enumerate(objects):
                colors = sorted({cells[i] for i in obj})
                self.object_list.insert("end", f"obj{n + 1:02}  {len(obj)} cells  colors {colors}")
            if self.selected is not None and self.selected < len(objects):
                self.object_list.selection_set(self.selected)
        self.draw_grid(objects)
        self.draw_reconstruction(objects)

    def update_header(self):
        states = self.states[self.dataset]
        done = sum(s == "complete" for s in states)
        flagged = sum(s == "flagged" for s in states)
        self.progress.config(text=f"{done}/{len(states)} complete, {flagged} flagged")
        if self.grid is None:
            return
        ref = self.queue[self.index]
        state = self.grid.state()
        check = "  ✓ reconstruction matches the Grid" if state == "complete" else ""
        self.title.config(text=f"{ref}    [{state}]    {self.index + 1}/{len(states)}{check}")
        self.background_label.config(
            text=f"Background: {self.grid.background()} ({self.grid.background_source()})")
        self.background_var.set(str(self.grid.background()))

    def update_flagged(self):
        states = self.states[self.dataset]
        self.flagged_indices = [i for i, s in enumerate(states) if s == "flagged"]
        self.flagged_list.delete(0, "end")
        for i in self.flagged_indices:
            self.flagged_list.insert("end", str(self.queue[i]))

    def draw_cells(self, canvas, cells):
        canvas.delete("all")
        size, cols = self.cell_size(), self.grid.cols()
        for i, color in enumerate(cells):
            r, c = divmod(i, cols)
            canvas.create_rectangle(c * size, r * size, (c + 1) * size, (r + 1) * size,
                                    fill=COLORS[color], outline="#222")

    def outline(self, canvas, cells, color, width):
        size, cols = self.cell_size(), self.grid.cols()
        for i in cells:
            r, c = divmod(i, cols)
            canvas.create_rectangle(c * size + 1, r * size + 1, (c + 1) * size - 1, (r + 1) * size - 1,
                                    outline=color, width=width)

    def draw_grid(self, objects):
        self.draw_cells(self.grid_canvas, self.grid.cells())
        if self.selected is not None and self.selected < len(objects):
            self.outline(self.grid_canvas, objects[self.selected], SELECTED_OUTLINE, 3)
        self.outline(self.grid_canvas, self.proposal, PROPOSAL_OUTLINE, 3)

    def draw_reconstruction(self, objects):
        canvas = self.recon_canvas
        self.draw_cells(canvas, self.grid.reconstruct())
        size, rows, cols = self.cell_size(), self.grid.rows(), self.grid.cols()
        owner = [None] * (rows * cols)
        for n, obj in enumerate(objects):
            for i in obj:
                owner[i] = n
        # Draw a border wherever an Object meets a different Object or the Background,
        # so touching Objects stay distinguishable.
        for i, o in enumerate(owner):
            if o is None:
                continue
            r, c = divmod(i, cols)
            x0, y0, x1, y1 = c * size, r * size, (c + 1) * size, (r + 1) * size
            if r == 0 or owner[i - cols] != o:
                canvas.create_line(x0, y0, x1, y0, fill=BORDER, width=2)
            if r == rows - 1 or owner[i + cols] != o:
                canvas.create_line(x0, y1, x1, y1, fill=BORDER, width=2)
            if c == 0 or owner[i - 1] != o:
                canvas.create_line(x0, y0, x0, y1, fill=BORDER, width=2)
            if c == cols - 1 or owner[i + 1] != o:
                canvas.create_line(x1, y0, x1, y1, fill=BORDER, width=2)
        for i in self.grid.unclaimed():
            r, c = divmod(i, cols)
            x0, y0, x1, y1 = c * size + 3, r * size + 3, (c + 1) * size - 3, (r + 1) * size - 3
            canvas.create_line(x0, y0, x1, y1, fill=UNCLAIMED_MARK, width=2)
            canvas.create_line(x0, y1, x1, y0, fill=UNCLAIMED_MARK, width=2)

    def set_status(self, text):
        self.status.config(text=text)


def main():
    root = tk.Tk()
    LabelingApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
