# Evaluation Decompositions are labeled as held-out ground truth

The repo normally treats `data/evaluation/` as off-limits during development. The labeling app deliberately decomposes evaluation Grids anyway, because those Decompositions are the ground truth for scoring how well a model perceives Objects. Models are trained only on training Decompositions. Evaluation labels are stored separately under `objects/evaluation/` and tagged with their Dataset, so a training pipeline can exclude them with a single path filter.
