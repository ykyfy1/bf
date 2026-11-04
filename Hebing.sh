#!/bin/bash
# ====================== 独立合并脚本：只合并远端2个zubo.enc，不跑IP扫描 ======================
# 链接放到Github Secrets，脚本从环境变量读取，不写死在代码

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧文件
rm -rf txt repo1.enc repo2.enc repo1.txt repo2.txt zubo.tar zubo.enc zubo.txt zubo.m3u
mkdir -p txt

echo "===== 下载远端两个加密包 ====="
curl -sL "${ENC_URL1}" -o repo1.enc || { echo "仓库1 enc下载失败"; exit 1; }
curl -sL "${ENC_URL2}" -o repo2.enc || { echo "仓库2 enc下载失败"; exit 1; }

echo "===== 解密两个enc包 ====="
# 远端enc加密的是单个zubo.txt，解密直接输出txt，不需要tar
openssl enc -d -aes-256-cbc -in repo1.enc -out repo1.txt -k "${ENCRYPT_PASS}"
openssl enc -d -aes-256-cbc -in repo2.enc -out repo2.txt -k "${ENCRYPT_PASS}"

echo "===== 远端源合并完成，开始同频道分组+按速度降序排序 ====="
# 读取解密出来的两个txt文件
awk -F',' '
BEGIN{OFS="\t"}
{
    if($0 ~ /速度=([0-9]+)/){
        split($0,sp,"速度=")
        split(sp[2],v,"KB")
        speed=v[1]+0
    }else{
        speed=0
    }
    chan=$2
    arr[chan][speed][NR]=$0
    speed_list[chan][speed]=1
}
END{
    for(chan in arr){
        n=asorti(speed_list[chan],s,"@ind_num_desc")
        for(i=1;i<=n;i++){
            s=s[i]
            for(line in arr[chan][s]){
                print arr[chan][s][line]
            }
        }
    }
}' repo1.txt repo2.txt > zubo.txt

# 去重
awk '!seen[$0]++' zubo.txt > zubo_tmp.txt && mv zubo_tmp.txt zubo.txt

# 取合并后总前MERGE_TOP_COUNT条
head -n ${MERGE_TOP_COUNT} zubo.txt > zubo_tmp.txt && mv zubo_tmp.txt zubo.txt

# ===================== 新增：生成播放器可用的 zubo.m3u =====================
echo "#EXTM3U" > zubo.m3u
while IFS= read -r line
do
    # 格式：IP,频道名,速度=xxKB
    ip=$(echo "$line" | cut -d',' -f1)
    name=$(echo "$line" | cut -d',' -f2)
    # udp模板，和你采集仓库保持一致
    echo "#EXTINF:-1,${name}" >> zubo.m3u
    echo "http://${ip}/udp/239.255.255.250:1234" >> zubo.m3u
done < zubo.txt

# 把本次合并后的zubo.txt放入txt目录，用于打包加密
cp zubo.txt ./txt/

echo "===== 打包txt目录并加密生成zubo.enc ====="
tar -cf zubo.tar ./txt
openssl enc -aes-256-cbc -salt -in zubo.tar -out zubo.enc -k "${ENCRYPT_PASS}"

# ✅ 删除明文，保留 zubo.m3u 和 zubo.enc
rm -rf txt zubo.tar zubo.txt repo1.enc repo2.enc repo1.txt repo2.txt
echo "===== 合并加密完成，明文全部清除，保留 zubo.enc + zubo.m3u ====="
