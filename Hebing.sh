#!/bin/bash
# 直接合并两份远端m3u明文，不使用openssl加密解密

# 清理临时文件
rm -rf src1.m3u src2.m3u merged.tmp final_body.tmp zubo.m3u

echo "===== 下载两份远端M3U源 ====="
curl -sL --connect-timeout 20 "${M3U_URL1}" -o src1.m3u
curl -sL --connect-timeout 20 "${M3U_URL2}" -o src2.m3u

# 校验下载是否成功
if [ ! -s src1.m3u ]; then
    echo "❌ M3U_URL1 下载失败或者内容为空"
    exit 1
fi
if [ ! -s src2.m3u ]; then
    echo "❌ M3U_URL2 下载失败或者内容为空"
    exit 1
fi

echo "src1.m3u 行数：$(wc -l src1.m3u)"
echo "src2.m3u 行数：$(wc -l src2.m3u)"

# 去除两份文件里的 #EXTM3U 表头
grep -v '^#EXTM3U' src1.m3u > merged.tmp
grep -v '^#EXTM3U' src2.m3u >> merged.tmp

# 根据播放URL去重，同一个链接只保留第一次出现
awk '
/^#EXTINF/ {
    inf=$0
    getline url
    if (!seen[url]++) {
        print inf
        print url
    }
}
' merged.tmp > final_body.tmp

# 组装最终输出m3u
echo "#EXTM3U" > zubo.m3u
cat final_body.tmp >> zubo.m3u

echo "✅ 合并完成，输出 zubo.m3u 总行数：$(wc -l zubo.m3u)"

# 删除临时文件
rm -rf src1.m3u src2.m3u merged.tmp final_body.tmp
