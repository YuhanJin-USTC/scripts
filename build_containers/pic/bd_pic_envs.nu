#!/usr/bin/env nu

source ../build_common.nu

# Build PIC environment images.
def main [
  program: string # epoch, smilei or smilei_spin
  --dry-run       # print config only
] {
  # Target configuration.
  let target_configs = {
    epoch: {
      work_dir: "/home/yuhanjin/Code_Program/Env/Epoch"
      image_name: "epoch_env.sif"
      template_name: "epoch_env.def.tmpl"
      docker_image: "ubuntu:20.04"
      apt_packages: "build-essential gfortran make mpich libmpich-dev wget openssh-client zlib1g-dev"
    }
    smilei: {
      work_dir: "/home/yuhanjin/Code_Program/Env/Smilei"
      image_name: "smilei_env.sif"
      template_name: "smilei_env.def.tmpl"
      docker_image: "ubuntu:20.04"
      apt_packages: "build-essential git make cmake gcc mpich libmpich-dev wget openssh-client zlib1g-dev python3 python3-pip"
      hdf5_version: "1.14.5"
      hdf5_prefix: "/opt/.local/program/hdf5"
      hdf5_source_dir: "/opt/.local/program/source_code"
      jobs: "8"
      pip_index: "https://pypi.tuna.tsinghua.edu.cn/simple"
    }
    smilei_spin: {
      work_dir: "/home/yuhanjin/Code_Program/Env/Smilei_Spin"
      image_name: "smilei_spin_env.sif"
      template_name: "smilei_env.def.tmpl"
      docker_image: "ubuntu:20.04"
      apt_packages: "build-essential git make cmake gcc mpich libmpich-dev wget openssh-client zlib1g-dev python3 python3-pip"
      hdf5_version: "1.14.5"
      hdf5_prefix: "/opt/.local/program/hdf5"
      hdf5_source_dir: "/opt/.local/program/source_code"
      jobs: "8"
      pip_index: "https://pypi.tuna.tsinghua.edu.cn/simple"
    }
  }

  # Resolve paths before any external build command.
  if $program not-in ($target_configs | columns) {
    error make {msg: $"Unknown program: ($program)."}
  }

  let script_dir = ($env.CURRENT_FILE | path dirname | path expand)
  let def_dir = ($script_dir | path join "pic_env_defs")
  let cfg = ($target_configs | get $program)
  let work_dir = ($cfg.work_dir | path expand)
  let image_path = ($work_dir | path join $cfg.image_name)
  let template_path = ($def_dir | path join $cfg.template_name)
  let engine = (select-engine)

  check-path $work_dir "work directory"
  check-path $template_path "definition template"

  title "PIC environment image build"
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
    render-template $template_path $temp_def (env-template-values $cfg)
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

def env-template-values [cfg: record] {
  {
    DOCKER_IMAGE: $cfg.docker_image
    APT_PACKAGES: $cfg.apt_packages
    AUTHOR: ($cfg.author? | default "")
    DESCRIPTION: ($cfg.description? | default "")
    HDF5_VERSION: ($cfg.hdf5_version? | default "")
    HDF5_PREFIX: ($cfg.hdf5_prefix? | default "")
    HDF5_SOURCE_DIR: ($cfg.hdf5_source_dir? | default "")
    JOBS: ($cfg.jobs? | default "")
    PIP_INDEX: ($cfg.pip_index? | default "")
  }
}
