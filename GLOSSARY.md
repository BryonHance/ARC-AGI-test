# ARC Object Labeling

A human labels the objects in ARC-AGI grids, and the resulting labels become training data that teaches a DNN to perceive objects the way people do.

## Language

**Dataset**:
One of the two ARC-AGI-1 task collections, *training* or *evaluation*. Models learn only from training Decompositions, and evaluation Decompositions are the ground truth for scoring how well a model perceives Objects.
_Avoid_: Split, set, folder

**Split**:
Whether a pair inside a Task is a *train* pair or a *test* pair.
_Avoid_: Dataset, set

**Task**:
One ARC-AGI puzzle, made up of train pairs and test pairs, where each pair has an input Grid and an output Grid.
_Avoid_: Example, puzzle, file

**Grid**:
One input or output of one pair in a Task, and the unit that gets decomposed into Objects. It is identified by Dataset, Task, Split, pair index, and side (input/output).
_Avoid_: Image, picture, example, board

**Object**:
A group of cells that a human perceives as one thing. It is usually a connected group of cells in one or a few colors. Objects come in any size and may touch one another. Each cell belongs to at most one Object, so where Objects appear to overlap, the cell goes to the one on top.
_Avoid_: Component, blob, shape, segment

**Background**:
The color that appears on the most cells of a grid, with the lowest color number winning a tie, unless the labeler picks a different color for that grid. Background cells do not belong to any Object.
_Avoid_: Empty, blank, black

**Decomposition**:
The full set of Objects a labeler has identified in one Grid. A Decomposition is **unlabeled** until work starts. It is **in progress** once it has at least one Object but is not yet complete. It is **complete** when every non-Background cell belongs to exactly one Object, which can mean zero Objects. It is **flagged** when the Labeler sets it aside as ambiguous, with a note.
_Avoid_: Segmentation, labeling, parse

**Labeler**:
The human who decides what the Objects in a Grid are.
_Avoid_: User, annotator, operator

**Object Label**:
A human's judgment that a particular set of cells in a grid forms one Object. It is the ground truth the DNN learns from.
_Avoid_: Annotation, mask, extraction
