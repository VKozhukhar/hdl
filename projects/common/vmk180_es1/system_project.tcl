source ../../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project template_vmk180_es1
adi_project_files template_vmk180_es1 [list \
  "$ad_hdl_dir/library/common/ad_iobuf.v" \
   "$ad_hdl_dir/projects/common/vmk180_es1/vmk180_es1_system_constr.xdc" \
  "system_constr.xdc"\
  "system_top.v" ]

adi_project_run template_vmk180_es1
