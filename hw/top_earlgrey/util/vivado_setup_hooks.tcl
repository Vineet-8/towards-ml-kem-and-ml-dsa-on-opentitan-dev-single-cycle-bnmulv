# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
# Modified for low-memory synthesis on 16 GB workstation.

set workroot [pwd]

# ── Hooks (unchanged from original) ─────────────────────────────
set_property STEPS.SYNTH_DESIGN.TCL.PRE "${workroot}/vivado_hook_synth_design_pre.tcl" [get_runs synth_1]
set_property STEPS.INIT_DESIGN.TCL.POST "${workroot}/vivado_hook_init_design_post.tcl" [get_runs impl_1]
set_property STEPS.OPT_DESIGN.TCL.POST "${workroot}/vivado_hook_opt_design_post.tcl" [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.TCL.POST "${workroot}/vivado_hook_write_bitstream_pre.tcl" [get_runs impl_1]

# ── Strategy first (sets defaults for all ARGS below) ───────────
# Use the least memory-intensive built-in strategies
set_property strategy Flow_RuntimeOptimized [get_runs synth_1]
set_property strategy Flow_RuntimeOptimized [get_runs impl_1]

# ── Custom ARGS AFTER strategy (override strategy defaults) ─────
# These are the memory-saving overrides
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE RuntimeOptimized [get_runs synth_1]

# ── Global thread limit (single-threaded to reduce peak RAM) ────
set_param general.maxThreads 1
set_param synth.maxThreads 1
