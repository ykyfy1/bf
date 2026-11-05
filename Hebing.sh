#!/bin/bash
# 合并远端2个m3u，合并后同时生成明文zubo.m3u 和加密 zubo.enc
# 环境变量：M3U_URL1 M3U_URL2 ENCRYPT_PASS

# 清理旧文件
rm -rf repo1.m3u repo2.m3u zubo.m3u zubo.enc
mkdir -p tmp

echo "===== 下载远端两个 m3u ====="
curl -sL "${M3U_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${M3U_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 1; }

echo "文件1大小: $(du -h repo1.m3u)"
echo "文件2大小: $(du -h repo2.m3u)"

# 合并 + 去重，只保留一次#EXTM3U
{
  echo "#EXTM3U"
  grep -v "#EXTM3U" repo1.m3u
  grep -v "#EXTM3U" repo2.m3u
} | awk '!seen[$0]++' > zubo.m3u

echo "✅m3u合并完成，输出 zubo.m3u"
echo "m3u最终行数：$(wc -l zubo.m3u)"

# AES-256-CBC 加密，和扫描仓库加密参数保持一致（解密必须用同样参数）
openssl enc -aes-256-cbc -md md5 -in zubo.m3u -out zubo.enc -k "${ENCRYPT_PASS}"

echo "✅加密完成，生成 zubo.enc"
ls -lh zubo.m3u zubo.enc
