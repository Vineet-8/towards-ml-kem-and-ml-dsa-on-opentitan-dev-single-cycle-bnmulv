# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set workroot [pwd]

# ── Strategy first (sets defaults for all ARGS below) ───────────
# Setting a run's strategy resets all of its STEPS.* properties,
# including TCL.PRE/TCL.POST hooks, so hooks must be set after this.
set_property strategy Flow_RuntimeOptimized [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# ── Hooks ──────────────────────────────────────────────────────
set_property STEPS.SYNTH_DESIGN.TCL.PRE "${workroot}/vivado_hook_synth_design_pre.tcl" [get_runs synth_1]
set_property STEPS.INIT_DESIGN.TCL.POST "${workroot}/vivado_hook_init_design_post.tcl" [get_runs impl_1]
set_property STEPS.OPT_DESIGN.TCL.POST "${workroot}/vivado_hook_opt_design_post.tcl" [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.TCL.PRE "${workroot}/vivado_hook_write_bitstream_pre.tcl" [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
