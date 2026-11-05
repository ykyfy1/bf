#!/bin/bash
# ====================== 独立合并脚本：读取M3U_URL1 M3U_URL2 ======================
# 直接读取仓库secret的M3U_URL1 M3U_URL2

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧文件
rm -rf txt repo1.m3u repo2.m3u zubo.txt zubo.m3u index.html
mkdir -p txt

echo "===== 下载远端两个m3u文件 ====="
echo "DEBUG M3U_URL1: >${M3U_URL1}<"
echo "DEBUG M3U_URL2: >${M3U_URL2}<"

curl -sL "${M3U_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${M3U_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 2; }

echo "repo1.m3u size: $(du -h repo1.m3u)"
echo "repo2.m3u size: $(du -h repo2.m3u)"

# 合并，去重，剔除多余#EXTM3U
> zubo.txt
echo "#EXTM3U" > zubo.txt
cat repo1.m3u repo2.m3u | grep -v "^#EXTM3U$" | sort -u >> zubo.txt

echo "===== 合并完成，总行数：$(wc -l zubo.txt)"
# 空文件兜底
if [ ! -s zubo.txt ]; then
  echo "#EXTM3U" > zubo.txt
  echo "# 暂无有效IP" >> zubo.txt
fi
