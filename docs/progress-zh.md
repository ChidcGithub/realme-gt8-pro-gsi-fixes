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
3. 性能调度 v2:post-fs-data.d 同目录 01-perf.sh(walt 调参 + GPU + IO + VM)
4. Doze 收紧:settings put global device_idle_constants
5. 微信/支付宝已加 Magisk DenyList
6. **IMS 全链路打通(8/15)**:官方 IMS 应用移植 + SELinux 策略注入 → 已注册(SMS/VoLTE 启用),详见 B2/B3
7. **动画掉帧修复(8/16)**:
   - 病根:屏幕是 144Hz 面板(1440x3136,支持 60/90/120/144),但 GSI 把 peak/min_refresh_rate 锁死 60 → 全程 60Hz
   - 修复:settings put system peak_refresh_rate 144 + min_refresh_rate 120(settings db,持久)
   - 验证:SystemUI 掉帧 2.21%,桌面 1.76%(<5% 属旗舰正常);GPU 负载仅 10%
   - 渲染器:用户自行设 debug.hwui.renderer=skiavk,重启 SystemUI/桌面进程后已生效(Pipeline=Skia (Vulkan))
   - 刷新率最终配置:peak=144 / min=60(待机 60,滑动升 144,已生效)
8. **相机→多任务卡顿修复(8/16)**:GCam 打开时主动把屏幕锁 60Hz,切多任务瞬间 60→120 模式切换撞动画 → min_refresh_rate 提到 120 解决(相机期间也保持 120Hz,零切换,已实测顺滑;代价亮屏略耗电)
9. **续航项(8/16)**:adaptive_battery_management_enabled=1;Doze 参数保持收紧版;wifi_scan_always_enabled=1 待用户决定

## 未解决(下次继续)
### A. 蓝牙 A2DP 无声(HFP 正常,媒体没声)
- 已排除:媒体音频开关、SBC 编码、A2DP offload 禁用(prop persist.sys.phh.disable_a2dp_offload=1)
- 诊断:插线后 dumpsys audio + logcat 抓 audioserver 打开 A2DP 输出失败点
- 候选:音频策略 XML 不匹配 oplus HAL / 编解码协商 / vendor 库缺失 / fluoride 栈

### B. IMS 不注册 → 短信电话不通(进度:85%,重大突破 8/15)
- 已修复:CarrierConfig 覆盖(volte_available=true 等)→ /data/user_de/0/com.android.phone/files/carrierconfig-com.android.carrierconfig-overlay-<redacted-ICCID>-2237.xml(纯文本 XML,持久生效)
- 已确认:cmd phone ims enable 可用;cafims/cafims_telephony overlay 已启用;modem 有 IMS 事件
- 卡点:org.codeaurora.ims(phh IMS APK)未注册 vendor ImsRadio 指示回调(indCb null)→ 无 SIP 注册

### B2. IMS 官方应用移植(8/15 已完成大部分!)
- 已从 super.img 解出 stock system_ext_a.img(1.1GB,EROFS,手机上 loop mount 查看)
- stock IMS 应用 = /system_ext/priv-app/ims/ims.apk(org.codeaurora.ims,API36,自含 AIDL 类)
- 病根链条(全部解决):
  1. APK manifest 有 <overlay> 声明,要求 persist.oplus.qspa.modem=enabled → 模块 system.prop 设置
  2. manifest 需 3 个 shared library(qti-telephony-hidl-wrapper/qti-telephony-utils/ims-ext-common)→ 模块提供 jar + permissions XML(ims-ext-common 声明是自造的)
  3. APK 与 oplus-ims-ext.jar 的 ImsApp.onCreate 均引用 OplusFeatureConfigManager → dex 二进制补丁(12 字节:const/4+const-string+if-eqz+2nop 跳转到 :cond_0,跳过特征检查;校验和已重算)
  4. sLogMgr/sRilInner 两个 getFeature 调用引用缺失框架类 → dex 二进制补丁(改为 sget DEFAULT + sput + nop)
  5. make() 调用(OplusImsServiceControllerExt,超类在缺失的 stock 框架)→ nop 掉
  6. ImsSenderRxr.<init> 尾部 OplusFeatureHelper(com.android.internal.telephony)→ 补丁为 isTablet=false
  7. oplus-ims-ext.jar 内藏 70+ 个 org.codeaurora.ims 类副本,会遮蔽 APK 的类 → 整个 jar 替换为最小空 jar(983B,只有占位类,保留 ims-ext-common 库名)
  8. 缺失类补充:从 phh GSI 版 apk 提取 QtiCarrierConfigHelper 等 27 个类 + org.codeaurora.telephony.utils 包(14 类)→ 打进 qti-telephony-utils.jar(替换原空壳)
  9. QtiCarrierConfigHelper.registerReceiver 无导出标志(API33 写法,Android14+ 崩)→ smali 加 RECEIVER_NOT_EXPORTED + .locals 6
  10. com.oplus.nec.OplusNecManager 缺失 → 手写空桩类打进 qti-utils jar
- 现状(已验证,重启后自动恢复):
  - org.codeaurora.ims 以 priv-app 稳定运行(不再崩溃)
  - 框架自动绑定:Binding ImsService → ImsServiceController added(MMTEL+EMERGENCY_MMTEL,slot0,subId1)
  - FeatureContainer 已创建(imsFeature/imsConfig/imsRegistration binder 齐全),state=UNAVAILABLE
- 剩余卡点:app 未收到 RIL 激活信号(EVENT_RADIO_AVAILABLE / registerForRadioEvents 的单卡直连初始化),未连接 vendor.qti.hardware.radio.ims.IImsRadio/imsradio0,故无 SIP 注册
  - 方向:ImsSubController.registerForRadioEvents → maybeInitDefaultSubscriptionStatus() 返回 false(多卡分支),需查单卡模式为何没走直连;或查 ImsRadioAidl 的 waitForDeclaredService 是否卡住/需要补事件触发
  - 注:app 的 Log 类(com.qualcomm.ims.utils.Log)也可能缺失,若走到日志路径会崩,注意观察

### B3. SELinux + IMS 注册(8/15 完成!!)
- 真正卡点 = SELinux:app 进程域是 priv_app,GSI 策略不允许访问 vendor 的 IMS 服务
  - "SELinux denied for service"(servicemanager 检查)+ dmesg:rild→priv_app binder call denied
- 修复:模块 post-fs-data.sh 用 magiskpolicy --live 注入(vendor 类型在 magisk 早期应用 sepolicy.rule 时还没加载,所以必须用脚本晚注入):
  - priv_app → vendor_hal_telephony_service2 / hal_radio_service / vendor_aidl_imsfactory_service / vendor_hal_imsrtp_service / vendor_hal_imsdc_service / vendor_aidl_rcsservice 的 service_manager find + binder call/transfer
  - 反向:rild / vendor_ims_service / vendor_ims_dcservice / vendor_hal_imsrtp → priv_app binder call/transfer
- 结果(已实测):
  - ImsRadioAidl 连接成功("initImsRadio: imsRadio availability: available[SUB0]")
  - REQUEST_QUERY_SERVICE_STATUS / GET_IMS_CONFIG 双向收发正常
  - REQUEST_IMS_REGISTRATION_STATE → state:1(已注册);onRegistrationChanged/onServiceStatusChanged 事件正常
  - REQUEST_SET_SERVICE_STATUS [SMS=1,VoLTE=1,UT=1 全部启用]
  - IMS PDN(APN ims)已建链并拿到 P-CSCF 地址
  - **StatusForAccessTech registered=2 status=0;mMtelCapabilities [Voice/Video/UT/SMS 全部 true] → IMS 完整注册!!**
  - 框架侧 MMTEL 特性 state=READY,绑定自动恢复
- 待用户实测:发短信、打电话(应有 VoLTE/HD 图标)
- 实测结果(8/15 晚):
  - ✅ 短信发送成功(走 IMS 注册路径)
  - ❌ 短信收不到(MT 无任何 onIncomingSms/onNewSms 指示,待查 modem 侧路由)
  - ⚠️ 电话:拨号已能到 modem(Dial Request → DIALING → 挂断也正常),但被 **CallFailCause 1502** 快速拒绝(END)。modem 拨号后切到 LTE 试图 VoLTE(5G SA 需 EPS 回落),INVITE 被拒后弹回 NR
    - 猜测:EPS 回落路径的 IMS PDN/SIP 注册没有在 LTE 上建立;或 CT 运营商 MBN 配置在 GSI 下未生效
    - 下次方向:①用设置里关 5G(网络模式切 4G)试打电话,验证 EPS 回落假设;②抓 modem 侧 SIP 日志(diag);③查 MBN 加载情况
- 8/15 晚追加调查(4G 也秒挂):
  - 4G 下同样失败 → 排除 EPS 回落;故障在 modem 侧 SIP 栈本身
  - 全链路已通:framework→app→ImsRadio→modem 双向正常;IMS PDN/P-CSCF 正常
  - 解码:CALL_FAIL 553=RADIO_INTERNAL_ERROR;modem 注册状态部分服务 registered=2、多数 registered=1(REGISTERING 卡住)
  - 电话失败时 accTechStatus registered=0(LTE 和 NR 都 0)
  - **新线索:vendor.oplus.hardware.ims.IImsStable/OplusImsRadio0/1 在 GSI 上没有任何客户端连接**——stock 的 oplus 框架通过这个接口给 modem 下发 IMS 供应配置(VoLTE 使能等),GSI 下缺失 → modem 的 SIP 注册不完整 → 呼叫被拒 + MT 短信不达
  - 下次方向:逆向 oplus ImsRadio AIDL 接口(vendor.oplus.hardware.ims),实现最小配置下发;或抓 modem diag 确认 SIP 注册失败原因

### B4. 呼叫失败根因分析(8/15 深夜,重要更正!)
- **枚举更正**:AIDL RegState:REGISTERED=1 / NOT_REGISTERED=2 / REGISTERING=3 → 之前的日志解读反了
  - 实际:modem 的 IMS 注册**正常**(registered=1=REGISTERED;部分服务 registered=2=NOT_REGISTERED 属正常,如 CT 不支持 SMS-over-IMS)
- **1502 解码**:IMSA_VERBOSE_CALL_END_REASON_DIAL_FAILED_CS_RETRY_REQUIRED——modem 的 SIP INVITE 失败,建议框架改走 CS 重拨
  - 电信已退网 CDMA,无 CS 回退 → CS 重拨必失败 → **必须让 INVITE 成功**
- **oplus ImsRadio 接口已逆向**(vendor.oplus.hardware.ims.V1,AIDL):
  - IOplusImsRadio:setCallback / sendOemCommand(int,int,String) / queryVopsStatus(int)
  - 回调:sendOemCommandResponse / queryVopsStatusResponse(int,int,bool) / oemCommonInd(String)
  - 很小,只是 OEM 命令通道+VoPS 查询,**大概率不是注册/呼叫的关键**(modem 自己跑 SIP)
- 剩余方向(下次):
  1. 抓 Qualcomm diag(QXDM/PCAP)看 modem 的 SIP REGISTER/INVITE 报文,确认 INVITE 失败原因(网络拒绝码/本地失败)
  2. 或逆向 stock 的 oplus 框架通过 OplusImsRadio 发了什么 OEM 命令(也许有 VOLTE 使能类命令)
  3. MT 短信:同样等 diag 确认 SMS 路由

### B5. 电话接通!!(8/15 深夜大突破)
- **电话已能接通**(DIALING→ALERTING→ACTIVE),10000 能拨通并接通
- **真正修复 = 3 个缺失方法桩**(getIntArray/isGlassesFree3DVideoSupported/isVisualizedVoiceSupported)——之前 app 在通话状态更新时崩溃导致呼叫夭折
- 加密标志实验结论:**isEncrypted 与接通无关**——强制 false 时电话正常接通;强制 true(12 B1 正确编码)反而卡 DIALING → 已回滚到 false(12 0B 状态,即原始行为)
- **剩余问题:接通无声音** —— RTP 计数 0(收发都是 0),媒体没流动
  - app 不连接 ImsRtpService(媒体栈在 vendor 内部:modem↔ims_rtp_daemon↔音频 HAL)
  - 音频 HAL 无语音会话活动(通话期间 PAL/AHAL 静默)
  - modem 报 call isEncrypted=false;InCall VoicePrivacy disabled
  - 推断:modem 的媒体 SA(SRTP/IPsec 媒体面)未建立 → 网络媒体被丢 → 无 PCM
  - 下次方向:diag 抓媒体面;或查 modem 的媒体 SA 建立(QCRIL 的 media 配置)
- 附带修复:删除了 phh 的 "PHH IMS" APN(电信 CT IMS APN 已接管,IPV4V6)
- 已归档:qcc10.jar(含全部缺失类+桩)、ims_rv_s.apk(当前运行版,加密=false)
- 模块文件:手机 /data/adb/modules/stockims;电脑存档 Flash\stockims-module\(含 apk/jar/全部脚本)
- 素材:stock system_ext 已 push 到手机 /data/local/tmp/(system_ext_a.img 等),mount 命令见会话记录

### 蓝牙 A2DP(已定性)
- 已尝试:offload 关闭/SBC/策略模块 remap(sysbta/bluetooth/bluetooth_qti)/VINTF/原生路径
- 已修复:phh-prop-handler.sh 语法 bug(bluetooth_fix 分支缺空格),已 bind mount 修补版
- 结论:PandoraEx 栈与 sysbta HAL 会话对不上(has NO port state observer),需 GSI 重建

### 下次方向:从 super.img 提取 oplus 官方 IMS 应用
- 工具:Windows 版 lpunpack 已找到 https://github.com/Rprop/aosp15_partition_tools(windows_x86/lpunpack.exe)
- super.img 分区表已解析(system_a 945MB EROFS @ 已知偏移)
- 思路:lpunpack 解出 system_a.img → 提取 stock IMS 应用(com.android.ims/com.oplus.ims)→ Magisk 模块
- 风险:依赖 oplus 框架库,可能连锁缺失;成功率中低
- 同时可提取:stock 运营商配置(修电梯信号)、stock 相机 app(200MP,同样依赖框架)
### C. 电梯信号差(和 B 同根:运营商 MBN 配置缺失)
- 修好 B 大概率一并解决;临时方案 LTE 优先

### D. 相机 2 亿像素(可行性 <20%)
- 验证:Camera2 元数据是否暴露全像素流 → 暴露则 Open Camera 可选;否则认命

## 关键文件位置
- 手机:/data/adb/post-fs-data.d/{spoof.sh, fixfake.sh} /data/adb/service.d/01-perf.sh
- 电脑:Flash\01-perf.sh
- super.img 解析脚本:临时目录已写过,可用 python 重跑(几何 4096/8192,元数据头 0x3000,表偏移=头+256+offset)



### E. WiFi 问题(已诊断完,结论见下)
- **WiFi 6 实测正常**(11ax 864Mbps,家里 CYQZY 已连上);**WPA3 客户端也正常**(CYQZY 即 SAE 网络)
- **热点 WPA3 缺失**:vendor hostapd 不上报能力(cmd wifi get-softap-supported-features 返回空),框架收不到 WPA3-SAE 特性 → 设置里不显示选项;与蓝牙/IMS 同类(框架-vendor 握手),修起来性价比低
- **结论:热点继续用 WPA2+强密码即可,优先级排最后**
