.class public Lcom/chidc/ctreg/SendReceiver;
.super Landroid/content/BroadcastReceiver;
.source "SendReceiver.java"

.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V

    return-void
.end method

.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 11

    const-string v0, "CTReg"

    :try_start_0
    const-string v1, "phone"

    invoke-virtual {p1, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroid/telephony/TelephonyManager;

    if-nez v1, :cond_noimsi

    const-string v2, ""

    goto :goto_imsi

    :cond_noimsi
    :try_imsi
    invoke-virtual {v1}, Landroid/telephony/TelephonyManager;->getSubscriberId()Ljava/lang/String;

    move-result-object v2
    :try_imsi_end
    .catch Ljava/lang/Exception; {:try_imsi .. :try_imsi_end} :imsi_fail

    if-nez v2, :goto_imsi

    :imsi_fail
    const-string v2, ""

    :goto_imsi
    invoke-virtual {v1}, Landroid/telephony/TelephonyManager;->getSimOperator()Ljava/lang/String;

    move-result-object v9

    if-nez v9, :cond_op

    const-string v9, ""

    :cond_op
    sget-object v3, Landroid/os/Build;->DISPLAY:Ljava/lang/String;

    if-nez v3, :cond_disp

    const-string v3, ""

    :cond_disp
    new-instance v4, Ljava/lang/StringBuilder;

    invoke-direct {v4}, Ljava/lang/StringBuilder;-><init>()V

    const-string v5, "<a><b>RLM-CN<c>"

    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4, v9}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v5, "<d>000000000000000<e>"

    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4, v9}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v5, "<f>"

    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v5, "<g></a>"

    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v5

    const-string v6, "XML: "

    invoke-static {v0, v6}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    invoke-virtual {v5}, Ljava/lang/String;->getBytes()[B

    move-result-object v6

    array-length v7, v6

    int-to-byte v7, v7

    add-int/lit8 v8, v7, 0x4

    new-array v8, v8, [B

    const/4 v9, 0x0

    const/4 v10, 0x4

    aput-byte v10, v8, v9

    const/4 v10, 0x1

    const/4 v9, 0x3

    aput-byte v9, v8, v10

    const/4 v9, 0x2

    aput-byte v7, v8, v9

    const/4 v9, 0x3

    const/4 v10, 0x0

    aput-byte v10, v8, v9

    array-length v9, v6

    const/4 v10, 0x0

    :loop_copy
    if-ge v10, v9, :cond_copy_done

    aget-byte v7, v6, v10

    add-int/lit8 v0, v10, 0x4

    aput-byte v7, v8, v0

    add-int/lit8 v10, v10, 0x1

    goto :loop_copy

    :cond_copy_done
    invoke-static {}, Landroid/telephony/SmsManager;->getDefault()Landroid/telephony/SmsManager;

    move-result-object v0

    const-string v6, "10659401"

    const/4 v7, 0x0

    const/4 v9, 0x0

    const/4 v10, 0x0

    move-object v1, v0

    move-object v2, v6

    move-object v3, v7

    move v4, v9

    move-object v5, v8

    move-object v6, v10

    move-object v7, v10

    invoke-virtual/range {v1 .. v7}, Landroid/telephony/SmsManager;->sendDataMessage(Ljava/lang/String;Ljava/lang/String;S[BLandroid/app/PendingIntent;Landroid/app/PendingIntent;)V

    const-string v0, "CTReg"

    const-string v1, "REGISTER SMS SENT"

    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0

    goto :goto_end

    :catch_0
    move-exception v0

    const-string v1, "CTReg"

    const-string v2, "SEND FAILED"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    :goto_end
    return-void
.end method
