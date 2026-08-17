#!/system/bin/sh
# 02-auto-profile.sh - 前台应用感知 自动切换性能档位
# 切换规则: 游戏→gaming, 熄屏→battery, 其他→balance

PROFILE_DIR=/data/adb/perf_profile
LAST_PROFILE=""

GAMES="com.miHoYo.Yuanshen com.miHoYo.hkrpg com.miHoYo.zzzzz com.tencent.tmgp.sgame com.tencent.tmgp.pubgmhd com.tencent.tmgp.cf com.netease.g93na com.netease.dwrg com.activision.callofduty.shooter com.supercell.clashofclans com.supercell.clashroyale com.garena.game.codm com.tencent.lolm com.mobile.legends com.netease.party com.netease.mrzhna com.kurogame.wutheringwaves.global com.kurogame.gplay.punishing com.hypergryph.arknights com.YoStarJP.Arknights com.lilithgame.hgame com.papegames.infinitynikki com.HoYoverse.Nap com.tencent.tmgp.speedmobile com.netease.x19 com.mojang.minecraftpe com.netease.huolianyx com.tencent.tmgp.cod"

is_game() {
  local pkg="$1"
  for g in $GAMES; do
    [ "$pkg" = "$g" ] && return 0
  done
  return 1
}

get_foreground() {
  dumpsys activity activities 2>/dev/null | grep "mFocusedApp" | head -1 | sed 's/.*{[^ ]* [^ ]* \([^\/}]*\).*/\1/' | tr -d ' '
}

get_screen_state() {
  dumpsys display 2>/dev/null | grep -q "mScreenState=ON" && echo 1 || echo 0
}

apply_profile() {
  [ "$1" = "$LAST_PROFILE" ] && return
  sh /data/adb/service.d/01-perf.sh "$1"
  echo "$1" > "$PROFILE_DIR"
  LAST_PROFILE="$1"
  echo "$(date) → $1" >> /data/adb/perf_profile.log
}

while true; do
  SCREEN=$(get_screen_state)

  if [ "$SCREEN" = "0" ]; then
    apply_profile battery
  else
    FG=$(get_foreground)
    if [ -n "$FG" ] && is_game "$FG"; then
      apply_profile gaming
    else
      apply_profile balance
    fi
  fi

  sleep 3
done
