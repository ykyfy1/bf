#!/bin/bash
# ====================== 合并脚本：直接下载2个远端 zubo.m3u 合并 ======================
# 链接放到Github Secrets，读取ENC_URL1 ENC_URL2，两个都是pages.dev/zubo.m3u

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧文件
rm -rf txt repo1.m3u repo2.m3u zubo.txt zubo.m3u index.html
mkdir -p txt

echo "===== 下载远端两个 m3u 文件 ====="
curl -sL "${ENC_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${ENC_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 1; }

echo "repo1.m3u size: $(du -h repo1.m3u)"
echo "repo2.m3u size: $(du -h repo2.m3u)"

# 合并，去重，保留m3u格式
> zubo.txt
# 写入m3u头部
echo "#EXTM3U" > zubo.txt

# 合并两个m3u，去掉重复行（跳过#EXTM3U重复表头）
cat repo1.m3u repo2.m3u | grep -v "^#EXTM3U$" | sort -u >> zubo.txt

echo "===== 合并完成，总行数：$(wc -l zubo.txt)"
# 兜底空文件
if [ ! -s zubo.txt ]; then
  echo "#EXTM3U" > zubo.txt
  echo "# 暂无合并IPTV数据" >> zubo.txt
fi
