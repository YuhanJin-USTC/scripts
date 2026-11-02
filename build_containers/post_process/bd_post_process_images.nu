#!/usr/bin/env nu

source ../build_common.nu

# Build post-processing images.
def main [
  program: string # epoch
  --dry-run       # print config only
] {
  # Target configuration.
  let target_configs = {
    epoch: {
      work_dir: "/home/yuhanjin/Code_Program/Post_Process/Epoch"
      image_name: "epoch_jupyter.sif"
      template_name: "epoch_jupyter.def.tmpl"
      docker_image: "python:3.12-slim-bookworm"
      pip_index: "https://pypi.tuna.tsinghua.edu.cn/simple"
      apt_packages: "ca-certificates fonts-dejavu-core libgomp1"
      pip_packages: "jupyterlab==4.6.2 ipykernel==7.3.0 numpy==2.5.1 scipy==1.18.0 matplotlib==3.11.1 h5py==3.16.0 pandas==3.0.5 sdfr==1.4.13"
    }
  }

  # Resolve paths before any external build command.
  if $program not-in ($target_configs | columns) {
    error make {msg: $"Unknown program: ($program)."}
  }

  let script_dir = ($env.CURRENT_FILE | path dirname | path expand)
  let def_dir = ($script_dir | path join "post_process_defs")
  let cfg = ($target_configs | get $program)
  let work_dir = ($cfg.work_dir | path expand)
  let image_path = ($work_dir | path join $cfg.image_name)
  let template_path = ($def_dir | path join $cfg.template_name)
  let engine = (select-engine)

  check-path $work_dir "work directory"
  check-path $template_path "definition template"

  title "Post-processing image build"
  field "Target" $program
  field "Mode" (if $dry_run { "dry-run" } else { "run" })
  field "Rule" "render template then build image with --force"
  field "Work dir" $work_dir
  field "Template" $template_path
  field "Image" $image_path
  field "Engine" $engine
  field "Overwrite" "true"
  if $dry_run {
    status "DRY-RUN" "No image will be built."
    status "OK" "Dry run completed."
    return
  }

  # Render the definition in a temporary build directory.
  let start_dir = (pwd)
  let temp_dir = (mktemp -d)
  let temp_def = ($temp_dir | path join ($cfg.template_name | str replace ".tmpl" ""))

  try {
    field "Temporary dir" $temp_dir
    render-template $template_path $temp_def (post-process-template-values $cfg)
    ensure-rendered $temp_def

    cd $temp_dir
    step $"Building image: ($image_path)"
    sudo -E $engine build --force $image_path ($temp_def | path basename)
    if $env.LAST_EXIT_CODE != 0 {
      error make {msg: $"Image build failed with code ($env.LAST_EXIT_CODE)."}
    }
  } catch {|err|
    cd $start_dir
    clean-temp-dir $temp_dir
    error make {msg: (sentence $"Build failed: ($err.msg)")}
  }

  cd $start_dir
  clean-temp-dir $temp_dir

  status "OK" $"Build completed. Image file: ($image_path)"
}

def post-process-template-values [cfg: record] {
  {
    DOCKER_IMAGE: $cfg.docker_image
    APT_PACKAGES: $cfg.apt_packages
    PIP_INDEX: $cfg.pip_index
    PIP_PACKAGES: $cfg.pip_packages
  }
}
