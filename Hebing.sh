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
# 远端enc：openssl -aes-256-cbc -salt，没有-pbkdf2！
openssl enc -d -aes-256-cbc -salt -in repo1.enc -out repo1.txt -k "${ENCRYPT_PASS}"
openssl enc -d -aes-256-cbc -salt -in repo2.enc -out repo2.txt -k "${ENCRYPT_PASS}"

echo "===== 远端源合并完成，开始同频道分组+按速度降序排序 ====="
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

# 生成播放器m3u（udp目前固定，后续采集脚本增加组播字段再优化）
echo "#EXTM3U" > zubo.m3u
while IFS= read -r line
do
    ip=$(echo "$line" | cut -d',' -f1)
    name=$(echo "$line" | cut -d',' -f2)
    echo "#EXTINF:-1,${name}" >> zubo.m3u
    echo "http://${ip}/udp/239.255.255.250:1234" >> zubo.m3u
done < zubo.txt

# 打包加密备份（本脚本输出的zubo.enc仅作为仓库备份，不需要传到CF）
cp zubo.txt ./txt/
echo "===== 打包txt目录并加密生成zubo.enc ====="
tar -cf zubo.tar ./txt
openssl enc -aes-256-cbc -salt -in zubo.tar -out zubo.enc -k "${ENCRYPT_PASS}"

# 清理明文，最终产物：zubo.m3u(给CF) 、 zubo.enc(本地备份)
rm -rf txt zubo.tar zubo.txt repo1.enc repo2.enc repo1.txt repo2.txt
echo "===== 合并完成，保留 zubo.enc + zubo.m3u ====="
