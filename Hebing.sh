#!/bin/bash
# ====================== 独立合并脚本：只合并远端2个zubo.enc，不跑IP扫描 ======================

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧文件
rm -rf txt repo1.enc repo2.enc repo1.txt repo2.txt zubo.tar zubo.enc zubo.txt zubo.m3u
mkdir -p txt

echo "===== 下载远端两个加密包 ====="
curl -sL "${ENC_URL1}" -o repo1.enc || { echo "❌仓库1 enc下载失败"; exit 1; }
curl -sL "${ENC_URL2}" -o repo2.enc || { echo "❌仓库2 enc下载失败"; exit 1; }

echo "repo1.enc size: $(du -h repo1.enc)"
echo "repo2.enc size: $(du -h repo2.enc)"

echo "===== 解密两个enc包 ====="
# 远端加密只有 -salt，禁止-pbkdf2
openssl enc -d -aes-256-cbc -salt -in repo1.enc -out repo1.txt -k "${ENCRYPT_PASS}"
openssl enc -d -aes-256-cbc -salt -in repo2.enc -out repo2.txt -k "${ENCRYPT_PASS}"

# ----------------调试信息【关键，看日志这里输出】----------------
echo "====调试 repo1.txt 行数: $(wc -l repo1.txt)"
echo "====调试 repo2.txt 行数: $(wc -l repo2.txt)"
echo "----repo1.txt前6行----"
head -n6 repo1.txt
echo "----repo2.txt前6行----"
head -n6 repo2.txt
# ----------------------------------------------------------------

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

echo "====调试 zubo.txt合并后原始行数: $(wc -l zubo.txt)"

# 去重
awk '!seen[$0]++' zubo.txt > zubo_tmp.txt && mv zubo_tmp.txt zubo.txt
echo "====调试 去重后zubo.txt行数: $(wc -l zubo.txt)"

# 取合并后总前MERGE_TOP_COUNT条
head -n ${MERGE_TOP_COUNT} zubo.txt > zubo_tmp.txt && mv zubo_tmp.txt zubo.txt
echo "====调试 head截取后zubo.txt行数: $(wc -l zubo.txt)"

# 生成播放器m3u
echo "#EXTM3U" > zubo.m3u
# 如果zubo.txt为空，直接提示
if [ ! -s zubo.txt ];then
    echo "⚠️警告：zubo.txt是空！没有任何源数据！"
else
    while IFS= read -r line
    do
        ip=$(echo "$line" | cut -d',' -f1)
        name=$(echo "$line" | cut -d',' -f2)
        echo "#EXTINF:-1,${name}" >> zubo.m3u
        echo "http://${ip}/udp/239.255.255.250:1234" >> zubo.m3u
    done < zubo.txt
fi

# 打包加密备份
cp zubo.txt ./txt/ 2>/dev/null
echo "===== 打包txt目录并加密生成zubo.enc ====="
tar -cf zubo.tar ./txt
openssl enc -aes-256-cbc -salt -in zubo.tar -out zubo.enc -k "${ENCRYPT_PASS}"

# 清理明文
rm -rf txt zubo.tar zubo.txt repo1.enc repo2.enc repo1.txt repo2.txt
echo "===== 合并脚本执行结束，保留 zubo.enc + zubo.m3u ====="
