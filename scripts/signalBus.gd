extends Node

signal sketch_solved()

# Emitted whenever a body's set of selected edges changes. `indices` is the
# current selection (edge indices into OcctBody.get_edges()).
signal edge_selection_changed(body: Node, indices: Array)
