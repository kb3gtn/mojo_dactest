
# PlanAhead Launch Script for Post-Synthesis pin planning, created by Project Navigator

create_project -name mojo_dactest -dir "/home/kb3gtn/sandbox/mojo_dactest/ISE/mojo_dactest/work/planAhead_run_1" -part xc6slx9tqg144-2
set_property design_mode GateLvl [get_property srcset [current_run -impl]]
set_property edif_top_file "/home/kb3gtn/sandbox/mojo_dactest/ISE/mojo_dactest/work/mojo_top.ngc" [ get_property srcset [ current_run ] ]
add_files -norecurse { {/home/kb3gtn/sandbox/mojo_dactest/ISE/mojo_dactest/work} }
set_param project.pinAheadLayout  yes
set_property target_constrs_file "/home/kb3gtn/sandbox/mojo_dactest/src/mojo.ucf" [current_fileset -constrset]
add_files [list {/home/kb3gtn/sandbox/mojo_dactest/src/mojo.ucf}] -fileset [get_property constrset [current_run]]
link_design
