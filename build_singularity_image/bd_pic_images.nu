#!/usr/bin/env nu

source /home/yuhanjin/scripts/build_singularity_image/pic_build_common.nu

# Build PIC program images from local source.
def main [
  program: string # epoch1d, epoch2d, epoch3d, smilei or smilei_spin
  --dry-run       # print config only
] {
  # -------------------------------------------------------------------------
  # 1. Target Configuration
  # -------------------------------------------------------------------------

  let target_configs = {
    epoch1d: {
      source_dir: "/home/yuhanjin/Source_Code/Epoch_2025/epoch"
      env_image: "/home/yuhanjin/Code_Program/Env/Epoch/epoch_env.sif"
      work_dir: "/home/yuhanjin/Code_Program/Epoch/Epoch1d"
      image_name: "epoch_epoch1d.sif"
      template_name: "epoch.def.tmpl"
      build_dir: "/opt/.local/program/epoch_build"
      tar_name: "generic_source.tar.gz"
      tar_target: "/opt/.local/program/source.tar.gz"
      jobs: 8
      exec_name: "epoch1d"
      epoch_dim: "epoch1d"
      epoch_compiler: "gfortran"
      clean_items: "epoch2d epoch3d doc .git .github .gitignore License README.md"
    }
    epoch2d: {
      source_dir: "/home/yuhanjin/Source_Code/Epoch_2025/epoch"
      env_image: "/home/yuhanjin/Code_Program/Env/Epoch/epoch_env.sif"
      work_dir: "/home/yuhanjin/Code_Program/Epoch/Epoch2d"
      image_name: "epoch_epoch2d.sif"
      template_name: "epoch.def.tmpl"
      build_dir: "/opt/.local/program/epoch_build"
      tar_name: "generic_source.tar.gz"
      tar_target: "/opt/.local/program/source.tar.gz"
      jobs: 8
      exec_name: "epoch2d"
      epoch_dim: "epoch2d"
      epoch_compiler: "gfortran"
      clean_items: "epoch1d epoch3d doc .git .github .gitignore License README.md"
    }
    epoch3d: {
      source_dir: "/home/yuhanjin/Source_Code/Epoch_2025/epoch"
      env_image: "/home/yuhanjin/Code_Program/Env/Epoch/epoch_env.sif"
      work_dir: "/home/yuhanjin/Code_Program/Epoch/Epoch3d"
      image_name: "epoch_epoch3d.sif"
      template_name: "epoch.def.tmpl"
      build_dir: "/opt/.local/program/epoch_build"
      tar_name: "generic_source.tar.gz"
      tar_target: "/opt/.local/program/source.tar.gz"
      jobs: 8
      exec_name: "epoch3d"
      epoch_dim: "epoch3d"
      epoch_compiler: "gfortran"
      clean_items: "epoch1d epoch2d doc .git .github .gitignore License README.md"
    }
    smilei: {
      source_dir: "/home/yuhanjin/Source_Code/Smilei_2025/Smilei"
      env_image: "/home/yuhanjin/Code_Program/Env/Smilei/smilei_env.sif"
      work_dir: "/home/yuhanjin/Code_Program/Smilei/Smilei_v5_1"
      image_name: "Smilei_v5_1.sif"
      template_name: "smilei.def.tmpl"
      build_dir: "/opt/.local/program/smilei_build"
      tar_name: "generic_source.tar.gz"
      tar_target: "/opt/.local/program/source.tar.gz"
      hdf5_root: "/opt/.local/program/hdf5"
      jobs: 8
      exec_name: "smilei"
      clean_items: "src benchmarks validation doc tools scripts makefile CMakeLists.txt .git .github .gitignore .gitlab-ci.yml License README.md"
    }
    smilei_spin: {
      source_dir: "/home/yuhanjin/Source_Code/Smilei_Spin_2025/Smilei_Spin"
      env_image: "/home/yuhanjin/Code_Program/Env/Smilei_Spin/smilei_spin_env.sif"
      work_dir: "/home/yuhanjin/Code_Program/Smilei_Spin/Smilei_Spin_v2_2_3D_interpolator"
      image_name: "Smilei_Spin_v2_2_3D_interpolator.sif"
      template_name: "smilei_spin.def.tmpl"
      build_dir: "/opt/.local/program/smilei_build"
      tar_name: "generic_source.tar.gz"
      tar_target: "/opt/.local/program/source.tar.gz"
      hdf5_root: "/opt/.local/program/hdf5"
      jobs: 8
      exec_name: "smilei"
      clean_items: "src benchmarks validation doc tools scripts makefile CMakeLists.txt .git .github .gitignore .gitlab-ci.yml License README.md"
    }
  }

  # -------------------------------------------------------------------------
  # 2. Path Resolution & Validation
  # -------------------------------------------------------------------------

  if $program not-in ($target_configs | columns) {
    error make {msg: $"Unknown program: ($program)"}
  }

  let script_dir = ($env.CURRENT_FILE | path dirname | path expand)
  let def_dir = ($script_dir | path join "pic_defs")
  let cfg = ($target_configs | get $program)
  let source_dir = ($cfg.source_dir | path expand)
  let env_image = ($cfg.env_image | path expand)
  let work_dir = ($cfg.work_dir | path expand)
  let image_path = ($work_dir | path join $cfg.image_name)
  let template_path = ($def_dir | path join $cfg.template_name)
  let engine = (select-engine)

  check-path $source_dir "source directory"
  check-path $work_dir "work directory"
  check-path $env_image "environment image"
  check-path $template_path "definition template"

  print $"Program:      ($program)"
  print $"Source:       ($source_dir)"
  print $"Env image:    ($env_image)"
  print $"Work dir:     ($work_dir)"
  print $"Template:     ($template_path)"
  print $"Image:        ($image_path)"
  print $"Engine:       ($engine)"
  print "Overwrite:    true"

  if $dry_run {
    print "Dry run complete."
    return
  }

  # -------------------------------------------------------------------------
  # 3. Build
  # -------------------------------------------------------------------------

  let start_dir = (pwd)
  let temp_dir = (mktemp -d)
  let temp_def = ($temp_dir | path join ($cfg.template_name | str replace ".tmpl" ""))

  try {
    let tar_path = ($temp_dir | path join $cfg.tar_name)
    let parent_dir = ($source_dir | path dirname)
    let base_name = ($source_dir | path basename)

    print $"Temporary dir: ($temp_dir)"
    print "Archiving source code..."
    tar -czf $tar_path -C $parent_dir $base_name

    render-template $template_path $temp_def (image-template-values $cfg $env_image)
    ensure-rendered $temp_def

    cd $temp_dir
    print $"Building image: ($image_path)"
    sudo -E $engine build --force $image_path ($temp_def | path basename)
  } catch {|err|
    cd $start_dir
    clean-temp-dir $temp_dir
    error make {msg: $"Build failed: ($err.msg)"}
  }

  cd $start_dir
  clean-temp-dir $temp_dir

  print ""
  print "#############################################"
  print "  Build accomplished."
  print $"  Image file: ($image_path)"
  print $"  Run test:   ($engine) exec ($image_path) ($cfg.exec_name)"
  print "#############################################"
}

def image-template-values [cfg: record env_image: string] {
  {
    ENV_IMAGE: $env_image
    TAR_NAME: $cfg.tar_name
    TAR_TARGET: $cfg.tar_target
    BUILD_DIR: $cfg.build_dir
    HDF5_ROOT: ($cfg.hdf5_root? | default "")
    JOBS: ($cfg.jobs | into string)
    EXEC_NAME: $cfg.exec_name
    CLEAN_ITEMS: $cfg.clean_items
    EPOCH_COMPILER: ($cfg.epoch_compiler? | default "")
    EPOCH_DIM: ($cfg.epoch_dim? | default "")
  }
}
