# 手机维修进度记录(RMX5200 + ossi GSI Android 16)

## 设备状态
- realme RMX5200(SM8850 / Adreno 840),BL 已解锁
- 系统:oplus "ossi" GSI(phh 系,EROFS),已装 Magisk 30.7(root)
- TWRP 3.7.1 已刷入 recovery
- 备份:backup\partitions-20260814-153121\(含 18GB super.img,官方系统完整分区)

## 已修复
1. 相机 Aperture 闪退 + 微信闪退(同一病根):
   /odm/framework/androidx.camera.extensions.impl.fake.jar 含老版 Kotlin 污染类加载
   → post-fs-data.d/fixfake.sh 用空 jar bind mount 覆盖
2. 微信风控自杀(System.exit):改机型绕过
   → post-fs-data.d/spoof.sh:ro.product.model/device/name 等改为 RMX5200/realme
3. 性能调度 v3:service.d/01-perf.sh(WALT 调参 + GPU + IO + VM) + 02-auto-profile.sh(自动档位)
4. Doze 收紧:settings put global device_idle_constants
5. 微信/支付宝已加 Magisk DenyList
6. **IMS 全链路打通(8/15)**:官方 IMS 应用移植 + SELinux 策略注入 → 已注册(SMS/VoLTE 启用),详见 B2/B3
7. **动画掉帧修复(8/16)**:
   - 病根:屏幕是 144Hz 面板(1440x3136,支持 60/90/120/144),但 GSI 把 peak/min_refresh_rate 锁死 60 → 全程 60Hz
   - 修复:settings put system peak_refresh_rate 144 + min_refresh_rate 120(settings db,持久)
   - 验证:SystemUI 掉帧 2.21%,桌面 1.76%(<5% 属旗舰正常);GPU 负载仅 10%
   - 渲染器:用户自行设 debug.hwui.renderer=skiavk,重启 SystemUI/桌面进程后已生效(Pipeline=Skia (Vulkan))
   - 刷新率最终配置:peak=144 / min=60(待机 60,滑动升 144,已生效)
8. **相机→多任务卡顿修复(8/16)**:GCam 打开时主动把屏幕锁 60Hz,切多任务瞬间 60→120 模式切换撞动画 → min_refresh_rate 提到 120 解决
9. **续航项(8/16)**:adaptive_battery_management_enabled=1;Doze 参数保持收紧版
10. **指纹(FOD)完全修复(8/17)**:
    - 病根:HIDL 旧路径没对接(new path 有 AIDL),framework 把传感器类型错报为 POWER_BUTTON(1)
    - 修复:framework.jar smali 修改(FingerprintSensorPropertiesInternal 构造函数):
      - sensorType 强制 = 3(UNDER_DISPLAY_ULTRASONIC)
      - sensorLocations 强制 = (720, 2352, r150)(屏幕底部 75% 区域)
      - halControlsIllumination + halHandlesDisplayTouches 强制 true(HAL 管理灯光/触控,解锁/指纹录入/支付全部正常)
    - 模块:oplusfix(framework.jar + services.jar + sensor_config.json + display XML + post-fs-data.sh bind mount)
11. **锁屏指纹图标修复(8/17)**:
    - 病根:EvoX 默认 UDFPS 图标渲染为白色矩形块(device_entry_icon_view 背景色错误)
    - 修复:settings put system udfps_icon 1(启用 Evolution UDFPS icons 包中的自定义指纹图标)
12. **自动亮度修复(8/17)**:
    - 病根链条(全部解决):
      1. framework-res 的 config_automatic_brightness_available=false → services.jar patch 强制 isAutoBrightnessAvailable=true
      2. vendor displayconfig 文件与当前屏不匹配(缺 display_id_4630947180293509523.xml) → 模块提供匹配文件
      3. vendor 配置缺 autoBrightness luxToBrightnessMapping → 补 12 档 lux→brightness 映射(0.0→0.01,10→0.05,50→0.15,100→0.25,200→0.38,400→0.52,800→0.65,1500→0.78,3000→0.88,5000→0.94,8000→0.97,12000→1.00)
      4. 传感器:qti.sensor.high_pwm_rgb(前置传感器,正确反映环境光)
    - 验证:mAmbientLux=1030,adjustedBrightness=0.69,亮度 177/255(69%),adjustment=0.0
13. **微信/QQ/媒体存储崩溃修复(8/17)**:
    - 病根:oplusfix 重建的 framework.jar 丢失了 res/debian.mime.types 资源 → DefaultMimeMapFactory 资源为 null → NPE → 微信/QQ 媒体存储每 2 秒循环崩溃
    - 修复:恢复原版 dex + 只改资源的 framework.jar(保留所有 res 资源)
14. **锁屏指纹图标白色圆形修复(8/17)**:
    - 病根:EvoX 默认指纹图标渲染外部圆形 → 系统预装 → 指纹区域渲染异常(白色圆形)
    - 修复:从官方 EvolutionX ROM 提取 UdfpsIcons.apk + UdfpsAnimations.apk 安装
15. **SystemUI 帧率优化(8/17)**:
    - gfxinfo 帧统计对比:桌面 2.5% 掉帧(正常) vs SystemUI 16.1%(偏高)
    - 根因:GPU min_clock 低 + idle_timer 短 → 频繁降频
    - 修复:GPU min_clock 342MHz + idle_timer 800(掉帧 29.4% → 4.57%)
    - balance 档:up_rate_limit 0 + hispeed_load 60 + min_freq 998M/1.27G + GPU min 342MHz

## 当前模块清单
- **stockims**:官方 IMS 应用移植 + SELinux 注入 + 缺失类桩
- **audiopatch**:通话音频 HAL 补丁(libaudiocorehal.qti.so)
- **ctreg**:CT IMS 短信自动注册发送器
- **oplusfix**:指纹/亮度/显示/传感器配置 bind mount 模块
- **perf**:性能调度 + 自动档位脚本(01-perf.sh + 02-auto-profile.sh)

## 未解决(下次继续)
### A. 蓝牙 A2DP 无声(HFP 正常,媒体没声)
- 已排除:媒体音频开关、SBC 编码、A2DP offload 禁用
- 结论:PandoraEx 栈与 sysbta HAL 会话对不上,需 GSI 重建

### B. IMS 呼叫失败(CallFailCause 1502/553)
- 已修复:3 个缺失方法桩(getIntArray/isGlassesFree3DVideoSupported/isVisualizedVoiceSupported)
- 剩余:接通无声音 → 已修复(音频 HAL 补丁)
- 剩余:MT 短信不达 → CT SMSC 需要 Oplus CT IMS SMS 自动注册流程(CTReg 已实现但未完全打通)

### C. 电梯信号差(和 B 同根:运营商 MBN 配置缺失)
- 修好 B 大概率一并解决;临时方案 LTE 优先

### D. 相机 2 亿像素(可行性 <20%)
- 验证:Camera2 元数据是否暴露全像素流

### E. WiFi 热点 WPA3 缺失
- vendor hostapd 不上报能力,框架收不到 WPA3-SAE 特性
- 结论:热点继续用 WPA2+强密码即可,优先级排最后

## smali 踩坑经验
- String.concat 是 invoke-virtual,不是 invoke-static
- 无效行号(如 369b,759b)会导致 smali 编译失败
- 重复标签(:goto_0)导致构建失败
- adjustLightSensorRate 的 p0 覆写 bug:原代码在 registerListener 调用中把 p0(this/controller)覆盖为 mHandler;任何后续访问 controller 字段的代码都会访问 Handler 对象 → 类型错误 → 开机循环
- AutomaticBrightnessController$2.smali(内部类 SensorEventListener)直接修改 outer class 字段(iget/iput)会导致 DEX 验证失败 → 开机循环;需要完全不同的架构(如单独的 listener 类)

---
## 2026-08-18 会话3 — MT 短信深挖: 断链终于指向 modem

### 旧理论推翻
- imsRadioTech 实际=14(LTE), 映射正确 → "tech=1 误读"理论作废
- RILJ 的 IRadioIms 缺失原厂同样存在(OPPO 从不用 AOSP IRadioIms) → 无关

### 新证据链(全部设备侧验证)
- MT 来电 IMS 正常到达 → 网络能路由 SIP 到本机注册
- MO 短信端到端送达(对方手机收到) → 电信 SMSC 接受本机 SIP MESSAGE
- modem ServiceStatus: type=5(SMS) status=2(ENABLED)
- 但 ImsRadioIndicationAidl.onIncomingSms() 零命中 → QMI 层从未收到 MT 短信
- 换机/原厂均能收 → 网络侧排除, 问题 100% 在 GSI 的 modem 行为差异

### ctreg 两处致命 bug 修复
1. IMSI 一直为空: getSubscriberId 被权限拒绝, catch 吞掉异常
   → 修复: pm grant READ_PHONE_STATE + appops READ_DEVICE_IDENTIFIERS allow
2. XML 字段错误: <b>应 RLM-RMX5200, <f>应原厂 DISPLAY(RMX5200_16.0.9.402(CN01)),
   <g>应 01 (原值来自 backup/userdata/buildprop.txt + ctautoregist 逆向)
- 已逆向 ACK 协议: 10659401 回 [0x03][0x03] 头(OplusInboundSmsHandlerImpl)

### vendor 线索
- subsys_daemon(libqti-radio-service.so) 承载 ISubsysRadio/IImsOrtc,
  mSubsysRadioIndication null 每秒报错, GSI 无客户端(与一加13 GSI 无短信案例同特征)
- super.img(lpunpack 解包, LP v10.2)提取原厂分区发现 5 个缺失 subsystem jar
  → 反编译初判辅助功能(天线/WFC/RTP), 无 SMS 直接引用, 未定罪

### 剩余唯一未知
- modem SIP REGISTER 是否缺 +g.3gpp.smsip (SIP 走 modem 内部, 抓不到;
  DataChannel type=28 DISABLED 无法打开)
- 下次: ①卡槽2插联通/移动卡鉴别 CT 专属 vs 通用缺陷 ②备份后恢复原厂抓基线

### 工具链沉淀
- lpunpack 解包 super → 设备 mount -t erofs 浏览原厂分区
- QImsService VERBOSE 开关: setprop log.tag.QImsService VERBOSE
- radio buffer 抓 RILJ: logcat -b radio
