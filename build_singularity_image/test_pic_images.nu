#!/usr/bin/env nu

source /home/yuhanjin/scripts/build_singularity_image/pic_build_common.nu

# Run smoke tests for PIC program images.
def main [
  program: string = "all" # all, epoch1d, epoch2d, epoch3d, smilei or smilei_spin
  --dry-run              # print commands only
] {
  # -------------------------------------------------------------------------
  # 1. Target Configuration
  # -------------------------------------------------------------------------

  let test_configs = {
    epoch1d: {
      image: "/home/yuhanjin/Code_Program/Epoch/Epoch1d/epoch_epoch1d.sif"
      input_dir: "pic_test_inputs/epoch1d"
      command: "printf '.\n' | epoch1d"
    }
    epoch2d: {
      image: "/home/yuhanjin/Code_Program/Epoch/Epoch2d/epoch_epoch2d.sif"
      input_dir: "pic_test_inputs/epoch2d"
      command: "printf '.\n' | epoch2d"
    }
    epoch3d: {
      image: "/home/yuhanjin/Code_Program/Epoch/Epoch3d/epoch_epoch3d.sif"
      input_dir: "pic_test_inputs/epoch3d"
      command: "printf '.\n' | epoch3d"
    }
    smilei: {
      image: "/home/yuhanjin/Code_Program/Smilei/Smilei_v5_1/Smilei_v5_1.sif"
      input_dir: "pic_test_inputs/smilei"
      command: "smilei smoke.py"
    }
    smilei_spin: {
      image: "/home/yuhanjin/Code_Program/Smilei_Spin/Smilei_Spin_v2_2_3D_interpolator/Smilei_Spin_v2_2_3D_interpolator.sif"
      input_dir: "pic_test_inputs/smilei_spin"
      command: "smilei smoke.py"
    }
  }

  # -------------------------------------------------------------------------
  # 2. Target Selection
  # -------------------------------------------------------------------------

  let targets = if $program == "all" {
    $test_configs | columns
  } else if $program in ($test_configs | columns) {
    [$program]
  } else {
    error make {msg: $"Unknown program: ($program)"}
  }

  let script_dir = ($env.CURRENT_FILE | path dirname | path expand)
  let engine = (select-engine)

  # -------------------------------------------------------------------------
  # 3. Run Tests
  # -------------------------------------------------------------------------

  for target in $targets {
    let cfg = ($test_configs | get $target)
    let image = ($cfg.image | path expand)
    let input_dir = ($script_dir | path join $cfg.input_dir)
    let run_dir = if $dry_run {
      $"/tmp/pic_test_($target)"
    } else {
      mktemp -d
    }

    check-path $image $"($target) image"
    check-path $input_dir $"($target) input directory"

    print ""
    print $"=== Testing ($target) ==="
    print $"Image:   ($image)"
    print $"Input:   ($input_dir)"
    print $"Run dir: ($run_dir)"

    let shell_cmd = $"cd /work && ($cfg.command)"
    print $"Command: ($engine) exec --bind ($run_dir):/work ($image) sh -lc '($shell_cmd)'"

    if not $dry_run {
      cp -r (($input_dir | path join "*") | into glob) $run_dir
      ^$engine exec --bind $"($run_dir):/work" $image sh -lc $shell_cmd
    }
  }
}
