let debug_name = ref false

let debug_node = ref false

let merge_branches = ref true

let analyze_possible_cell_data_shapes = ref true

let use_most_general_cell_data_shape = ref false

let default_translate_style : Translate_style.t = `Mix0

let translate_style : Translate_style.t ref = ref default_translate_style

let pid_cell_name = "pid"

let cell_name_prefix = "tgc_"

let entry_point_pred_prefix = "TgEntry"

let wildcard_var_prefix = "_tgany"

let tamarin_output_underscore_prefix_replacement = "u_"

let graph_vertex_label_prefix = "tgk"

let auto_gen_name_prefix = "tgsys"

let pcell_freed_apred_name = "PcellFreed"

let pcell_read_apred_name = "PcellRead"

let pcell_ptr_prefix = "pcellptr"

let pcell_restriction_name = "pcell_restriction"

let builtin_functions = [
  "h";
  "senc";
  "sdec";
  "aenc";
  "adec";
  "pk";
  "sign";
  "verify";
  "pair";
  "fst";
  "snd";
]

let builtin_constants = [
  "true";
  "zero";
]

let state_pred_prefix = "St"

let reserved_names =
  [
    "In";
    "Out";
    "Fr";
    "KU";
    "K";
    "undef";
    "St";
    "StF";
    "StB";
    "Cell";
    "Pcell";
    "let";
    "in";
    "rule";
    "T";
    "F";
    pcell_freed_apred_name;
    pcell_read_apred_name;
    pcell_restriction_name;
  ]

let reserved_prefixes =
  [
    cell_name_prefix;
    entry_point_pred_prefix;
    wildcard_var_prefix;
    tamarin_output_underscore_prefix_replacement;
    graph_vertex_label_prefix;
    auto_gen_name_prefix;
    pcell_ptr_prefix;
  ]

let file_extension = ".tg"
