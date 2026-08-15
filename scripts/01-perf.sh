#!/system/bin/sh
# 性能调度 v2:性能最顶 + 耗电最轻(EAS/WALT 平衡调参)
# 存放: /data/adb/service.d/01-perf.sh,删除重启即还原

w() {
  [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

# ===== CPU 小核簇 policy0 =====
P0=/sys/devices/system/cpu/cpufreq/policy0
w "$P0/scaling_min_freq" 384000
w "$P0/walt/hispeed_load" 70
w "$P0/walt/hispeed_freq" 1286400
w "$P0/walt/up_rate_limit_us" 0
w "$P0/walt/down_rate_limit_us" 3000
w "$P0/walt/rtg_boost_freq" 1267200

# ===== CPU 大核簇 policy6 =====
P6=/sys/devices/system/cpu/cpufreq/policy6
w "$P6/scaling_min_freq" 768000
w "$P6/walt/hispeed_load" 70
w "$P6/walt/hispeed_freq" 1497600
w "$P6/walt/up_rate_limit_us" 0
w "$P6/walt/down_rate_limit_us" 4000
w "$P6/walt/rtg_boost_freq" 1382400

# ===== GPU =====
w /sys/class/kgsl/kgsl-3d0/min_clock_mhz 160
w /sys/class/kgsl/kgsl-3d0/idle_timer 200

# ===== I/O =====
for b in sda sdb sdc sdd sde sdf; do
  w "/sys/block/$b/queue/read_ahead_kb" 1024
  w "/sys/block/$b/queue/rq_affinity" 2
done

# ===== 内存/回写 =====
w /proc/sys/vm/dirty_ratio 20
w /proc/sys/vm/dirty_background_ratio 5
w /proc/sys/vm/dirty_expire_centisecs 3000
w /proc/sys/vm/dirty_writeback_centisecs 500

w /proc/sys/kernel/random/read_wakeup_threshold 64
w /proc/sys/kernel/random/write_wakeup_threshold 128
